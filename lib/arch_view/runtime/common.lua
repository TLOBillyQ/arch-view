local script_common = require("arch_view.runtime.host")

local common = {}

local _delegated_function_names = {
  "sorted_pairs",
  "bilingual",
  "is_windows",
  "is_macos",
  "normalize_path",
  "simplify_path",
  "is_absolute_path",
  "resolve_path",
  "current_dir",
  "join_path",
  "parent_dir",
  "split",
  "join",
  "system_tmp_dir",
  "ensure_dir",
  "ensure_parent_dir",
  "read_file",
  "write_file",
  "append_file",
  "collect_files",
  "collect_lua_files",
  "path_exists",
  "path_mtime",
  "remove_path",
  "copy_tree",
  "run_command",
  "make_temp_path",
  "command_exists",
  "open_path",
  "build_open_command",
  "shell_quote",
  "sorted_keys",
  "is_numeric",
  "to_integer",
}

for _, _name in ipairs(_delegated_function_names) do
  common[_name] = script_common[_name]
end

function common.copy_array(values)
  local copied = {}
  for index, value in ipairs(values or {}) do
    copied[index] = value
  end
  return copied
end

function common.starts_with_segments(parts, prefix)
  if #prefix > #parts then
    return false
  end
  for index = 1, #prefix do
    if parts[index] ~= prefix[index] then
      return false
    end
  end
  return true
end

function common.list_to_set(values)
  local set = {}
  for _, value in ipairs(values or {}) do
    set[value] = true
  end
  return set
end

function common.edge_key(from_id, to_id)
  return tostring(from_id) .. "\n" .. tostring(to_id)
end

function common.sorted_edges(edge_map)
  local edges = {}
  for _, edge in common.sorted_pairs(edge_map or {}) do
    edges[#edges + 1] = edge
  end
  table.sort(edges, function(left, right)
    if left.from == right.from then
      return tostring(left.to) < tostring(right.to)
    end
    return tostring(left.from) < tostring(right.from)
  end)
  return edges
end

function common.view_key(path_segments)
  if path_segments == nil or #path_segments == 0 then
    return "root"
  end
  return table.concat(path_segments, ".")
end

function common.strip_src_prefix(module_id)
  local text = tostring(module_id or "")
  return (text:gsub("^src%.", ""))
end

function common.source_filename(path)
  local normalized = common.normalize_path(path)
  return normalized:match("([^/]+)$")
end

function common.source_filename_base(path)
  local filename = common.source_filename(path)
  if filename == nil then
    return nil
  end
  return (filename:gsub("%.[^.]+$", ""))
end

return common
