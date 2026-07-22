-- Unit tests for the pure layout engine (lib/arch_view/internal/layout.lua):
-- Tarjan SCC, exact minimum feedback edge enumeration for small components,
-- Eades greedy fallback for larger ones, longest-path layering, and the
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

-- Small components (<= 8 nodes, <= 12 internal edges) use exact enumeration:
-- the first edge subset that leaves a DAG is removed. Greedy would have
-- picked b->c here (the backward edge of its linear order [c, a, b]); exact
-- picks a->b, the first working single-edge subset in input order.
local function test_feedback_edges_exact_minimum_for_small_cycle()
    local edges = {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    }
    local feedback = layout.feedback_edge_set({ "a", "b", "c" }, edges)
    _assert_true(feedback[layout.edge_key("a", "b")], "exact enumeration removes a->b")
    _assert_true(not feedback[layout.edge_key("b", "c")], "b->c stays (greedy would have picked it)")
    _assert_true(not feedback[layout.edge_key("c", "a")], "c->a stays")
end

-- exact_feedback_edges returns a mathematically minimal set: the two cycles
-- a->b->c->a and b->c->b share the edge b->c, so one removal breaks both.
local function test_exact_feedback_edges_minimal_double_cycle()
    local feedback = layout.exact_feedback_edges({ "a", "b", "c" }, {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
        { from = "c", to = "b" },
    })
    _assert_eq(#feedback, 1, "one edge breaks both cycles")
    _assert_eq(feedback[1].from, "b")
    _assert_eq(feedback[1].to, "c")
end

-- exact_feedback_edges on a DAG removes nothing (the k = 0 subset wins).
local function test_exact_feedback_edges_empty_on_dag()
    local feedback = layout.exact_feedback_edges({ "a", "b" }, {
        { from = "a", to = "b" },
    })
    _assert_eq(#feedback, 0, "DAG needs no feedback edges")
end

-- Boundary: exactly 8 nodes and 12 internal edges still qualifies for exact
-- enumeration. The only cycle is a->b->c->a; greedy would remove b->c, exact
-- removes a->b (the first working subset in input order).
local function test_feedback_edges_exact_at_size_boundary()
    local node_ids = { "a", "b", "c", "d", "e", "f", "g", "h" }
    local edges = {
        { from = "a", to = "b" },
        { from = "a", to = "d" },
        { from = "a", to = "e" },
        { from = "b", to = "c" },
        { from = "b", to = "d" },
        { from = "c", to = "a" },
        { from = "c", to = "e" },
        { from = "d", to = "e" },
        { from = "d", to = "f" },
        { from = "e", to = "f" },
        { from = "f", to = "g" },
        { from = "g", to = "h" },
    }
    local feedback = layout.feedback_edge_set(node_ids, edges)
    local count = 0
    for _ in pairs(feedback) do
        count = count + 1
    end
    _assert_eq(count, 1, "single-cycle component yields the minimum one-edge set")
    _assert_true(feedback[layout.edge_key("a", "b")], "exact enumeration removes a->b, not greedy's b->c")
end

-- Beyond the node threshold (9 nodes in the component) the component falls
-- back to the Eades greedy order [i, a, b, ..., h]; its only backward edge
-- is h->i, where exact enumeration would have removed a->b.
local function test_feedback_edges_greedy_beyond_node_threshold()
    local node_ids = { "a", "b", "c", "d", "e", "f", "g", "h", "i" }
    local edges = {}
    for index = 1, 8 do
        edges[#edges + 1] = { from = node_ids[index], to = node_ids[index + 1] }
    end
    edges[#edges + 1] = { from = "i", to = "a" }
    local feedback = layout.feedback_edge_set(node_ids, edges)
    _assert_true(feedback[layout.edge_key("h", "i")], "greedy order removes h->i")
    _assert_true(not feedback[layout.edge_key("a", "b")], "exact enumeration would have removed a->b")
end

-- Beyond the edge threshold (13 internal edges on 8 nodes) the component
-- also falls back to greedy, which removes three edges here; the exact
-- minimum for the same graph is a single edge.
local function test_feedback_edges_greedy_beyond_edge_threshold()
    local node_ids = { "a", "b", "c", "d", "e", "f", "g", "h" }
    local edges = {}
    for index = 1, 7 do
        edges[#edges + 1] = { from = node_ids[index], to = node_ids[index + 1] }
    end
    edges[#edges + 1] = { from = "h", to = "a" }
    edges[#edges + 1] = { from = "a", to = "c" }
    edges[#edges + 1] = { from = "b", to = "d" }
    edges[#edges + 1] = { from = "c", to = "e" }
    edges[#edges + 1] = { from = "d", to = "f" }
    edges[#edges + 1] = { from = "e", to = "g" }
    local feedback = layout.feedback_edge_set(node_ids, edges)
    _assert_true(feedback[layout.edge_key("a", "b")], "greedy removes a->b")
    _assert_true(feedback[layout.edge_key("c", "d")], "greedy removes c->d")
    _assert_true(feedback[layout.edge_key("c", "e")], "greedy removes c->e")
    local exact = layout.exact_feedback_edges(node_ids, edges)
    _assert_eq(#exact, 1, "the exact minimum for the same graph is one edge")
end

-- Self-loop is always a feedback edge.
local function test_feedback_edges_include_self_loops()
    local feedback = layout.feedback_edge_set({ "a" }, { { from = "a", to = "a" } })
    _assert_true(feedback[layout.edge_key("a", "a")], "self-loop should be a feedback edge")
end

-- BFS shortest path: neighbors are visited in lexicographic order, so the
-- first goal hit is the lexicographically earliest among the shortest paths.
local function test_shortest_path_bfs_lexicographic()
    local edges = {
        { from = "s", to = "b" },
        { from = "s", to = "a" },
        { from = "a", to = "t" },
        { from = "b", to = "t" },
        { from = "s", to = "t" },
    }
    local path = layout.shortest_path(edges, "s", "t")
    _assert_eq(table.concat(path, ","), "s,t", "direct edge is the shortest path")
    local detour = layout.shortest_path({
        { from = "s", to = "b" },
        { from = "s", to = "a" },
        { from = "a", to = "t" },
        { from = "b", to = "t" },
    }, "s", "t")
    _assert_eq(table.concat(detour, ","), "s,a,t", "lexicographically smallest neighbor first")
    _assert_eq(layout.shortest_path(edges, "t", "s"), nil, "no path returns nil")
end

-- A self-loop feedback edge closes on itself: a->a.
local function test_cycle_path_self_loop_closes_on_itself()
    local path = layout.cycle_path_for_feedback_edge({}, { from = "a", to = "a" })
    _assert_eq(table.concat(path, ","), "a,a")
end

-- cycle_paths: one closed a->...->a path per feedback edge, built from the
-- BFS shortest to->from path on the acyclic remainder, prefixed with from.
local function test_cycle_paths_closed_format()
    local node_ids = { "a", "b", "c" }
    local edges = {
        { from = "a", to = "b" },
        { from = "b", to = "c" },
        { from = "c", to = "a" },
    }
    local assigned = layout.assign_layers(node_ids, edges)
    -- exact enumeration removes a->b; the acyclic remainder routes b->c->a,
    -- closing the cycle as a->b->c->a.
    _assert_eq(#assigned.cycles, 1, "one feedback edge yields one cycle path")
    _assert_eq(table.concat(assigned.cycles[1], "->"), "a->b->c->a", "closed cycle format")
end

-- A DAG has no cycle paths at all.
local function test_cycle_paths_empty_on_dag()
    local assigned = layout.assign_layers({ "a", "b" }, {
        { from = "a", to = "b" },
    })
    _assert_eq(#assigned.cycles, 0, "DAG yields no cycle paths")
end

-- compute_view exposes the cyclic node set: both ends of a two-node cycle.
local function test_compute_view_marks_cyclic_nodes()
    local view = layout.compute_view({ "a", "b", "c" }, {
        { from = "a", to = "b" },
        { from = "b", to = "a" },
    })
    _assert_true(view.cyclic_nodes["a"], "a sits in the cycle")
    _assert_true(view.cyclic_nodes["b"], "b sits in the cycle")
    _assert_true(not view.cyclic_nodes["c"], "c is outside the cycle")
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
        _assert_eq(root_view.edges, nil, "contract v2 drops the edges/display_edges duplicate alias")

        local node_by_id = {}
        for _, node in ipairs(root_view.nodes) do
            node_by_id[node.id] = node
            _assert_eq(type(node.layer), "number", "node.layer should be a layout row")
            _assert_eq(type(node.rect), "table", "node.rect should come from the layout engine")
            _assert_near(node.rect.width, 105.6, "rect width from layout engine")
            _assert_near(node.rect.height, 70.0, "rect height from layout engine")
        end
        -- exact enumeration removes a->b (the first single-edge subset that
        -- leaves a DAG), so b sits on top.
        _assert_eq(node_by_id["b"].layer, 0, "b should land on the top row")
        _assert_eq(node_by_id["a"].layer, 1, "a should land one row below")
        _assert_near(node_by_id["b"].rect.y, 42.0, "top row y")
        _assert_near(node_by_id["a"].rect.y, 42.0 + 70.0 * 1.5, "second row y")

        local break_count = 0
        for _, edge in ipairs(root_view.display_edges) do
            _assert_eq(type(edge.cycle_break), "boolean", "edge.cycle_break should be boolean")
            _assert_eq(edge.arrowhead, nil, "contract v2 drops the dead arrowhead field")
            _assert_eq(edge.route_points, nil, "contract v2 drops the dead route_points field")
            if edge.cycle_break then
                break_count = break_count + 1
                _assert_eq(edge.from, "a", "a->b is the first exact single-edge subset leaving a DAG")
                _assert_eq(edge.to, "b")
            end
        end
        _assert_eq(break_count, 1, "exactly one edge should be marked cycle_break")

        -- Cycle readability fields are really filled (no constant false).
        _assert_true(node_by_id["a"].cycle, "a sits in the cycle component")
        _assert_true(node_by_id["b"].cycle, "b sits in the cycle component")
        _assert_eq(node_by_id["a"].has_cycle_subtree, false, "no subviews means no subtree cycle")
        _assert_eq(#root_view.cycle_lines, 1, "root view lists its own cycle")
        _assert_eq(root_view.cycle_lines[1], "a->b->a", "closed cycle line format")
    end)
end

-- has_cycle_subtree rolls up from deeper views: a cycle inside src.sub makes
-- the root-level node "sub" red even though the root view itself is acyclic.
local function test_analyzer_fills_has_cycle_subtree()
    local arch_view = require("arch_view")
    local common = require("arch_view.runtime.common")

    helpers.with_clean_tmp("arch_view_test_subtree_cycle", function(tmp_root)
        local project_root = common.join_path(tmp_root, "subtree_project")
        assert(common.ensure_dir(common.join_path(project_root, "src/sub")))
        assert(common.write_file(common.join_path(project_root, "arch_view.config.json"), [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
}
]]))
        assert(common.write_file(common.join_path(project_root, "src/top.lua"), 'local x = require("src.sub.x")\nreturn {}\n'))
        assert(common.write_file(common.join_path(project_root, "src/sub/x.lua"), 'local y = require("src.sub.y")\nreturn {}\n'))
        assert(common.write_file(common.join_path(project_root, "src/sub/y.lua"), 'local x = require("src.sub.x")\nreturn {}\n'))

        local architecture, analyze_err = arch_view.analyze({ project_root = project_root })
        if architecture == nil then
            error(analyze_err)
        end

        local root_view = architecture.views["root"]
        local sub_view = architecture.views["sub"]
        _assert_true(root_view ~= nil and sub_view ~= nil, "root and sub views should exist")

        local root_node_by_id = {}
        for _, node in ipairs(root_view.nodes) do
            root_node_by_id[node.id] = node
        end
        _assert_eq(root_node_by_id["sub"].cycle, false, "sub is not in a root-level cycle")
        _assert_true(root_node_by_id["sub"].has_cycle_subtree, "sub subtree contains the x<->y cycle")
        _assert_eq(root_node_by_id["top"].has_cycle_subtree, false, "top has no subtree cycle")

        local sub_node_by_id = {}
        for _, node in ipairs(sub_view.nodes) do
            sub_node_by_id[node.id] = node
        end
        _assert_true(sub_node_by_id["x"].cycle, "x sits in the sub view cycle")
        _assert_true(sub_node_by_id["y"].cycle, "y sits in the sub view cycle")

        -- The root view aggregates descendant cycle lines (full names carry
        -- the namespace prefix); the sub view lists only its own.
        _assert_eq(#sub_view.cycle_lines, 1)
        _assert_eq(sub_view.cycle_lines[1], "sub.x->sub.y->sub.x", "sub view cycle line")
        _assert_eq(#root_view.cycle_lines, 1, "root view aggregates the descendant cycle")
        _assert_eq(root_view.cycle_lines[1], "sub.x->sub.y->sub.x")
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
    test_feedback_edges_exact_minimum_for_small_cycle = test_feedback_edges_exact_minimum_for_small_cycle,
    test_exact_feedback_edges_minimal_double_cycle = test_exact_feedback_edges_minimal_double_cycle,
    test_exact_feedback_edges_empty_on_dag = test_exact_feedback_edges_empty_on_dag,
    test_feedback_edges_exact_at_size_boundary = test_feedback_edges_exact_at_size_boundary,
    test_feedback_edges_greedy_beyond_node_threshold = test_feedback_edges_greedy_beyond_node_threshold,
    test_feedback_edges_greedy_beyond_edge_threshold = test_feedback_edges_greedy_beyond_edge_threshold,
    test_feedback_edges_include_self_loops = test_feedback_edges_include_self_loops,
    test_shortest_path_bfs_lexicographic = test_shortest_path_bfs_lexicographic,
    test_cycle_path_self_loop_closes_on_itself = test_cycle_path_self_loop_closes_on_itself,
    test_cycle_paths_closed_format = test_cycle_paths_closed_format,
    test_cycle_paths_empty_on_dag = test_cycle_paths_empty_on_dag,
    test_compute_view_marks_cyclic_nodes = test_compute_view_marks_cyclic_nodes,
    test_topological_levels_chain = test_topological_levels_chain,
    test_topological_levels_diamond = test_topological_levels_diamond,
    test_assign_layers_groups_sorted = test_assign_layers_groups_sorted,
    test_assign_layers_marks_feedback = test_assign_layers_marks_feedback,
    test_centered_peer_x_centered = test_centered_peer_x_centered,
    test_centered_peer_x_compressed = test_centered_peer_x_compressed,
    test_compute_view_rect_formula = test_compute_view_rect_formula,
    test_compute_view_row_spacing = test_compute_view_row_spacing,
    test_analyzer_wires_layout_and_cycle_break = test_analyzer_wires_layout_and_cycle_break,
    test_analyzer_fills_has_cycle_subtree = test_analyzer_fills_has_cycle_subtree,
}
