-- Unit tests for the pure layout engine (lib/arch_view/internal/layout.lua):
-- Tarjan SCC, Eades greedy feedback edges, longest-path layering, and the
-- unclebob arch-view coordinate formulas. No filesystem access here except
-- one end-to-end analyzer test at the bottom (tmp-dir project with a cycle).

local layout = require("arch_view.internal.layout")

local helpers = dofile("tests/helpers.lua")

local _assert_eq = helpers.assert_eq

local function _assert_near(actual, expected, message)
    if math.abs(actual - expected) > 1e-9 then
        error((message or "values differ") .. "\nexpected: " .. tostring(expected) .. "\nactual: " .. tostring(actual))
    end
end

local function _assert_true(value, message)
    if not value then
        error(message or "expected truthy value")
    end
end

local function _sorted_components(components)
    local out = {}
    for _, component in ipairs(components) do
        local copy = {}
        for _, id in ipairs(component) do
            copy[#copy + 1] = id
        end
        table.sort(copy)
        out[#out + 1] = table.concat(copy, ",")
    end
    table.sort(out)
    return out
end

-- Tarjan: a 3-node cycle plus an isolated node yields one 3-node component
-- and one singleton.
local function test_tarjan_finds_cycle_component()
    local components = layout.strongly_connected_components({ "a", "b", "c", "d" }, {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    })
    local shapes = _sorted_components(components)
    _assert_eq(#shapes, 2, "should find two components")
    _assert_eq(shapes[1], "a,b,c")
    _assert_eq(shapes[2], "d")
end

-- A single-node component with a self-loop counts as a cycle component.
local function test_tarjan_self_loop_is_cyclic()
    local edges = { { from = "a", to = "a" } }
    local components = layout.strongly_connected_components({ "a" }, edges)
    _assert_eq(#components, 1, "self-loop node stays one component")
    _assert_eq(#components[1], 1)
    _assert_true(layout.cyclic_component(components[1], edges), "self-loop component is cyclic")
end

-- Plain DAG edges never form cyclic components.
local function test_acyclic_components_not_cyclic()
    local edges = { { from = "a", to = "b" } }
    local components = layout.strongly_connected_components({ "a", "b" }, edges)
    _assert_eq(#components, 2, "DAG yields singleton components")
    for _, component in ipairs(components) do
        _assert_true(not layout.cyclic_component(component, edges), "singleton without self-loop is acyclic")
    end
end

-- Greedy order, source branch: the unique source goes left first.
local function test_greedy_order_sources_first()
    local order = layout.greedy_order({ "s", "a", "b" }, {
        { from = "s", to = "a" },
        { from = "a", to = "b" },
        { from = "b", to = "a" },
    })
    _assert_eq(#order, 3)
    _assert_eq(order[1], "s", "source should be placed leftmost")
end

-- Greedy order, sink branch: with no source available, the sink goes right.
local function test_greedy_order_sinks_go_right()
    local order = layout.greedy_order({ "a", "b", "t" }, {
        { from = "a", to = "b" },
        { from = "b", to = "a" },
        { from = "b", to = "t" },
    })
    _assert_eq(#order, 3)
    _assert_eq(order[3], "t", "sink should be placed rightmost")
end

-- Greedy order, degree-difference branch: no source and no sink, so the node
-- with the largest out-degree minus in-degree goes left.
local function test_greedy_order_max_degree_diff_goes_left()
    local order = layout.greedy_order({ "a", "b", "c" }, {
        { from = "a", to = "b" },
        { from = "a", to = "c" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    })
    _assert_eq(order[1], "a", "largest out-in difference should be placed leftmost")
end

-- Greedy order, degree-difference tie: equal differences fall back to the
-- lexicographically largest name (matches the JS/Clojure original).
local function test_greedy_order_tie_prefers_largest_name()
    local order = layout.greedy_order({ "a", "b", "c" }, {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    })
    _assert_eq(order[1], "c", "tied differences should pick the largest name")
end

-- Feedback edges are exactly the backward edges in the greedy linear order.
local function test_feedback_edges_are_backward_in_linear_order()
    local edges = {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    }
    local feedback = layout.feedback_edge_set({ "a", "b", "c" }, edges)
    -- greedy order is [c, a, b]: c wins the degree tie, then a is a source.
    -- Only b->c runs backward, so it alone is removed.
    _assert_true(feedback[layout.edge_key("b", "c")], "b->c should be a feedback edge")
    _assert_true(not feedback[layout.edge_key("a", "b")], "a->b follows the order")
    _assert_true(not feedback[layout.edge_key("c", "a")], "c->a follows the order")
end

-- Self-loop is always a feedback edge.
local function test_feedback_edges_include_self_loops()
    local feedback = layout.feedback_edge_set({ "a" }, { { from = "a", to = "a" } })
    _assert_true(feedback[layout.edge_key("a", "a")], "self-loop should be a feedback edge")
end

-- Longest-path layering on a chain: the node nobody depends on sits at
-- level 1, each dependent layer one deeper.
local function test_topological_levels_chain()
    local levels = layout.topological_levels({ "a", "b", "c" }, {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
    })
    _assert_eq(levels["a"], 1)
    _assert_eq(levels["b"], 2)
    _assert_eq(levels["c"], 3)
end

-- Diamond: a node with two parents lands one below the deeper parent.
local function test_topological_levels_diamond()
    local levels = layout.topological_levels({ "a", "b", "c", "d" }, {
        { from = "a", to = "b" },
        { from = "a", to = "c" },
        { from = "b", to = "d" },
        { from = "c", to = "d" },
    })
    _assert_eq(levels["a"], 1)
    _assert_eq(levels["b"], 2)
    _assert_eq(levels["c"], 2)
    _assert_eq(levels["d"], 3)
end

-- assign_layers groups nodes per level, row = level - 1, modules sorted.
local function test_assign_layers_groups_sorted()
    local assigned = layout.assign_layers({ "d", "c", "b", "a" }, {
        { from = "a", to = "c" },
        { from = "b", to = "c" },
    })
    _assert_eq(#assigned.layers, 2, "expected two layers")
    _assert_eq(assigned.layers[1].level, 1)
    _assert_eq(assigned.layers[1].row, 0)
    _assert_eq(table.concat(assigned.layers[1].modules, ","), "a,b,d", "same-level modules sorted lexicographically")
    _assert_eq(assigned.layers[2].level, 2)
    _assert_eq(assigned.layers[2].row, 1)
    _assert_eq(table.concat(assigned.layers[2].modules, ","), "c")
end

-- assign_layers strips feedback edges out of the acyclic remainder.
local function test_assign_layers_marks_feedback()
    local assigned = layout.assign_layers({ "a", "b" }, {
        { from = "a", to = "b" },
        { from = "b", to = "a" },
    })
    local feedback_count = 0
    for _ in pairs(assigned.feedback) do
        feedback_count = feedback_count + 1
    end
    _assert_eq(feedback_count, 1, "two-node cycle yields one feedback edge")
    _assert_eq(#assigned.acyclic_edges, 1, "acyclic remainder keeps the other edge")
    _assert_eq(#assigned.edges, 2, "normalized edge list keeps both")
end

-- Coordinates, centered case: two peers fit at the preferred 1.5x spacing
-- and the group is centered on the canvas.
local function test_centered_peer_x_centered()
    local rect_width = 0.5 * layout.track_width(1200)
    local x0 = layout.centered_peer_x(1200, rect_width, 0, 2)
    local x1 = layout.centered_peer_x(1200, rect_width, 1, 2)
    _assert_near(x0, 468.0, "first peer x")
    _assert_near(x1, 468.0 + rect_width * 1.5, "second peer at preferred spacing")
    local group_center = (x0 + x1 + rect_width) / 2
    _assert_near(group_center, 600.0, "group should be centered on the canvas")
end

-- Coordinates, compressed case: too many peers for the preferred spacing, so
-- spacing shrinks until the group exactly fills the usable width.
local function test_centered_peer_x_compressed()
    local rect_width = 0.5 * layout.track_width(1200)
    local x0 = layout.centered_peer_x(1200, rect_width, 0, 10)
    local x9 = layout.centered_peer_x(1200, rect_width, 9, 10)
    _assert_near(x0, 24.0, "compressed group starts at the margin")
    _assert_near(x9 + rect_width, 1200 - 24.0, "compressed group ends at the far margin")
    _assert_true(x9 - layout.centered_peer_x(1200, rect_width, 8, 10) < rect_width * 1.5,
        "compressed spacing is below the preferred 1.5x")
end

-- compute_view applies the unclebob geometry constants: track width from the
-- 1200px canvas, rect 0.5x track wide and 70 high, single node centered.
local function test_compute_view_rect_formula()
    local view = layout.compute_view({ "solo" }, {})
    local entry = view.nodes["solo"]
    _assert_eq(entry.level, 1)
    _assert_eq(entry.row, 0)
    _assert_near(entry.rect.width, 105.6, "rect width = 0.5 * track width")
    _assert_near(entry.rect.height, 70.0, "rect height = 0.5 * layer height")
    _assert_near(entry.rect.y, 42.0, "top row starts at the scene top padding")
    _assert_near(entry.rect.x, 547.2, "single peer centered")
end

-- Row 1 sits 1.5 rect heights below row 0.
local function test_compute_view_row_spacing()
    local view = layout.compute_view({ "top", "bottom" }, {
        { from = "top", to = "bottom" },
    })
    _assert_eq(view.nodes["top"].row, 0)
    _assert_eq(view.nodes["bottom"].row, 1)
    _assert_near(view.nodes["bottom"].rect.y, 42.0 + 70.0 * 1.5, "row spacing = 1.5 * rect height")
end

-- End-to-end: analyzer wires layout results into view nodes (layer, rect)
-- and marks the removed feedback edge with cycle_break = true.
local function test_analyzer_wires_layout_and_cycle_break()
    local arch_view = require("arch_view")
    local common = require("arch_view.runtime.common")

    helpers.with_clean_tmp("arch_view_test_layout", function(tmp_root)
        local project_root = common.join_path(tmp_root, "cycle_project")
        assert(common.ensure_dir(common.join_path(project_root, "src")))
        assert(common.write_file(common.join_path(project_root, "arch_view.config.json"), [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
}
]]))
        assert(common.write_file(common.join_path(project_root, "src/a.lua"), 'local b = require("src.b")\nreturn {}\n'))
        assert(common.write_file(common.join_path(project_root, "src/b.lua"), 'local a = require("src.a")\nreturn {}\n'))

        local architecture, analyze_err = arch_view.analyze({ project_root = project_root })
        if architecture == nil then
            error(analyze_err)
        end

        local root_view = architecture.views["root"]
        _assert_true(root_view ~= nil, "root view should exist")
        _assert_eq(#root_view.nodes, 2, "root view should have two nodes")
        _assert_eq(#root_view.display_edges, 2, "root view should have two edges")

        local node_by_id = {}
        for _, node in ipairs(root_view.nodes) do
            node_by_id[node.id] = node
            _assert_eq(type(node.layer), "number", "node.layer should be a layout row")
            _assert_eq(type(node.rect), "table", "node.rect should come from the layout engine")
            _assert_near(node.rect.width, 105.6, "rect width from layout engine")
            _assert_near(node.rect.height, 70.0, "rect height from layout engine")
        end
        -- greedy order is [b, a]; removing a->b leaves b->a, so b sits on top.
        _assert_eq(node_by_id["b"].layer, 0, "b should land on the top row")
        _assert_eq(node_by_id["a"].layer, 1, "a should land one row below")
        _assert_near(node_by_id["b"].rect.y, 42.0, "top row y")
        _assert_near(node_by_id["a"].rect.y, 42.0 + 70.0 * 1.5, "second row y")

        local break_count = 0
        for _, edge in ipairs(root_view.display_edges) do
            _assert_eq(type(edge.cycle_break), "boolean", "edge.cycle_break should be boolean")
            if edge.cycle_break then
                break_count = break_count + 1
                _assert_eq(edge.from, "a", "a->b is the backward edge in the greedy order")
                _assert_eq(edge.to, "b")
            end
        end
        _assert_eq(break_count, 1, "exactly one edge should be marked cycle_break")
    end)
end

return {
    test_tarjan_finds_cycle_component = test_tarjan_finds_cycle_component,
    test_tarjan_self_loop_is_cyclic = test_tarjan_self_loop_is_cyclic,
    test_acyclic_components_not_cyclic = test_acyclic_components_not_cyclic,
    test_greedy_order_sources_first = test_greedy_order_sources_first,
    test_greedy_order_sinks_go_right = test_greedy_order_sinks_go_right,
    test_greedy_order_max_degree_diff_goes_left = test_greedy_order_max_degree_diff_goes_left,
    test_greedy_order_tie_prefers_largest_name = test_greedy_order_tie_prefers_largest_name,
    test_feedback_edges_are_backward_in_linear_order = test_feedback_edges_are_backward_in_linear_order,
    test_feedback_edges_include_self_loops = test_feedback_edges_include_self_loops,
    test_topological_levels_chain = test_topological_levels_chain,
    test_topological_levels_diamond = test_topological_levels_diamond,
    test_assign_layers_groups_sorted = test_assign_layers_groups_sorted,
    test_assign_layers_marks_feedback = test_assign_layers_marks_feedback,
    test_centered_peer_x_centered = test_centered_peer_x_centered,
    test_centered_peer_x_compressed = test_centered_peer_x_compressed,
    test_compute_view_rect_formula = test_compute_view_rect_formula,
    test_compute_view_row_spacing = test_compute_view_row_spacing,
    test_analyzer_wires_layout_and_cycle_break = test_analyzer_wires_layout_and_cycle_break,
}
