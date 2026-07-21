local analyzer = require("arch_view.internal.analyzer")
local config_loader = require("arch_view.internal.config")
local paths = require("arch_view.internal.paths")
local common = require("arch_view.runtime.common")
local fs = require("arch_view.runtime.fs")
local json_writer = require("arch_view.runtime.json_writer")

local service = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _resolved_project_root(opts)
  local cwd = fs.current_dir()
  return fs.resolve_path(cwd, opts and opts.project_root or cwd)
end

local function _resolve_context(opts)
  opts = opts or {}
  local resolved, err = config_loader.resolve(opts)
  if resolved == nil then
    return nil, err
  end
  resolved.package_root = opts.package_root or paths.package_root()
  return resolved
end

local function _ensure_architecture(opts)
  if opts.architecture ~= nil then
    return opts.architecture
  end
  return service.analyze(opts)
end

local function _read_architecture_json_text(path)
  local content, err = fs.read_file(path)
  if content == nil then
    return nil, err
  end
  return content:match("^%s*(.-)%s*$")
end

local function _export_viewer_payload(architecture_json_text, architecture, project_root, out_dir, asset_root, opts)
  local ok, mkdir_err = fs.ensure_dir(out_dir)
  if not ok then
    return nil, mkdir_err
  end

  local copy_ok, copy_err = fs.copy_tree(asset_root, out_dir)
  if not copy_ok then
    return nil, copy_err
  end

  local write_ok, write_err = fs.write_file(fs.join_path(out_dir, "architecture.json"), architecture_json_text)
  if not write_ok then
    return nil, write_err
  end

  write_ok, write_err = fs.write_file(
    fs.join_path(out_dir, "architecture_data.js"),
    "window.ARCH_VIEW_DATA = " .. architecture_json_text .. ";\n"
  )
  if not write_ok then
    return nil, write_err
  end

  local index_path = fs.join_path(out_dir, "index.html")
  if opts.open then
    local open_fn = opts.open_path or fs.open_path
    local opened, open_err = open_fn(index_path)
    if not opened then
      return nil, open_err
    end
  end

  return {
    out_dir = out_dir,
    index_path = index_path,
    architecture = architecture,
    asset_root = asset_root,
    project_root = project_root,
  }
end

function service.load_config(path)
  return config_loader.load(path)
end

function service.analyze(opts)
  local resolved, err = _resolve_context(opts)
  if resolved == nil then
    return nil, err
  end
  return analyzer.analyze(resolved)
end

function service.check(opts)
  local architecture, err = service.analyze(opts)
  if architecture == nil then
    return nil, err
  end
  return {
    check = architecture.check,
    project_root = architecture.project_root,
    config_path = architecture.config_path,
  }
end

function service.write_scan(opts)
  opts = opts or {}
  local project_root = _resolved_project_root(opts)
  local out_path = paths.resolve_project_path(project_root, opts.out_path)
  if out_path == nil then
    return nil, _text(
      "scan 命令需要输出文件路径",
      "scan command requires an output file path"
    )
  end

  local architecture, err = _ensure_architecture(opts)
  if architecture == nil then
    return nil, err
  end

  local write_ok, write_err = fs.write_file(out_path, json_writer.encode(architecture))
  if not write_ok then
    return nil, write_err
  end

  return {
    out_path = out_path,
    architecture = architecture,
    project_root = project_root,
    config_path = architecture.config_path or opts.config_path,
  }
end

function service.export_viewer(opts)
  opts = opts or {}
  local project_root = _resolved_project_root(opts)
  local out_dir = paths.resolve_project_path(project_root, opts.out_dir)
    or paths.default_viewer_out_dir(project_root)
  local asset_root = opts.asset_root and fs.resolve_path(fs.current_dir(), opts.asset_root)
    or paths.default_asset_root()

  local architecture = opts.architecture
  local architecture_json_text = nil
  if architecture ~= nil then
    architecture_json_text = json_writer.encode(architecture)
  elseif opts.in_json ~= nil then
    local err
    architecture_json_text, err = _read_architecture_json_text(paths.resolve_project_path(project_root, opts.in_json))
    if architecture_json_text == nil then
      return nil, err
    end
  else
    local err
    architecture, err = _ensure_architecture(opts)
    if architecture == nil then
      return nil, err
    end
    architecture_json_text = json_writer.encode(architecture)
  end

  return _export_viewer_payload(architecture_json_text, architecture, project_root, out_dir, asset_root, opts)
end

return service
