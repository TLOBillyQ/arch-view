-- Shared helpers for the arch_view golden-output test scripts.
-- All scripts must be run with the repository root as the current working
-- directory, e.g. `lua tests/compare.lua` from the repo root.

local helpers = {}

helpers.PROJECT_ROOT = "tests/fixture"
helpers.CONFIG_PATH = "tests/fixture/arch_view.config.json"
helpers.GOLDEN_DIR = "tests/golden"

-- Placeholder that replaces the absolute repository root inside generated
-- output, so golden files stay byte-stable across machine checkouts.
helpers.ROOT_PLACEHOLDER = "__ARCH_VIEW_ROOT__"

function helpers.fail(message)
  io.stderr:write(tostring(message) .. "\n")
  os.exit(1)
end

-- Run fn(tmp_root) with a fresh, empty directory under the system temp dir.
-- The directory is removed afterwards either way; fn errors propagate.
function helpers.with_clean_tmp(name, fn)
  local common = require("arch_view.runtime.common")
  local tmp_root = common.join_path(common.system_tmp_dir(), name)
  common.remove_path(tmp_root)
  local ok, err = pcall(fn, tmp_root)
  common.remove_path(tmp_root)
  if not ok then
    error(err)
  end
end

-- Resolve the current working directory the same way the library does
-- (lib/arch_view/runtime/host.lua common.current_dir uses `pwd`), so the
-- string we strip during normalization is exactly the string the library
-- embeds into its output.
function helpers.repo_root()
  local process = io.popen("pwd")
  if process == nil then
    helpers.fail("error: cannot determine current directory (popen pwd failed)")
  end
  local path = process:read("*l") or "."
  process:close()
  return (tostring(path):gsub("\\", "/"))
end

-- Verify cwd is the repository root and prepend lib/ to package.path.
-- Returns the absolute repository root.
function helpers.setup()
  local root = helpers.repo_root()
  local probe = io.open(root .. "/lib/arch_view/init.lua", "rb")
  if probe == nil then
    helpers.fail("error: run this script from the repository root "
      .. "(lib/arch_view/init.lua not found under " .. root .. ")")
  end
  probe:close()
  package.path = root .. "/lib/?.lua;" .. root .. "/lib/?/init.lua;" .. package.path
  return root
end

function helpers.read_file(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

function helpers.write_file(path, content)
  local file = io.open(path, "wb")
  if file == nil then
    return nil, "cannot open for write: " .. tostring(path)
  end
  file:write(content)
  file:close()
  return true
end

local function escape_pattern(text)
  return (tostring(text):gsub("%W", "%%%1"))
end

-- Replace every occurrence of the absolute repository root with a fixed
-- placeholder. This only rewrites the machine-specific path prefix; all
-- relative layout and content differences survive untouched.
function helpers.normalize(content, root)
  return (tostring(content):gsub(escape_pattern(root), helpers.ROOT_PLACEHOLDER))
end

-- Run analyze + write_scan + export_viewer against the fixture, writing the
-- three golden artifacts into out_dir:
--   out_dir/scan/architecture.json     (from write_scan)
--   out_dir/viewer/architecture.json   (from export_viewer)
--   out_dir/viewer/architecture_data.js
-- Returns a table with the three output paths.
function helpers.generate_outputs(root, out_dir)
  local arch_view = require("arch_view")
  local fs = require("arch_view.runtime.fs")

  local architecture, analyze_err = arch_view.analyze({
    project_root = helpers.PROJECT_ROOT,
    config_path = helpers.CONFIG_PATH,
  })
  if architecture == nil then
    helpers.fail("error: analyze failed: " .. tostring(analyze_err))
  end

  local scan_path = fs.join_path(out_dir, "scan/architecture.json")
  local scan_result, scan_err = arch_view.write_scan({
    architecture = architecture,
    project_root = helpers.PROJECT_ROOT,
    out_path = scan_path,
  })
  if scan_result == nil then
    helpers.fail("error: write_scan failed: " .. tostring(scan_err))
  end

  local viewer_dir = fs.join_path(out_dir, "viewer")
  local viewer_result, viewer_err = arch_view.export_viewer({
    architecture = architecture,
    project_root = helpers.PROJECT_ROOT,
    out_dir = viewer_dir,
  })
  if viewer_result == nil then
    helpers.fail("error: export_viewer failed: " .. tostring(viewer_err))
  end

  return {
    scan_json = scan_path,
    viewer_json = fs.join_path(viewer_dir, "architecture.json"),
    viewer_data_js = fs.join_path(viewer_dir, "architecture_data.js"),
  }
end

return helpers
