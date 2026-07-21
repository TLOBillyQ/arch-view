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

  if env.script_dir ~= nil then
    opts.asset_root = common.join_path(env.script_dir, "viewer")
  end

  return cli_runner.run(common.copy_array(args), opts)
end

return cli
