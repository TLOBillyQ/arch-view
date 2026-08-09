local cli_runner = require("arch_view.internal.cli_runner")
local service = require("arch_view.internal.service")

local arch_view = {}

function arch_view.load_config(path)
  return service.load_config(path)
end

function arch_view.analyze(opts)
  return service.analyze(opts)
end

function arch_view.check(opts)
  return service.check(opts)
end

function arch_view.write_scan(opts)
  return service.write_scan(opts)
end

function arch_view.export_viewer(opts)
  return service.export_viewer(opts)
end

function arch_view.run_cli(args, opts)
  return cli_runner.run(args, opts)
end

return arch_view
