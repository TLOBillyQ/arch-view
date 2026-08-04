-- Config validation for the allowed_cycles waiver mechanism (arch_view #3).
-- A waiver entry is { "view": <view key>, "nodes": [<participant names>],
-- "reason": <optional text> } and matches a reported projection cycle by
-- exact view key plus participant-set equality.

local config = require("arch_view.internal.config")
local lu = require("luaunit")
local common = require("arch_view.runtime.common")

local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_config")

local function _with_config_file(config_body, fn)
    common.remove_path(tmp_root)
    local ok, err = pcall(function()
        assert(common.ensure_dir(tmp_root))
        local path = common.join_path(tmp_root, "arch_view.config.json")
        assert(common.write_file(path, config_body))
        fn(config.load(path))
    end)
    common.remove_path(tmp_root)
    if not ok then
        error(err)
    end
end

local _base = [[
{
  "source_roots": ["src"],
  "component_rules": [
    {"name": "core", "match": ["^src$", "^src%..+"], "component": "core"}
  ]
]]

local function test_allowed_cycles_valid_shape_loads()
    _with_config_file(_base .. [[,
  "allowed_cycles": [
    {"view": "root", "nodes": ["alpha", "beta"], "reason": "accepted pattern"},
    {"view": "ui", "nodes": ["ui.registry"]}
  ]
}
]], function(loaded, err)
        lu.assertTrue(loaded ~= nil, "valid allowed_cycles must load: " .. tostring(err))
        lu.assertEquals(#loaded.allowed_cycles, 2)
        lu.assertEquals(loaded.allowed_cycles[1].reason, "accepted pattern")
    end)
end

local function test_missing_allowed_cycles_loads()
    _with_config_file(_base .. "\n}\n", function(loaded, err)
        lu.assertTrue(loaded ~= nil, "config without allowed_cycles must load: " .. tostring(err))
        lu.assertTrue(loaded.allowed_cycles == nil)
    end)
end

local function test_allowed_cycles_must_be_array()
    _with_config_file(_base .. [[,
  "allowed_cycles": {"view": "root", "nodes": ["a", "b"]}
}
]], function(loaded, err)
        lu.assertTrue(loaded == nil, "non-array allowed_cycles must be rejected")
        lu.assertTrue(tostring(err):find("allowed_cycles") ~= nil,
            "error must name the field, got " .. tostring(err))
    end)
end

local function test_allowed_cycles_entry_requires_view()
    _with_config_file(_base .. [[,
  "allowed_cycles": [
    {"nodes": ["alpha", "beta"]}
  ]
}
]], function(loaded, err)
        lu.assertTrue(loaded == nil, "entry without view must be rejected")
        lu.assertTrue(tostring(err):find("allowed_cycles%[1%]") ~= nil,
            "error must name the entry index, got " .. tostring(err))
    end)
end

local function test_allowed_cycles_entry_requires_nodes()
    _with_config_file(_base .. [[,
  "allowed_cycles": [
    {"view": "root"}
  ]
}
]], function(loaded, err)
        lu.assertTrue(loaded == nil, "entry without nodes must be rejected")
        lu.assertTrue(tostring(err):find("allowed_cycles%[1%]") ~= nil,
            "error must name the entry index, got " .. tostring(err))
    end)
end

local function test_allowed_cycles_nodes_must_be_non_empty_strings()
    _with_config_file(_base .. [[,
  "allowed_cycles": [
    {"view": "root", "nodes": ["alpha", 42]}
  ]
}
]], function(loaded, err)
        lu.assertTrue(loaded == nil, "non-string node must be rejected")
        lu.assertTrue(tostring(err):find("allowed_cycles%[1%]") ~= nil,
            "error must name the entry index, got " .. tostring(err))
    end)
end

return {
    test_allowed_cycles_valid_shape_loads = test_allowed_cycles_valid_shape_loads,
    test_missing_allowed_cycles_loads = test_missing_allowed_cycles_loads,
    test_allowed_cycles_must_be_array = test_allowed_cycles_must_be_array,
    test_allowed_cycles_entry_requires_view = test_allowed_cycles_entry_requires_view,
    test_allowed_cycles_entry_requires_nodes = test_allowed_cycles_entry_requires_nodes,
    test_allowed_cycles_nodes_must_be_non_empty_strings = test_allowed_cycles_nodes_must_be_non_empty_strings,
}
