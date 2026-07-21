local fs = require("arch_view.runtime.fs")

local analyzer = {}

local function _sort(values)
  table.sort(values, function(a, b) return tostring(a) < tostring(b) end)
  return values
end

local function _sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  return _sort(keys)
end

local function _copy_array(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    out[#out + 1] = value
  end
  return out
end

local function _to_repo_relative(project_root, path)
  local root = tostring(project_root or ""):gsub("\\", "/"):gsub("/+$", "") .. "/"
  local normalized = tostring(path or ""):gsub("\\", "/")
  if normalized:sub(1, #root) == root then
    return normalized:sub(#root + 1)
  end
  return normalized
end

local function _module_id_from_path(project_root, path)
  local relative = _to_repo_relative(project_root, path):gsub("%.lua$", "")
  local module_id = relative:gsub("/", ".")
  module_id = module_id:gsub("%.init$", "")
  return module_id
end

local function _segments(module_id)
  local out = {}
  for segment in tostring(module_id or ""):gmatch("[^%.]+") do
    out[#out + 1] = segment
  end
  return out
end

local function _namespace_segments(segments)
  local out = {}
  for index = 2, #segments do
    out[#out + 1] = segments[index]
  end
  return out
end

local function _matches_any(module_id, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if tostring(module_id or ""):match(pattern) ~= nil then
      return true
    end
  end
  return false
end

local function _rule_match(module_id, rules)
  for _, rule in ipairs(rules or {}) do
    if _matches_any(module_id, rule.match) then
      return rule
    end
  end
  return nil
end

local function _strip_comments(source)
  local stripped = tostring(source or "")
  stripped = stripped:gsub("%-%-%[%[.-%]%]", "")
  stripped = stripped:gsub("%-%-[^\r\n]*", "")
  return stripped
end

local function _scan_requires(source)
  local stripped = _strip_comments(source)
  local seen = {}
  local requires = {}
  local function add(module_id)
    if module_id ~= nil and module_id ~= "" and not seen[module_id] then
      seen[module_id] = true
      requires[#requires + 1] = module_id
    end
  end
  for module_id in stripped:gmatch("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
    add(module_id)
  end
  for module_id in stripped:gmatch("require%s+['\"]([^'\"]+)['\"]") do
    add(module_id)
  end
  return _sort(requires)
end

local function _module_source_file_name(path)
  return tostring(path or ""):gsub("\\", "/"):match("([^/]+)%.lua$") or tostring(path or "")
end

local function _edge_key(from_id, to_id)
  return tostring(from_id) .. "\0" .. tostring(to_id)
end

local function _edge_type(to_module)
  return to_module.abstract and "abstract" or "direct"
end

local function _edge_text(from_id, to_id)
  return tostring(from_id):gsub("^src%.", "") .. " -> " .. tostring(to_id):gsub("^src%.", "")
end

local function _build_modules(project_root, config)
  local modules = {}
  local files = {}
  for _, source_root in ipairs(config.source_roots or {}) do
    local root_path = fs.resolve_path(project_root, source_root)
    local collected = fs.collect_files(root_path, ".lua") or {}
    for _, path in ipairs(collected) do
      files[#files + 1] = path
    end
  end
  table.sort(files)

  for _, path in ipairs(files) do
    local source = fs.read_file(path) or ""
    local module_id = _module_id_from_path(project_root, path)
    local segments = _segments(module_id)
    local component_rule = _rule_match(module_id, config.component_rules)
    local abstract_rule = _rule_match(module_id, config.abstract_rules)
    modules[module_id] = {
      module_id = module_id,
      module_segments = segments,
      namespace_segments = _namespace_segments(segments),
      source_path = path,
      source_text = source,
      source_file_name = _module_source_file_name(path),
      component = component_rule and component_rule.component or nil,
      abstract = abstract_rule ~= nil,
      internal_requires = {},
      external_requires = {},
      _raw_requires = _scan_requires(source),
    }
  end

  for _, module_id in ipairs(_sorted_keys(modules)) do
    local info = modules[module_id]
    for _, required in ipairs(info._raw_requires or {}) do
      if modules[required] ~= nil then
        info.internal_requires[#info.internal_requires + 1] = required
      else
        info.external_requires[#info.external_requires + 1] = required
      end
    end
    info._raw_requires = nil
  end

  return modules
end

local function _build_graph(modules)
  local nodes = _sorted_keys(modules)
  local edges = {}
  local seen = {}
  for _, from_id in ipairs(nodes) do
    for _, to_id in ipairs(modules[from_id].internal_requires or {}) do
      local key = _edge_key(from_id, to_id)
      if not seen[key] then
        seen[key] = true
        edges[#edges + 1] = { from = from_id, to = to_id }
      end
    end
  end
  table.sort(edges, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.to < b.to
  end)
  return { nodes = nodes, edges = edges }
end

local function _classified_edges(graph, modules)
  local out = {}
  for _, edge in ipairs(graph.edges or {}) do
    local from_module = modules[edge.from] or {}
    local to_module = modules[edge.to] or {}
    out[#out + 1] = {
      from = edge.from,
      to = edge.to,
      from_component = from_module.component,
      to_component = to_module.component,
      type = _edge_type(to_module),
    }
  end
  return out
end

local function _build_check(graph, modules, config)
  local violations = {}
  for _, module_id in ipairs(_sorted_keys(modules)) do
    if modules[module_id].component == nil then
      violations[#violations + 1] = {
        kind = "unclassified_module",
        module_id = module_id,
      }
    end
  end
  for _, edge in ipairs(graph.edges or {}) do
    for _, rule in ipairs(config.forbidden_dependency_rules or {}) do
      if _matches_any(edge.from, rule.from) and _matches_any(edge.to, rule.to) then
        violations[#violations + 1] = {
          kind = "forbidden_dependency",
          rule = rule.name,
          description = rule.description,
          from = edge.from,
          to = edge.to,
        }
      end
    end
  end
  return {
    ok = #violations == 0,
    violations = violations,
    cycles = {},
    projection_cycles = {},
  }
end

local function _child_for(info, prefix)
  local ns = info.namespace_segments or {}
  if #prefix > #ns then
    return nil
  end
  for index, value in ipairs(prefix) do
    if ns[index] ~= value then
      return nil
    end
  end
  return ns[#prefix + 1]
end

local function _full_name(prefix, child)
  local parts = _copy_array(prefix)
  if child ~= nil and child ~= "" then
    parts[#parts + 1] = child
  end
  return table.concat(parts, ".")
end

local function _module_id_for_namespace(modules, full_name, module_ids)
  local exact = full_name ~= "" and ("src." .. full_name) or nil
  if exact and modules[exact] then
    return exact
  end
  return module_ids[1]
end

local function _dependency_entry(direction, edge, modules)
  local to_module = modules[edge.to] or {}
  return {
    direction = direction,
    from = edge.from,
    to = edge.to,
    type = _edge_type(to_module),
    text = _edge_text(edge.from, edge.to) .. " (1)",
  }
end

-- Precomputed dependency entries plus per-module edge indices, so each view
-- node collects its dependencies without rescanning the whole graph. Every
-- per-module index list is ascending; merging several lists takes one numeric
-- sort to reproduce the original graph.edges traversal order exactly.
local function _build_dependency_index(graph, modules)
  local incoming_entries = {}
  local outgoing_entries = {}
  local incoming_by_module = {}
  local outgoing_by_module = {}
  for index, edge in ipairs(graph.edges or {}) do
    incoming_entries[index] = _dependency_entry("incoming", edge, modules)
    outgoing_entries[index] = _dependency_entry("outgoing", edge, modules)
    local outgoing = outgoing_by_module[edge.from]
    if outgoing == nil then
      outgoing = {}
      outgoing_by_module[edge.from] = outgoing
    end
    outgoing[#outgoing + 1] = index
    local incoming = incoming_by_module[edge.to]
    if incoming == nil then
      incoming = {}
      incoming_by_module[edge.to] = incoming
    end
    incoming[#incoming + 1] = index
  end
  return {
    incoming_entries = incoming_entries,
    outgoing_entries = outgoing_entries,
    incoming_by_module = incoming_by_module,
    outgoing_by_module = outgoing_by_module,
  }
end

local function _collect_dependencies(module_ids, by_module, entries)
  local indices = {}
  for _, module_id in ipairs(module_ids) do
    for _, index in ipairs(by_module[module_id] or {}) do
      indices[#indices + 1] = index
    end
  end
  if #module_ids > 1 then
    table.sort(indices)
  end
  local out = {}
  for _, index in ipairs(indices) do
    out[#out + 1] = entries[index]
  end
  return out
end

local function _build_view_nodes(prefix, modules, dependencies)
  local buckets = {}
  for _, module_id in ipairs(_sorted_keys(modules)) do
    local info = modules[module_id]
    local child = _child_for(info, prefix)
    if child ~= nil then
      buckets[child] = buckets[child] or {}
      buckets[child][#buckets[child] + 1] = module_id
    end
  end

  local nodes = {}
  for _, child in ipairs(_sorted_keys(buckets)) do
    local module_ids = buckets[child]
    table.sort(module_ids)
    local full_name = _full_name(prefix, child)
    local module_id = _module_id_for_namespace(modules, full_name, module_ids)
    local module_info = modules[module_id] or modules[module_ids[1]] or {}
    local drillable = false
    for _, represented_id in ipairs(module_ids) do
      local ns = modules[represented_id].namespace_segments or {}
      if #ns > #prefix + 1 then
        drillable = true
        break
      end
    end
    local incoming = _collect_dependencies(module_ids, dependencies.incoming_by_module, dependencies.incoming_entries)
    local outgoing = _collect_dependencies(module_ids, dependencies.outgoing_by_module, dependencies.outgoing_entries)
    nodes[#nodes + 1] = {
      id = child,
      label = child,
      display_label = child,
      child_name = child,
      full_name = full_name,
      module_id = module_id,
      module_ids = module_ids,
      source_path = module_info.source_path,
      source_text = module_info.source_text,
      source_file_name = module_info.source_file_name,
      component = module_info.component,
      abstract = module_info.abstract == true,
      internal_requires = _copy_array(module_info.internal_requires),
      leaf = not drillable,
      drillable = drillable,
      cycle = false,
      has_cycle_subtree = false,
      layer = #prefix,
      rect = { x = 80 + (#nodes % 4) * 220, y = 80 + math.floor(#nodes / 4) * 120, width = 188, height = 60 },
      incoming_dependencies = incoming,
      outgoing_dependencies = outgoing,
    }
  end
  return nodes, buckets
end

local function _build_view_edges(prefix, buckets, graph, modules)
  local bucket_by_module = {}
  for child, module_ids in pairs(buckets or {}) do
    for _, module_id in ipairs(module_ids) do
      bucket_by_module[module_id] = child
    end
  end

  local aggregated = {}
  for _, edge in ipairs(graph.edges or {}) do
    local from_child = bucket_by_module[edge.from]
    local to_child = bucket_by_module[edge.to]
    if from_child ~= nil and to_child ~= nil and from_child ~= to_child then
      local key = _edge_key(from_child, to_child)
      local entry = aggregated[key]
      if entry == nil then
        entry = {
          id = from_child .. "->" .. to_child,
          from = from_child,
          to = to_child,
          type = "direct",
          count = 0,
          module_edges = {},
          tooltip = {},
          tooltip_lines = {},
          arrowhead = "standard",
          route_points = {},
        }
        aggregated[key] = entry
      end
      local to_module = modules[edge.to] or {}
      local edge_type = _edge_type(to_module)
      if edge_type == "abstract" then
        entry.type = "abstract"
      end
      entry.count = entry.count + 1
      local text = _edge_text(edge.from, edge.to)
      entry.module_edges[#entry.module_edges + 1] = {
        from = edge.from,
        to = edge.to,
        type = edge_type,
        text = text,
      }
      entry.tooltip[#entry.tooltip + 1] = { type = edge_type, text = text .. " (1)" }
      entry.tooltip_lines[#entry.tooltip_lines + 1] = text .. " (1)"
    end
  end

  local edges = {}
  for _, key in ipairs(_sorted_keys(aggregated)) do
    edges[#edges + 1] = aggregated[key]
  end
  return edges
end

local function _collect_view_prefixes(modules)
  local prefixes = { ["root"] = {} }
  for _, module_id in ipairs(_sorted_keys(modules)) do
    local ns = modules[module_id].namespace_segments or {}
    for length = 1, #ns - 1 do
      local parts = {}
      for index = 1, length do
        parts[#parts + 1] = ns[index]
      end
      prefixes[table.concat(parts, ".")] = parts
    end
  end
  return prefixes
end

local function _build_views(modules, graph, dependencies)
  local views = {}
  local prefixes = _collect_view_prefixes(modules)
  for _, view_key in ipairs(_sorted_keys(prefixes)) do
    local prefix = prefixes[view_key]
    local nodes, buckets = _build_view_nodes(prefix, modules, dependencies)
    if #nodes > 0 then
      local display_edges = _build_view_edges(prefix, buckets, graph, modules)
      views[view_key] = {
        key = view_key,
        nodes = nodes,
        display_edges = display_edges,
        edges = display_edges,
        breadcrumb = {
          { key = "root", label = "root" },
        },
      }
      if view_key ~= "root" then
        views[view_key].breadcrumb[#views[view_key].breadcrumb + 1] = {
          key = view_key,
          label = view_key:match("([^%.]+)$") or view_key,
        }
      end
    end
  end
  return views
end

function analyzer.analyze(resolved)
  local current_dir = fs.current_dir()
  local project_root = fs.resolve_path(current_dir, resolved.project_root or current_dir)
  local config = resolved.config or {}
  local modules = _build_modules(project_root, config)
  local graph = _build_graph(modules)
  local dependencies = _build_dependency_index(graph, modules)
  local check = _build_check(graph, modules, config)
  local views = _build_views(modules, graph, dependencies)
  return {
    schema_version = 1,
    project_root = project_root,
    config_path = resolved.config_path,
    modules = modules,
    graph = graph,
    classified_edges = _classified_edges(graph, modules),
    layout = {},
    views = views,
    check = check,
    projection_cycles = {},
  }
end

return analyzer
