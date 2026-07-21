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

local function _is_array(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        local normalized_key = common.to_integer(key)
        if normalized_key == nil or normalized_key ~= key or normalized_key < 1 then
            return false
        end
        count = count + 1
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

return json_writer
