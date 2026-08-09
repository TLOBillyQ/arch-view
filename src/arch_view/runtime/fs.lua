local script_common = require("arch_view.runtime.host")

local fs = {}

local exported = {
  "normalize_path",
  "current_dir",
  "join_path",
  "parent_dir",
  "resolve_path",
  "ensure_dir",
  "ensure_parent_dir",
  "read_file",
  "write_file",
  "path_exists",
  "path_mtime",
  "remove_path",
  "open_path",
  "copy_tree",
  "collect_files",
  "run_command",
  "make_temp_path",
}

for _, name in ipairs(exported) do
  fs[name] = script_common[name]
end

return fs
