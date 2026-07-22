-- Unit tests for the JSON writer's type discrimination (monopoly #231):
-- an empty Lua table is an empty OBJECT and must encode as "{}", never "[]";
-- lists that may be empty are marked explicitly with json_writer.array.

local json_writer = require("arch_view.runtime.json_writer")

local helpers = dofile("tests/helpers.lua")

local _assert_eq = helpers.assert_eq

local function test_empty_table_encodes_as_object()
    _assert_eq(json_writer.encode({}), "{}", "empty table should encode as {}")
end

local function test_marked_empty_table_encodes_as_array()
    _assert_eq(json_writer.encode(json_writer.array({})), "[]",
        "json_writer.array({}) should encode as []")
end

local function test_non_empty_array_still_encodes_as_array()
    _assert_eq(json_writer.encode({ 1, 2, 3 }), "[1,2,3]")
end

local function test_non_empty_map_still_encodes_as_object()
    _assert_eq(json_writer.encode({ a = 1 }), '{"a":1}')
end

local function test_nested_empty_containers_keep_their_kind()
    _assert_eq(
        json_writer.encode({ list = json_writer.array({}), map = {} }),
        '{"list":[],"map":{}}',
        "nested empty array and empty object should keep distinct encodings")
end

local function test_marked_non_empty_array_encodes_as_array()
    _assert_eq(json_writer.encode(json_writer.array({ "a", "b" })), '["a","b"]')
end

return {
    test_empty_table_encodes_as_object = test_empty_table_encodes_as_object,
    test_marked_empty_table_encodes_as_array = test_marked_empty_table_encodes_as_array,
    test_non_empty_array_still_encodes_as_array = test_non_empty_array_still_encodes_as_array,
    test_non_empty_map_still_encodes_as_object = test_non_empty_map_still_encodes_as_object,
    test_nested_empty_containers_keep_their_kind = test_nested_empty_containers_keep_their_kind,
    test_marked_non_empty_array_encodes_as_array = test_marked_non_empty_array_encodes_as_array,
}
