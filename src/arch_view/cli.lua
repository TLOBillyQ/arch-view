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

  -- Override asset_root from script_dir only when a viewer/ dir exists under
  -- it (source / vendor form); installed rocks carry viewer inside the lua
  -- dir, resolved by paths.default_asset_root().
  if env.script_dir ~= nil then
    local script_asset_root = common.join_path(env.script_dir, "viewer")
    if common.path_exists(script_asset_root) == true then
      opts.asset_root = script_asset_root
    end
  end

  return cli_runner.run(common.copy_array(args), opts)
end

return cli
