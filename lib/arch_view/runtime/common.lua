local script_common = require("arch_view.runtime.host")

local common = {}

local _delegated_function_names = {
  "sorted_pairs",
  "bilingual",
  "is_windows",
  "is_macos",
  "normalize_path",
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

function common.simplify_path(path)
  local normalized = common.normalize_path(path)
  local prefix = ""
  local remainder = normalized
  if normalized:match("^%a:/") then
    prefix = normalized:sub(1, 2)
    remainder = normalized:sub(4)
  elseif normalized:match("^/[A-Za-z]/") then
    prefix = normalized:sub(2, 3)
    remainder = normalized:sub(5)
  elseif normalized:sub(1, 1) == "/" then
    prefix = "/"
    remainder = normalized:sub(2)
  end
  local parts = {}
  for _, segment in ipairs(common.split(remainder, "/")) do
    if segment ~= "" and segment ~= "." then
      if segment == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then
          parts[#parts] = nil
        elseif prefix == "" then
          parts[#parts + 1] = segment
        end
      else
        parts[#parts + 1] = segment
      end
    end
  end
  local simplified = table.concat(parts, "/")
  if prefix == "" then
    return simplified
  end
  if simplified == "" then
    return prefix == "/" and "/" or (prefix .. "/")
  end
  if prefix == "/" then
    return "/" .. simplified
  end
  return prefix .. "/" .. simplified
end

function common.is_absolute_path(path)
  local normalized = common.normalize_path(path)
  if normalized:match("^%a:/") then
    return true
  end
  if normalized:match("^/[A-Za-z]/") then
    return true
  end
  if normalized:match("^//") then
    return true
  end
  return normalized:sub(1, 1) == "/"
end

function common.resolve_path(base, path)
  local normalized_path = common.normalize_path(path)
  if normalized_path == "" then
    return common.simplify_path(base)
  end
  if common.is_windows() and normalized_path:sub(1, 1) == "/" then
    if normalized_path:match("^/[A-Za-z]/") then
      return common.simplify_path(normalized_path:sub(2, 2) .. ":" .. normalized_path:sub(3))
    end
    local tmpdir = common.system_tmp_dir()
    if normalized_path == "/tmp" or normalized_path:match("^/tmp/") then
      local suffix = normalized_path:sub(5)
      return common.simplify_path(common.join_path(tmpdir, suffix))
    end
  end
  if common.is_absolute_path(normalized_path) then
    return common.simplify_path(normalized_path)
  end
  return common.simplify_path(common.join_path(base or "", normalized_path))
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
