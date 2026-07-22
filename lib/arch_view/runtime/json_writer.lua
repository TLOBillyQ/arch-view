local common = require("arch_view.runtime.common")

local json_writer = {}

local _escape_replacements = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\r"] = "\\r",
    ["\n"] = "\\n",
    ["\t"] = "\\t",
}

local function _escape_string(value)
    local escaped = tostring(value or "")
    return (escaped:gsub("[\"\\\r\n\t]", _escape_replacements))
end

-- Marker metatable for lists that may be empty: an empty Lua table is
-- ambiguous, and the encoder treats it as an empty OBJECT ({}). Producers
-- wrap empty-capable lists with json_writer.array so they encode as [].
local _array_metatable = {}

local function _is_array(value)
    if type(value) ~= "table" then
        return false
    end
    if getmetatable(value) == _array_metatable then
        return true
    end
    local count = 0
    for key in pairs(value) do
        local normalized_key = common.to_integer(key)
        if normalized_key == nil or normalized_key ~= key or normalized_key < 1 then
            return false
        end
        count = count + 1
    end
    if count == 0 then
        -- Empty table: encodes as an empty object ({}), never as [].
        return false
    end
    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end
    return true
end

local function _encode(value)
    local value_type = type(value)
    if value_type == "nil" then
        return "null"
    end
    if value_type == "string" then
        return "\"" .. _escape_string(value) .. "\""
    end
    if value_type == "boolean" or common.is_numeric(value) then
        return tostring(value)
    end
    if value_type ~= "table" then
        return "\"" .. _escape_string(tostring(value)) .. "\""
    end

    if _is_array(value) then
        local parts = {}
        for _, item in ipairs(value) do
            parts[#parts + 1] = _encode(item)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local fields = {}
    for key, field_value in common.sorted_pairs(value) do
        fields[#fields + 1] = "\"" .. _escape_string(key) .. "\":" .. _encode(field_value)
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

function json_writer.encode(value)
    return _encode(value)
end

-- Mark a list so it encodes as a JSON array even when empty. The metatable
-- is invisible to pairs/ipairs, so Lua-side consumers are unaffected.
function json_writer.array(value)
    return setmetatable(value or {}, _array_metatable)
end

return json_writer
