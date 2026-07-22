local arch_view = require("arch_view")
local common = require("arch_view.runtime.common")
local json_reader = require("arch_view.runtime.json_reader")

local helpers = dofile("tests/helpers.lua")

local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_api")

local _assert_eq = helpers.assert_eq

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

        assert(type(architecture.graph) == "table", "architecture should have graph")
        assert(type(architecture.modules) == "table", "architecture should have modules")
        assert(type(architecture.check) == "table", "architecture should have check")

        -- Contract v2 (monopoly #231): schema_version = 2 and the v1 dead
        -- fields (redundant aliases, unconsumed shells) are gone.
        assert(architecture.schema_version == 2, "schema_version should be 2")
        assert(architecture.layout == nil, "v2 drops the top-level layout shell")
        assert(architecture.classified_edges == nil, "v2 drops classified_edges (no consumers)")
        assert(architecture.projection_cycles == nil, "v2 drops the top-level projection_cycles shell")
        local root_view = architecture.views["root"]
        assert(type(root_view) == "table", "root view should exist")
        assert(type(root_view.display_edges) == "table", "view keeps display_edges")
        assert(root_view.edges == nil, "v2 drops the edges/display_edges duplicate alias")
        for _, edge in ipairs(root_view.display_edges) do
            assert(edge.arrowhead == nil, "v2 drops the dead arrowhead field")
            assert(edge.route_points == nil, "v2 drops the dead route_points field")
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

        assert(type(result.check) == "table", "check result should have check field")
        assert(type(result.check.ok) == "boolean", "check.ok should be boolean")
        assert(result.project_root == project_root, "should return project root")
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

        assert(_exists(out_path), "scan should write output file")
        local content = _read_file(out_path)
        assert(#content > 0, "output file should not be empty")
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

        assert(_exists(result.index_path), "viewer should write index.html")
        assert(_exists(common.join_path(result.out_dir, "architecture.json")), "viewer should write architecture.json")
        assert(_exists(common.join_path(result.out_dir, "architecture_data.js")), "viewer should write architecture_data.js")
        assert(_exists(common.join_path(result.out_dir, "script.js")), "viewer should copy script.js")
        assert(_exists(common.join_path(result.out_dir, "styles.css")), "viewer should copy styles.css")
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
        assert(decoded.schema_version == 2, "--in-json roundtrip should carry schema_version = 2")
        assert(decoded.layout == nil, "v2 JSON has no top-level layout shell")
        assert(decoded.classified_edges == nil, "v2 JSON has no classified_edges")
        assert(decoded.projection_cycles == nil, "v2 JSON has no top-level projection_cycles shell")
        assert(decoded.views ~= nil and decoded.views["root"] ~= nil, "v2 JSON keeps views")
        assert(decoded.views["root"].edges == nil, "v2 view has no edges alias of display_edges")
        assert(decoded.views["root"].display_edges ~= nil, "v2 view keeps display_edges")
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
    test_analyze_basic = test_analyze_basic,
    test_check_returns_result = test_check_returns_result,
    test_write_scan_creates_file = test_write_scan_creates_file,
    test_export_viewer_creates_files = test_export_viewer_creates_files,
    test_export_viewer_in_json_roundtrip_v2 = test_export_viewer_in_json_roundtrip_v2,
    test_viewer_export_is_self_contained = test_viewer_export_is_self_contained,
}
