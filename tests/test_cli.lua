local cli = require("arch_view.cli")
local lu = require("luaunit")
local common = require("arch_view.runtime.common")

local helpers = dofile("tests/helpers.lua")

local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_cli")

local function _write_file(path, content)
    local ok, err = common.write_file(path, content)
    if not ok then
        error(err)
    end
end

local function _exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function _mkdir(path)
    local ok, err = common.ensure_dir(path)
    if not ok then
        error(err)
    end
end

local function _with_clean_tmp(fn)
    common.remove_path(tmp_root)
    _mkdir(tmp_root)
    local ok, err = pcall(fn)
    common.remove_path(tmp_root)
    if not ok then
        error(err)
    end
end

local function _write_sample_project(project_root)
    _mkdir(project_root)
    _mkdir(common.join_path(project_root, "src"))
    _write_file(common.join_path(project_root, "arch_view.config.json"), [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
}
]])
    _write_file(common.join_path(project_root, "src/init.lua"), "return {}")
end

local function test_cli_scan_command()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_scan")
        local out_path = ".arch_view/architecture.json"
        _write_sample_project(project_root)

        local result = cli.run({"scan", "--out", out_path}, {
            default_project_root = project_root,
        })

        lu.assertTrue(result == true, "cli scan should succeed")
        lu.assertTrue(_exists(common.join_path(project_root, out_path)), "cli scan should write output")
    end)
end

local function test_cli_check_command()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_check")
        _write_sample_project(project_root)

        local ok, err = pcall(function()
            cli.run({"check"}, {
                default_project_root = project_root,
            })
        end)

        lu.assertTrue(ok, "cli check should succeed: " .. tostring(err))
    end)
end

-- Issue #3: check fails closed on a projection cycle — cli.run returns false
-- so the host wrapper exits non-zero.
local function test_cli_check_fails_on_projection_cycle()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_cycle")
        helpers.write_cycle_project(project_root)

        local result = cli.run({"check"}, {
            default_project_root = project_root,
        })

        lu.assertTrue(result == false, "cli check should fail on an unwaived projection cycle")
    end)
end

-- Issue #3: a matching allowed_cycles waiver turns the same project green.
local function test_cli_check_passes_with_waived_cycle()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_cycle_waived")
        helpers.write_cycle_project(project_root, [[
  "allowed_cycles": [
    {"view": "root", "nodes": ["alpha", "beta"], "reason": "accepted pattern"}
  ]
]]
        )

        local result = cli.run({"check"}, {
            default_project_root = project_root,
        })

        lu.assertTrue(result == true, "cli check should pass when every cycle is waived")
    end)
end

local function test_cli_viewer_command()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_viewer")
        local out_dir = ".arch_view/viewer"
        _write_sample_project(project_root)

        local result = cli.run({"viewer", "--out-dir", out_dir}, {
            default_project_root = project_root,
        })

        lu.assertTrue(result == true, "cli viewer should succeed")
        lu.assertTrue(_exists(common.join_path(project_root, out_dir, "index.html")), "cli viewer should write index.html")
    end)
end

local function test_cli_respects_project_root()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_root")
        _write_sample_project(project_root)

        local result = cli.run({
            "scan",
            "--out", ".arch_view/out.json",
            "--project-root", project_root,
        })

        lu.assertTrue(result == true, "cli should respect --project-root")
        lu.assertTrue(_exists(common.join_path(project_root, ".arch_view/out.json")), "output should be in project root")
    end)
end

local function test_cli_viewer_respects_project_root_for_relative_out_dir()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_viewer_root")
        _write_sample_project(project_root)

        local result = cli.run({
            "viewer",
            "--out-dir", ".arch_view/custom-viewer",
            "--project-root", project_root,
        })

        lu.assertTrue(result == true, "cli viewer should respect --project-root")
        lu.assertTrue(_exists(common.join_path(project_root, ".arch_view/custom-viewer/index.html")),
            "viewer output should be rooted at project_root")
    end)
end

local function test_cli_scan_pinned_layers_flag()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cli_pinned")
        local out_path = ".arch_view/architecture.json"
        _write_sample_project(project_root)

        local result = cli.run({"scan", "--out", out_path, "--pinned-layers"}, {
            default_project_root = project_root,
        })

        lu.assertTrue(result == true, "cli scan --pinned-layers should succeed")
        local file = assert(io.open(common.join_path(project_root, out_path), "r"))
        local content = file:read("*a")
        file:close()
        lu.assertTrue(content:find('"pinned_layers":%s*true') ~= nil,
            "scan output should record the pinned-layers mode")
    end)
end

return {
    test_cli_scan_command = test_cli_scan_command,
    test_cli_scan_pinned_layers_flag = test_cli_scan_pinned_layers_flag,
    test_cli_check_command = test_cli_check_command,
    test_cli_check_fails_on_projection_cycle = test_cli_check_fails_on_projection_cycle,
    test_cli_check_passes_with_waived_cycle = test_cli_check_passes_with_waived_cycle,
    test_cli_viewer_command = test_cli_viewer_command,
    test_cli_respects_project_root = test_cli_respects_project_root,
    test_cli_viewer_respects_project_root_for_relative_out_dir = test_cli_viewer_respects_project_root_for_relative_out_dir,
}
