local cli_runner = require("arch_view.internal.cli_runner")
local common = require("arch_view.runtime.common")

local cli = {}

function cli.run(args, env)
  env = env or {}

  local opts = {
    cwd = env.cwd,
    command_name = env.command_name,
    open_path = env.open_path,
    default_project_root = env.default_project_root,
    default_config_path = env.default_config_path,
  }

  -- script_dir 下存在 viewer/ 时(源码 / vendor 形态)才覆盖 asset_root;
  -- rock 形态下 viewer 由 builtin 装进 lua_dir,走 default_asset_root() 定位。
  if env.script_dir ~= nil then
    local script_asset_root = common.join_path(env.script_dir, "viewer")
    if common.path_exists(script_asset_root) == true then
      opts.asset_root = script_asset_root
    end
  end

  return cli_runner.run(common.copy_array(args), opts)
end

return cli
