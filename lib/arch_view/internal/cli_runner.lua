local common = require("arch_view.runtime.common")
local paths = require("arch_view.internal.paths")
local service = require("arch_view.internal.service")
local fs = require("arch_view.runtime.fs")

local cli = {}

local _flag_fields = {
  ["--project-root"] = "project_root",
  ["--config"] = "config_path",
  ["--out"] = "out_path",
  ["--out-dir"] = "out_dir",
  ["--in-json"] = "in_json",
}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _usage(command_name)
  local name = tostring(command_name or "arch_view")
  local prefix = "  lua " .. name
  io.write(_text("用法", "Usage") .. ":\n")
  io.write(prefix .. " scan --out <file> [--project-root <dir>] [--config <file>] [--pinned-layers]\n")
  io.write(prefix .. " check [--project-root <dir>] [--config <file>]\n")
  io.write(prefix .. " viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--pinned-layers] [--open]\n")
  io.write(prefix .. "\n")
end

local function _parse_args(args)
  local options = {
    command = args[1],
    project_root = nil,
    config_path = nil,
    out_path = nil,
    out_dir = nil,
    in_json = nil,
    open = false,
    pinned_layers = false,
  }
  local index = 2
  while index <= #args do
    local token = args[index]
    local field = _flag_fields[token]
    if field ~= nil then
      options[field] = args[index + 1]
      index = index + 2
    elseif token == "--open" then
      options.open = true
      index = index + 1
    elseif token == "--pinned-layers" then
      options.pinned_layers = true
      index = index + 1
    else
      error(_text(
        "未知参数: " .. tostring(token),
        "Unknown flag: " .. tostring(token)
      ))
    end
  end
  return options
end

local function _normalize_options(parsed, opts)
  opts = opts or {}
  local cwd = opts.cwd and fs.resolve_path(fs.current_dir(), opts.cwd) or fs.current_dir()
  local default_project_root = opts.default_project_root and fs.resolve_path(cwd, opts.default_project_root) or cwd
  local project_root = parsed.project_root and fs.resolve_path(cwd, parsed.project_root) or default_project_root
  return {
    project_root = project_root,
    config_path = parsed.config_path and fs.resolve_path(cwd, parsed.config_path)
      or (opts.default_config_path and fs.resolve_path(cwd, opts.default_config_path) or nil),
    out_path = paths.resolve_project_path(project_root, parsed.out_path),
    out_dir = paths.resolve_project_path(project_root, parsed.out_dir),
    in_json = paths.resolve_project_path(project_root, parsed.in_json),
    open = parsed.open,
    pinned_layers = parsed.pinned_layers,
    asset_root = opts.asset_root and fs.resolve_path(cwd, opts.asset_root) or paths.default_asset_root(),
    open_path = opts.open_path,
  }
end

local function _call_service(service_fn, options)
  local result, err = service_fn(options)
  if result == nil then
    error(err, 2)
  end
  return result
end

local function _run_check(options)
  local result = _call_service(service.check, options)
  local check = result.check or {}
  if check.ok then
    print(_text("arch_view 检查通过", "arch_view check ok"))
    return true
  end
  io.stderr:write(_text("arch_view 检查失败", "arch_view check failed"), "\n")
  for _, violation in ipairs(check.violations or {}) do
    if violation.kind == "forbidden_dependency" then
      io.stderr:write("  ", _text("禁止依赖", "forbidden_dependency"), " [", tostring(violation.rule), "] ", tostring(violation.from), " -> ", tostring(violation.to), "\n")
      io.stderr:write("    ", tostring(violation.description), "\n")
    elseif violation.kind == "unclassified_module" then
      io.stderr:write("  ", _text("未分类模块", "unclassified_module"), " ", tostring(violation.module_id), "\n")
    elseif violation.kind == "projection_cycle" then
      io.stderr:write("  ", _text("投影循环", "projection_cycle"), " ", tostring(violation.view), "\n")
      io.stderr:write("    ", tostring(violation.description), "\n")
    else
      io.stderr:write("  ", tostring(violation.kind), " ", table.concat(violation.cycle or {}, ", "), "\n")
      io.stderr:write("    ", tostring(violation.description), "\n")
    end
  end
  os.exit(1)
end

function cli.run(args, opts)
  opts = opts or {}
  local parsed = _parse_args(args or {})
  local command = parsed.command
  if command == "--help" or command == "-h" then
    _usage(opts.command_name)
    return true
  end
  if command == nil then
    parsed.command = "viewer"
    parsed.open = true
    command = parsed.command
  end

  local options = _normalize_options(parsed, opts)

  if command == "scan" then
    local result = _call_service(service.write_scan, options)
    print(_text("arch_view 扫描完成: ", "arch_view scan ok: ") .. result.out_path)
    return true
  end
  if command == "check" then
    return _run_check(options)
  end
  if command == "viewer" then
    local result = _call_service(service.export_viewer, options)
    print(_text("arch_view 视图已生成: ", "arch_view viewer ok: ") .. result.out_dir)
    return true
  end

  _usage(opts.command_name)
  error(_text(
    "未知命令: " .. tostring(command),
    "Unknown command: " .. tostring(command)
  ))
end

return cli
