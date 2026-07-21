local fs = require("arch_view.runtime.fs")

local module_path = {}

local function _source_path(stack_level)
  local info = debug.getinfo(stack_level, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return fs.normalize_path(source)
end

function module_path.source_path(stack_level)
  return _source_path((stack_level or 1) + 1)
end

function module_path.source_dir(stack_level)
  return fs.parent_dir(_source_path((stack_level or 1) + 1))
end

function module_path.package_root(stack_level)
  local dir = fs.parent_dir(_source_path((stack_level or 1) + 1))
  return fs.parent_dir(fs.parent_dir(dir))
end

return module_path
