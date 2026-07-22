-- Pure layout engine for arch_view views (no IO).
--
-- Ported function-by-function from the unclebob/arch-view layout pipeline
-- (src/arch_view/layout/layers.clj for the graph algorithms,
-- src/arch_view/render/ui/util/layout.clj for the geometry), via the verified
-- JS prototype of monopoly issue #221. Function semantics map one-to-one;
-- naming follows the repo snake_case convention.
--
-- Pipeline: normalize edges -> Tarjan SCC -> per-component feedback edge
-- removal (exact minimum-set enumeration for small components, Eades greedy
-- otherwise) -> longest-path layering on the remaining DAG ->
-- same-level lexicographic ordering -> centered peer coordinates on a fixed
-- 1200px canvas.
--
-- Edge direction: `from` depends on (requires) `to`. Nodes nobody depends on
-- (in-degree 0) sit at level 1 on top; each dependent layer goes one deeper.

local layout = {}

-- Geometry constants (unclebob layout.clj / canvas.clj).
layout.CANVAS_WIDTH = 1200.0
layout.SCENE_TOP_PADDING = 42.0
layout.RACETRACK_COUNT = 5
layout.RACETRACK_MARGIN = 24.0
layout.RACETRACK_GAP = 24.0
layout.LAYER_HEIGHT = 140.0
layout.RECT_SCALE = 0.5

-- Exact feedback edge enumeration thresholds (monopoly #228, layers.clj:5-6):
-- a component within both limits gets its exact minimum feedback edge set;
-- larger components keep the Eades greedy heuristic.
layout.EXACT_FEEDBACK_MAX_NODES = 8
layout.EXACT_FEEDBACK_MAX_EDGES = 12

function layout.edge_key(from_id, to_id)
  return tostring(from_id) .. "\0" .. tostring(to_id)
end

local function _sorted(values)
  table.sort(values)
  return values
end

local function _sorted_keys(set)
  local out = {}
  for value in pairs(set) do
    out[#out + 1] = value
  end
  return _sorted(out)
end

local function _to_set(values)
  local set = {}
  for _, value in ipairs(values or {}) do
    set[value] = true
  end
  return set
end

-- Drop dangling endpoints, dedupe, and sort by (from, to) for determinism.
function layout.normalize_edges(node_ids, edges)
  local nodes = _to_set(node_ids)
  local seen = {}
  local out = {}
  for _, edge in ipairs(edges or {}) do
    local from_id = edge.from
    local to_id = edge.to
    if from_id ~= nil and to_id ~= nil and nodes[from_id] and nodes[to_id] then
      local key = layout.edge_key(from_id, to_id)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = { from = from_id, to = to_id }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    return a.to < b.to
  end)
  return out
end

local function _outgoing_map(node_ids, edges)
  local map = {}
  for _, node_id in ipairs(node_ids) do
    map[node_id] = {}
  end
  for _, edge in ipairs(edges or {}) do
    if map[edge.from] ~= nil then
      map[edge.from][edge.to] = true
    end
  end
  return map
end

local function _incoming_map(node_ids, edges)
  local map = {}
  for _, node_id in ipairs(node_ids) do
    map[node_id] = {}
  end
  for _, edge in ipairs(edges or {}) do
    if map[edge.to] ~= nil then
      map[edge.to][edge.from] = true
    end
  end
  return map
end

-- Tarjan strongly connected components; adjacency and traversal both follow
-- lexicographic order to match the original.
function layout.strongly_connected_components(node_ids, edges)
  local adjacency = _outgoing_map(node_ids, edges)
  local index_counter = 0
  local stack = {}
  local on_stack = {}
  local index = {}
  local low = {}
  local components = {}

  local function strong_connect(v)
    index[v] = index_counter
    low[v] = index_counter
    index_counter = index_counter + 1
    stack[#stack + 1] = v
    on_stack[v] = true
    for _, w in ipairs(_sorted_keys(adjacency[v] or {})) do
      if index[w] == nil then
        strong_connect(w)
        low[v] = math.min(low[v], low[w])
      elseif on_stack[w] then
        low[v] = math.min(low[v], index[w])
      end
    end
    if low[v] == index[v] then
      local component = {}
      while true do
        local w = stack[#stack]
        stack[#stack] = nil
        on_stack[w] = nil
        component[#component + 1] = w
        if w == v then
          break
        end
      end
      components[#components + 1] = component
    end
  end

  for _, node_id in ipairs(_sorted_keys(_to_set(node_ids))) do
    if index[node_id] == nil then
      strong_connect(node_id)
    end
  end
  return components
end

local function _has_self_loop(component, edges)
  local set = _to_set(component)
  for _, edge in ipairs(edges or {}) do
    if edge.from == edge.to and set[edge.from] then
      return true
    end
  end
  return false
end

-- A component is cyclic when it has more than one node or contains a
-- self-loop.
function layout.cyclic_component(component, edges)
  return #component > 1 or _has_self_loop(component, edges)
end

-- Eades greedy linear order: repeatedly place sources left, sinks right, and
-- when neither exists place the node with the largest out-degree minus
-- in-degree left (ties broken by the lexicographically largest name).
local function _set_size(set)
  local count = 0
  for _ in pairs(set) do
    count = count + 1
  end
  return count
end

function layout.greedy_order(node_ids, edges)
  local remaining = _to_set(node_ids)
  local active_edges = {}
  for _, edge in ipairs(edges or {}) do
    active_edges[#active_edges + 1] = edge
  end
  local left = {}
  local right = {}

  local function remaining_ids()
    return _sorted_keys(remaining)
  end

  while next(remaining) ~= nil do
    local ids = remaining_ids()
    local incoming = _incoming_map(ids, active_edges)
    local outgoing = _outgoing_map(ids, active_edges)
    local node_id
    local side
    local sources = {}
    for _, id in ipairs(ids) do
      if next(incoming[id]) == nil then
        sources[#sources + 1] = id
      end
    end
    if #sources > 0 then
      node_id = sources[1]
      side = "left"
    else
      local sinks = {}
      for _, id in ipairs(ids) do
        if next(outgoing[id]) == nil then
          sinks[#sinks + 1] = id
        end
      end
      if #sinks > 0 then
        node_id = sinks[1]
        side = "right"
      else
        local keyed = {}
        for _, id in ipairs(ids) do
          keyed[#keyed + 1] = { id = id, diff = _set_size(outgoing[id]) - _set_size(incoming[id]) }
        end
        table.sort(keyed, function(a, b)
          if a.diff ~= b.diff then
            return a.diff < b.diff
          end
          return a.id < b.id
        end)
        node_id = keyed[#keyed].id
        side = "left"
      end
    end
    if side == "left" then
      left[#left + 1] = node_id
    else
      right[#right + 1] = node_id
    end
    remaining[node_id] = nil
    local kept = {}
    for _, edge in ipairs(active_edges) do
      if edge.from ~= node_id and edge.to ~= node_id then
        kept[#kept + 1] = edge
      end
    end
    active_edges = kept
  end

  local order = {}
  for _, id in ipairs(left) do
    order[#order + 1] = id
  end
  for index = #right, 1, -1 do
    order[#order + 1] = right[index]
  end
  return order
end

-- choose-k subsets of values in the same recursive order as the original
-- (layers.clj choose-k): subsets containing the head first, then the rest.
local function _choose_k(values, k)
  if k == 0 then
    return { {} }
  end
  if k > #values then
    return {}
  end
  local head = values[1]
  local tail = {}
  for index = 2, #values do
    tail[#tail + 1] = values[index]
  end
  local out = {}
  for _, rest in ipairs(_choose_k(tail, k - 1)) do
    local subset = { head }
    for _, value in ipairs(rest) do
      subset[#subset + 1] = value
    end
    out[#out + 1] = subset
  end
  for _, subset in ipairs(_choose_k(tail, k)) do
    out[#out + 1] = subset
  end
  return out
end

-- Kahn DAG check with a lexicographic queue, matching the original
-- topological-order (layers.clj): every node is ordered iff no cycle remains.
local function _is_dag(node_ids, edges)
  local outgoing = _outgoing_map(node_ids, edges)
  local incoming = _incoming_map(node_ids, edges)
  local remaining_in = {}
  local queue = {}
  for _, node_id in ipairs(node_ids) do
    remaining_in[node_id] = _set_size(incoming[node_id] or {})
    if remaining_in[node_id] == 0 then
      queue[#queue + 1] = node_id
    end
  end
  _sorted(queue)
  local ordered = 0
  while #queue > 0 do
    local node_id = table.remove(queue, 1)
    ordered = ordered + 1
    for _, dep in ipairs(_sorted_keys(outgoing[node_id] or {})) do
      remaining_in[dep] = (remaining_in[dep] or 0) - 1
      if remaining_in[dep] == 0 then
        queue[#queue + 1] = dep
        _sorted(queue)
      end
    end
  end
  return ordered == #node_ids
end

-- Exact minimum feedback edge set (monopoly #228, layers.clj:128-138):
-- enumerate the k-subsets of edges for k = 0, 1, 2, ... in input order; the
-- first subset whose removal leaves a DAG is a minimum set and is removed.
-- Determinism comes from the lexicographic edge order upstream
-- (normalize_edges). Returns nil only when no subset works, which cannot
-- happen for a finite edge list (removing everything always leaves a DAG).
function layout.exact_feedback_edges(node_ids, edges)
  local indices = {}
  for index = 1, #edges do
    indices[index] = index
  end
  for k = 0, #edges do
    for _, subset in ipairs(_choose_k(indices, k)) do
      local removed = {}
      for _, index in ipairs(subset) do
        removed[index] = true
      end
      local remaining = {}
      for index, edge in ipairs(edges) do
        if not removed[index] then
          remaining[#remaining + 1] = edge
        end
      end
      if _is_dag(node_ids, remaining) then
        local feedback = {}
        for _, index in ipairs(subset) do
          feedback[#feedback + 1] = edges[index]
        end
        return feedback
      end
    end
  end
  return nil
end

-- Feedback edges of one cyclic component: small components (at most
-- EXACT_FEEDBACK_MAX_NODES nodes and EXACT_FEEDBACK_MAX_EDGES internal
-- edges) get the exact minimum set by enumeration; larger components keep
-- the Eades greedy linear order, whose backward edges (from ordered at or
-- after to) are removed. A nil from the exact path (impossible for a
-- finite edge list) falls back to greedy too: removing nothing would let
-- a cyclic component reach layering with its cycle intact, which fails
-- far more obscurely than a suboptimal edge choice.
local function _component_feedback_edges(component, edges)
  local set = _to_set(component)
  local internal = {}
  for _, edge in ipairs(edges or {}) do
    if set[edge.from] and set[edge.to] then
      internal[#internal + 1] = edge
    end
  end
  if not layout.cyclic_component(component, internal) then
    return {}
  end
  if #component <= layout.EXACT_FEEDBACK_MAX_NODES and #internal <= layout.EXACT_FEEDBACK_MAX_EDGES then
    local exact = layout.exact_feedback_edges(component, internal)
    if exact ~= nil then
      return exact
    end
  end
  local order = layout.greedy_order(component, internal)
  local position = {}
  for index, id in ipairs(order) do
    position[id] = index
  end
  local feedback = {}
  for _, edge in ipairs(internal) do
    if (position[edge.from] or 0) >= (position[edge.to] or 0) then
      feedback[#feedback + 1] = edge
    end
  end
  return feedback
end

-- Set (edge_key -> true) of every feedback edge across all components.
function layout.feedback_edge_set(node_ids, edges)
  local feedback = {}
  for _, component in ipairs(layout.strongly_connected_components(node_ids, edges)) do
    for _, edge in ipairs(_component_feedback_edges(component, edges)) do
      feedback[layout.edge_key(edge.from, edge.to)] = true
    end
  end
  return feedback
end

-- BFS shortest path from start to goal over edges, enqueueing neighbors in
-- lexicographic order to match the original (layers.clj shortest-path).
-- Returns the node id list from start to goal inclusive, or nil.
function layout.shortest_path(edges, start, goal)
  local node_ids = {}
  local seen_node = {}
  for _, edge in ipairs(edges or {}) do
    if not seen_node[edge.from] then
      seen_node[edge.from] = true
      node_ids[#node_ids + 1] = edge.from
    end
    if not seen_node[edge.to] then
      seen_node[edge.to] = true
      node_ids[#node_ids + 1] = edge.to
    end
  end
  local outgoing = _outgoing_map(node_ids, edges)
  local queue = { { start } }
  local seen = { [start] = true }
  while #queue > 0 do
    local path = table.remove(queue, 1)
    local node_id = path[#path]
    if node_id == goal then
      return path
    end
    for _, neighbor in ipairs(_sorted_keys(outgoing[node_id] or {})) do
      if not seen[neighbor] then
        seen[neighbor] = true
        local next_path = {}
        for _, id in ipairs(path) do
          next_path[#next_path + 1] = id
        end
        next_path[#next_path + 1] = neighbor
        queue[#queue + 1] = next_path
      end
    end
  end
  return nil
end

-- Closed cycle path for one feedback edge: the BFS shortest path to->from on
-- the acyclic remainder, prefixed with from (a self-loop closes on itself).
function layout.cycle_path_for_feedback_edge(acyclic_edges, edge)
  if edge.from == edge.to then
    return { edge.from, edge.from }
  end
  local path = layout.shortest_path(acyclic_edges, edge.to, edge.from)
  if path == nil then
    return nil
  end
  local cycle = { edge.from }
  for _, id in ipairs(path) do
    cycle[#cycle + 1] = id
  end
  return cycle
end

-- One closed cycle path per feedback edge, iterated in (from, to) order and
-- deduplicated by the joined path (layers.clj cycle-paths).
function layout.cycle_paths(feedback, edges, acyclic_edges)
  local feedback_edges = {}
  for _, edge in ipairs(edges or {}) do
    if feedback[layout.edge_key(edge.from, edge.to)] then
      feedback_edges[#feedback_edges + 1] = edge
    end
  end
  table.sort(feedback_edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    return a.to < b.to
  end)
  local seen = {}
  local cycles = {}
  for _, edge in ipairs(feedback_edges) do
    local path = layout.cycle_path_for_feedback_edge(acyclic_edges, edge)
    if path ~= nil then
      local key = table.concat(path, "\0")
      if not seen[key] then
        seen[key] = true
        cycles[#cycles + 1] = path
      end
    end
  end
  return cycles
end

-- Longest-path levels on a DAG: nodes with in-degree 0 (nothing depends on
-- them) get level 1 at the top; every dependency sits at least one level
-- below its deepest dependent, and the incoming side pushes nodes up too
-- (both rules ported verbatim from layers.clj topological-levels).
function layout.topological_levels(node_ids, edges)
  local outgoing = _outgoing_map(node_ids, edges)
  local incoming = _incoming_map(node_ids, edges)
  local indegree = {}
  for _, node_id in ipairs(node_ids) do
    indegree[node_id] = 0
  end
  for _, edge in ipairs(edges or {}) do
    if indegree[edge.to] ~= nil then
      indegree[edge.to] = indegree[edge.to] + 1
    end
  end
  local levels = {}
  local queue = {}
  for _, node_id in ipairs(node_ids) do
    levels[node_id] = 1
    if indegree[node_id] == 0 then
      queue[#queue + 1] = node_id
    end
  end
  _sorted(queue)
  while #queue > 0 do
    local node_id = table.remove(queue, 1)
    local node_level = levels[node_id] or 1
    for _, dep in ipairs(_sorted_keys(outgoing[node_id] or {})) do
      levels[dep] = math.max(levels[dep] or 1, node_level + 1)
      indegree[dep] = (indegree[dep] or 0) - 1
      if indegree[dep] == 0 then
        queue[#queue + 1] = dep
        _sorted(queue)
      end
    end
    local roots = incoming[node_id] or {}
    if next(roots) ~= nil then
      local max_root = 1
      for root in pairs(roots) do
        max_root = math.max(max_root, levels[root] or 1)
      end
      levels[node_id] = math.max(levels[node_id] or 1, max_root + 1)
    end
  end
  return levels
end

-- Full layering result: normalized edges, feedback set, the remaining DAG,
-- closed cycle paths, per-node levels, and layers (row = level - 1, modules
-- sorted per level).
function layout.assign_layers(node_ids, raw_edges)
  local edges = layout.normalize_edges(node_ids, raw_edges)
  local feedback = layout.feedback_edge_set(node_ids, edges)
  local acyclic_edges = {}
  for _, edge in ipairs(edges) do
    if not feedback[layout.edge_key(edge.from, edge.to)] then
      acyclic_edges[#acyclic_edges + 1] = edge
    end
  end
  local cycles = layout.cycle_paths(feedback, edges, acyclic_edges)
  local levels = layout.topological_levels(node_ids, acyclic_edges)
  local by_level = {}
  for _, node_id in ipairs(node_ids) do
    local level = levels[node_id] or 1
    by_level[level] = by_level[level] or {}
    by_level[level][#by_level[level] + 1] = node_id
  end
  local level_numbers = {}
  for level in pairs(by_level) do
    level_numbers[#level_numbers + 1] = level
  end
  table.sort(level_numbers)
  local layers = {}
  for _, level in ipairs(level_numbers) do
    layers[#layers + 1] = {
      level = level,
      row = level - 1,
      modules = _sorted(by_level[level]),
    }
  end
  return {
    edges = edges,
    feedback = feedback,
    acyclic_edges = acyclic_edges,
    cycles = cycles,
    levels = levels,
    layers = layers,
  }
end

-- Set (node_id -> true) of every node sitting in a cyclic component.
function layout.cyclic_node_set(node_ids, edges)
  local cyclic = {}
  for _, component in ipairs(layout.strongly_connected_components(node_ids, edges)) do
    if layout.cyclic_component(component, edges) then
      for _, node_id in ipairs(component) do
        cyclic[node_id] = true
      end
    end
  end
  return cyclic
end

function layout.track_width(canvas_width)
  return (canvas_width - 2 * layout.RACETRACK_MARGIN - (layout.RACETRACK_COUNT - 1) * layout.RACETRACK_GAP)
    / layout.RACETRACK_COUNT
end

-- Horizontal slot of one peer inside its level: the group is centered on the
-- canvas with 1.5x rect-width spacing, compressed to exactly fill the usable
-- width when the preferred spacing does not fit. peer_index is 0-based.
function layout.centered_peer_x(canvas_width, rect_width, peer_index, peer_count)
  local usable_width = math.max(rect_width, canvas_width - 2 * layout.RACETRACK_MARGIN)
  local preferred_spacing = rect_width * 1.5
  local max_spacing = 0
  if peer_count > 1 then
    max_spacing = math.max(0, (usable_width - rect_width) / (peer_count - 1))
  end
  local spacing = 0
  if peer_count > 1 then
    spacing = math.min(preferred_spacing, max_spacing)
  end
  local group_width = rect_width + (math.max(1, peer_count) - 1) * spacing
  local group_start = layout.RACETRACK_MARGIN + (usable_width - group_width) / 2
  return group_start + peer_index * spacing
end

-- Per-view layout: for every node id, its level/row, peer position, and rect
-- on the fixed 1200px canvas, plus the feedback edge set, the closed cycle
-- paths, and the cyclic node set of the view.
function layout.compute_view(node_ids, raw_edges)
  local assigned = layout.assign_layers(node_ids, raw_edges)
  local width = layout.CANVAS_WIDTH
  local rect_width = layout.RECT_SCALE * layout.track_width(width)
  local rect_height = layout.RECT_SCALE * layout.LAYER_HEIGHT
  local nodes = {}
  for _, layer in ipairs(assigned.layers) do
    local peer_count = #layer.modules
    for index, module_id in ipairs(layer.modules) do
      local peer_index = index - 1
      nodes[module_id] = {
        level = layer.level,
        row = layer.row,
        peer_index = peer_index,
        peer_count = peer_count,
        rect = {
          x = layout.centered_peer_x(width, rect_width, peer_index, peer_count),
          y = layout.SCENE_TOP_PADDING + layer.row * rect_height * 1.5,
          width = rect_width,
          height = rect_height,
        },
      }
    end
  end
  return {
    nodes = nodes,
    layers = assigned.layers,
    edges = assigned.edges,
    feedback = assigned.feedback,
    acyclic_edges = assigned.acyclic_edges,
    cycles = assigned.cycles,
    cyclic_nodes = layout.cyclic_node_set(node_ids, assigned.edges),
  }
end

return layout
