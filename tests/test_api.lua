local arch_view = require("arch_view")
local lu = require("luaunit")
local common = require("arch_view.runtime.common")
local json_reader = require("arch_view.runtime.json_reader")

local helpers = dofile("tests/helpers.lua")

local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_api")


local function _assert_contains(list, expected, message)
    for _, value in ipairs(list or {}) do
        if value == expected then
            return
        end
    end
    error((message or "missing value") .. "\nmissing: " .. tostring(expected))
end

local function _read_file(path)
    local content, err = common.read_file(path)
    if content == nil then
        error(err)
    end
    return content
end

local function _write_file(path, content)
    local ok, err = common.write_file(path, content)
    if not ok then
        error(err)
    end
end

local function _assert_not_contains(text, expected, message)
    if tostring(text or ""):find(expected, 1, true) ~= nil then
        error((message or "unexpected value present") .. "\nunexpected: " .. tostring(expected))
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
    _write_file(common.join_path(project_root, "src/core_module.lua"), 'local init = require("init")\nreturn {}')
end

-- A project whose ONLY gate fact is a projection cycle: two modules that
-- require each other. Everything is classified and no forbidden rule fires.
local function _write_cycle_project(project_root, config_extra)
    _mkdir(project_root)
    _mkdir(common.join_path(project_root, "src"))
    local config = [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
]]
    if config_extra ~= nil then
        config = config .. ",\n" .. config_extra .. "\n"
    end
    config = config .. "}\n"
    _write_file(common.join_path(project_root, "arch_view.config.json"), config)
    _write_file(common.join_path(project_root, "src/init.lua"), "return {}")
    _write_file(common.join_path(project_root, "src/alpha.lua"), 'local beta = require("src.beta")\nreturn {}')
    _write_file(common.join_path(project_root, "src/beta.lua"), 'local alpha = require("src.alpha")\nreturn {}')
end

local function _analyze(project_root)
    local architecture, err = arch_view.analyze({ project_root = project_root })
    if architecture == nil then
        error(err)
    end
    return architecture
end

local function _find_violation(check, kind)
    for _, violation in ipairs(check.violations or {}) do
        if violation.kind == kind then
            return violation
        end
    end
    return nil
end

-- Issue #3: check must report the projection cycle it sees (same layout the
-- viewer renders) and fail closed — a cycle-only project is NOT ok.
local function test_projection_cycle_fails_check()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "cycle_project")
        _write_cycle_project(project_root)

        local architecture = _analyze(project_root)
        local check = architecture.check

        lu.assertTrue(check.cycles == nil, "v3 drops the dead check.cycles shell")
        lu.assertTrue(type(check.projection_cycles) == "table",
            "check.projection_cycles must be a table")
        lu.assertEquals(#check.projection_cycles, 1,
            "the alpha<->beta cycle must be reported exactly once")
        local entry = check.projection_cycles[1]
        lu.assertEquals(entry.view, "root", "cycle entry names its owning view")
        lu.assertEquals(entry.cycle, "alpha->beta->alpha",
            "cycle entry carries the same closed line the viewer shows")
        lu.assertEquals(entry.nodes, { "alpha", "beta" },
            "cycle entry carries its participant nodes")
        lu.assertTrue(entry.waived == false, "unwaived cycle is marked waived = false")

        local violation = _find_violation(check, "projection_cycle")
        lu.assertTrue(violation ~= nil, "unwaived cycle must produce a projection_cycle violation")
        lu.assertEquals(violation.view, "root")
        lu.assertEquals(violation.cycle, "alpha->beta->alpha")
        lu.assertTrue(check.ok == false, "a projection cycle alone must fail the check")
    end)
end

-- Issue #3: a config allowed_cycles entry matching view + participant set
-- waives the cycle: reported as waived, no violation, check passes.
local function test_allowed_cycles_waives_projection_cycle()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "waived_cycle_project")
        _write_cycle_project(project_root, [[
  "allowed_cycles": [
    {"view": "root", "nodes": ["alpha", "beta"], "reason": "accepted pattern"}
  ]
]]
        )

        local architecture = _analyze(project_root)
        local check = architecture.check

        lu.assertEquals(#check.projection_cycles, 1, "waived cycle is still reported")
        local entry = check.projection_cycles[1]
        lu.assertTrue(entry.waived == true, "matched waiver marks the entry waived")
        lu.assertEquals(entry.reason, "accepted pattern",
            "waived entry carries the waiver's reason")
        lu.assertTrue(_find_violation(check, "projection_cycle") == nil,
            "waived cycle must NOT produce a violation")
        lu.assertTrue(check.ok == true, "an all-waived cycle set passes the check")
    end)
end

-- Issue #3: a waiver that does not match (different participants, or a
-- different view) leaves the cycle unwaived and the check failing.
local function test_unmatched_allowed_cycles_still_fails()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "unmatched_waiver_project")
        _write_cycle_project(project_root, [[
  "allowed_cycles": [
    {"view": "root", "nodes": ["alpha", "gamma"]},
    {"view": "other", "nodes": ["alpha", "beta"]}
  ]
]]
        )

        local architecture = _analyze(project_root)
        local check = architecture.check

        lu.assertEquals(#check.projection_cycles, 1)
        lu.assertTrue(check.projection_cycles[1].waived == false,
            "non-matching waivers must not waive the cycle")
        lu.assertTrue(_find_violation(check, "projection_cycle") ~= nil,
            "unwaived cycle still violates")
        lu.assertTrue(check.ok == false, "unmatched waiver leaves the check failing")
    end)
end

local function test_analyze_basic()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "analyze_project")
        _write_sample_project(project_root)

        local architecture, err = arch_view.analyze({
            project_root = project_root,
        })
        if architecture == nil then
            error(err)
        end

        lu.assertTrue(type(architecture.graph) == "table", "architecture should have graph")
        lu.assertTrue(type(architecture.modules) == "table", "architecture should have modules")
        lu.assertTrue(type(architecture.check) == "table", "architecture should have check")

        -- Contract v3 (arch_view #3): schema_version = 3, projection cycles
        -- are a real gate fact, and the v1/v2 dead fields stay gone.
        lu.assertTrue(architecture.schema_version == 3, "schema_version should be 3")
        lu.assertTrue(architecture.layout == nil, "v2 drops the top-level layout shell")
        lu.assertTrue(architecture.classified_edges == nil, "v2 drops classified_edges (no consumers)")
        lu.assertTrue(architecture.projection_cycles == nil, "v2 drops the top-level projection_cycles shell")
        local root_view = architecture.views["root"]
        lu.assertTrue(type(root_view) == "table", "root view should exist")
        lu.assertTrue(type(root_view.display_edges) == "table", "view keeps display_edges")
        lu.assertTrue(root_view.edges == nil, "v2 drops the edges/display_edges duplicate alias")
        for _, edge in ipairs(root_view.display_edges) do
            lu.assertTrue(edge.arrowhead == nil, "v2 drops the dead arrowhead field")
            lu.assertTrue(edge.route_points == nil, "v2 drops the dead route_points field")
        end
    end)
end

local function test_check_returns_result()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "check_project")
        _write_sample_project(project_root)

        local result, err = arch_view.check({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        lu.assertTrue(type(result.check) == "table", "check result should have check field")
        lu.assertTrue(type(result.check.ok) == "boolean", "check.ok should be boolean")
        lu.assertTrue(result.project_root == project_root, "should return project root")
    end)
end

local function test_write_scan_creates_file()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "scan_project")
        local out_path = common.join_path(project_root, ".arch_view/architecture.json")
        _write_sample_project(project_root)

        local result, err = arch_view.write_scan({
            project_root = project_root,
            out_path = out_path,
        })
        if result == nil then
            error(err)
        end

        lu.assertTrue(_exists(out_path), "scan should write output file")
        local content = _read_file(out_path)
        lu.assertTrue(#content > 0, "output file should not be empty")
    end)
end

local function test_export_viewer_creates_files()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "viewer_project")
        _write_sample_project(project_root)

        local result, err = arch_view.export_viewer({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        lu.assertTrue(_exists(result.index_path), "viewer should write index.html")
        lu.assertTrue(_exists(common.join_path(result.out_dir, "architecture.json")), "viewer should write architecture.json")
        lu.assertTrue(_exists(common.join_path(result.out_dir, "architecture_data.js")), "viewer should write architecture_data.js")
        lu.assertTrue(_exists(common.join_path(result.out_dir, "script.js")), "viewer should copy script.js")
        lu.assertTrue(_exists(common.join_path(result.out_dir, "styles.css")), "viewer should copy styles.css")
    end)
end

-- The --in-json readback path takes a v2 scan file and re-exports it
-- verbatim: schema_version = 2 survives and no v1 dead field reappears
-- (monopoly #231).
local function test_export_viewer_in_json_roundtrip_v2()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "in_json_project")
        local scan_path = common.join_path(project_root, ".arch_view/architecture.json")
        _write_sample_project(project_root)

        local scan_result, scan_err = arch_view.write_scan({
            project_root = project_root,
            out_path = scan_path,
        })
        if scan_result == nil then
            error(scan_err)
        end

        local result, err = arch_view.export_viewer({
            project_root = project_root,
            in_json = scan_path,
        })
        if result == nil then
            error(err)
        end

        local exported = _read_file(common.join_path(result.out_dir, "architecture.json"))
        local decoded = json_reader.decode(exported)
        lu.assertTrue(decoded.schema_version == 3, "--in-json roundtrip should carry schema_version = 3")
        lu.assertTrue(decoded.layout == nil, "v2 JSON has no top-level layout shell")
        lu.assertTrue(decoded.classified_edges == nil, "v2 JSON has no classified_edges")
        lu.assertTrue(decoded.projection_cycles == nil, "v2 JSON has no top-level projection_cycles shell")
        lu.assertTrue(decoded.views ~= nil and decoded.views["root"] ~= nil, "v2 JSON keeps views")
        lu.assertTrue(decoded.views["root"].edges == nil, "v2 view has no edges alias of display_edges")
        lu.assertTrue(decoded.views["root"].display_edges ~= nil, "v2 view keeps display_edges")
    end)
end

local function test_viewer_export_is_self_contained()
    _with_clean_tmp(function()
        local project_root = common.join_path(tmp_root, "self_contained_project")
        local out_dir = common.join_path(project_root, ".arch_view/viewer")
        _write_sample_project(project_root)

        local result, err = arch_view.export_viewer({
            project_root = project_root,
        })
        if result == nil then
            error(err)
        end

        local exported_index = _read_file(common.join_path(out_dir, "index.html"))
        local exported_styles = _read_file(common.join_path(out_dir, "styles.css"))
        _assert_not_contains(exported_index, "fonts.googleapis.com", "viewer should not depend on Google Fonts")
        _assert_not_contains(exported_index, "fonts.gstatic.com", "viewer should not depend on Google Fonts")
    end)
end

return {
    test_projection_cycle_fails_check = test_projection_cycle_fails_check,
    test_allowed_cycles_waives_projection_cycle = test_allowed_cycles_waives_projection_cycle,
    test_unmatched_allowed_cycles_still_fails = test_unmatched_allowed_cycles_still_fails,
    test_analyze_basic = test_analyze_basic,
    test_check_returns_result = test_check_returns_result,
    test_write_scan_creates_file = test_write_scan_creates_file,
    test_export_viewer_creates_files = test_export_viewer_creates_files,
    test_export_viewer_in_json_roundtrip_v2 = test_export_viewer_in_json_roundtrip_v2,
    test_viewer_export_is_self_contained = test_viewer_export_is_self_contained,
}
