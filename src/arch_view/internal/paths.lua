local fs = require("arch_view.runtime.fs")
local module_path = require("arch_view.runtime.module_path")

local paths = {}

function paths.package_root()
  local root = module_path.package_root(2)
  if tostring(root):match("/src$") then
    return fs.parent_dir(root)
  end
  return root
end

-- Viewer assets resolve in two forms (matching the rockspec packaging):
-- - source / vendor tree: repo root has src/ and lua/viewer/ (lua/ is the
--   builtin install mirror), so package_root resolves to the repo root;
-- - installed rock: the builtin driver copies lua/ into the lua dir, so the
--   viewer lands at <lua_dir>/viewer and package_root is the lua dir itself.
function paths.default_asset_root()
  local root = paths.package_root()
  local direct = fs.join_path(root, "viewer")
  if fs.path_exists(direct) == true then
    return direct
  end
  return fs.join_path(fs.join_path(root, "lua"), "viewer")
end

function paths.default_viewer_out_dir(project_root)
  return fs.join_path(project_root, ".arch_view/viewer")
end

function paths.resolve_project_path(project_root, path)
  if path == nil then
    return nil
  end
  return fs.resolve_path(project_root, path)
end

return paths
