local fs = require("arch_view.runtime.fs")
local module_path = require("arch_view.runtime.module_path")

local paths = {}

function paths.package_root()
  local root = module_path.package_root(2)
  if tostring(root):match("/lib$") then
    return fs.parent_dir(root)
  end
  return root
end

-- viewer 资产的两形态定位(与 rockspec 打包对应):
-- - 源码 / vendor 形态:repo 根有 lib/ 与 lua/viewer/(lua/ 是 builtin 的安装镜像),package_root 解析到 repo 根;
-- - rock 形态:builtin 把 lua/ 拷进 lua_dir,viewer 就在 <lua_dir>/viewer,package_root 即 lua_dir。
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
