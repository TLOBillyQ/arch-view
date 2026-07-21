local json_reader = {}

local _byte_space = string.byte(" ")
local _byte_lf = string.byte("\n")
local _byte_cr = string.byte("\r")
local _byte_tab = string.byte("\t")
local _byte_quote = string.byte("\"")
local _byte_comma = string.byte(",")
local _byte_colon = string.byte(":")
local _byte_minus = string.byte("-")
local _byte_plus = string.byte("+")
local _byte_dot = string.byte(".")
local _byte_open_brace = string.byte("{")
local _byte_close_brace = string.byte("}")
local _byte_open_bracket = string.byte("[")
local _byte_close_bracket = string.byte("]")
local _byte_e_lower = string.byte("e")
local _byte_e_upper = string.byte("E")
local _byte_f = string.byte("f")
local _byte_n = string.byte("n")
local _byte_t = string.byte("t")

local _escape_replacements = {
    [string.byte("\"")] = "\"",
    [string.byte("\\")] = "\\",
    [string.byte("/")] = "/",
    [string.byte("b")] = "\b",
    [string.byte("f")] = "\f",
    [string.byte("n")] = "\n",
    [string.byte("r")] = "\r",
    [string.byte("t")] = "\t",
}

local function _build_error(text, index)
    error("json decode error at " .. tostring(index) .. ": " .. tostring(text))
end

local function _is_whitespace(byte)
    return byte == _byte_space or byte == _byte_lf or byte == _byte_cr or byte == _byte_tab
end

local function _skip_whitespace(text, index)
    local cursor = index
    while cursor <= #text and _is_whitespace(string.byte(text, cursor)) do
        cursor = cursor + 1
    end
    return cursor
end

local function _parse_string(text, index)
    local cursor = index + 1
    local parts = {}
    local chunk_start = cursor
    while true do
        local special = string.find(text, "[\"\\]", cursor)
        if special == nil then
            _build_error("unterminated string", index)
        end
        parts[#parts + 1] = string.sub(text, chunk_start, special - 1)
        if string.byte(text, special) == _byte_quote then
            return table.concat(parts), special + 1
        end
        local escape = _escape_replacements[string.byte(text, special + 1)]
        if escape == nil then
            _build_error("unsupported escape sequence", special)
        end
        parts[#parts + 1] = escape
        cursor = special + 2
        chunk_start = cursor
    end
end

local function _digit_value(byte)
    if byte == nil then
        return nil
    end
    local digit = byte - 48
    if digit < 0 or digit > 9 then
        return nil
    end
    return digit
end

local function _parse_number(text, index)
    local cursor = index
    local sign = 1
    if string.byte(text, cursor) == _byte_minus then
        sign = -1
        cursor = cursor + 1
    end

    local int_value = 0
    local digit_count = 0
    while true do
        local digit = _digit_value(string.byte(text, cursor))
        if digit == nil then
            break
        end
        int_value = int_value * 10 + digit
        digit_count = digit_count + 1
        cursor = cursor + 1
    end
    if digit_count == 0 then
        _build_error("invalid number", index)
    end

    local value = int_value
    if string.byte(text, cursor) == _byte_dot then
        cursor = cursor + 1
        local divisor = 1
        local fraction_count = 0
        while true do
            local digit = _digit_value(string.byte(text, cursor))
            if digit == nil then
                break
            end
            value = value * 10 + digit
            divisor = divisor * 10
            fraction_count = fraction_count + 1
            cursor = cursor + 1
        end
        if fraction_count == 0 then
            _build_error("invalid fractional number", index)
        end
        value = value / divisor
    end

    local exponent = 0
    local exp_sign = 1
    local exp_marker = string.byte(text, cursor)
    if exp_marker == _byte_e_lower or exp_marker == _byte_e_upper then
        cursor = cursor + 1
        local exp_byte = string.byte(text, cursor)
        if exp_byte == _byte_minus then
            exp_sign = -1
            cursor = cursor + 1
        elseif exp_byte == _byte_plus then
            cursor = cursor + 1
        end
        local exp_count = 0
        while true do
            local digit = _digit_value(string.byte(text, cursor))
            if digit == nil then
                break
            end
            exponent = exponent * 10 + digit
            exp_count = exp_count + 1
            cursor = cursor + 1
        end
        if exp_count == 0 then
            _build_error("invalid exponent", index)
        end
    end

    value = sign * value
    if exponent ~= 0 then
        value = value * (10 ^ (exp_sign * exponent))
    end
    return value, cursor
end

local function _parse_literal(text, index, literal, value)
    if string.sub(text, index, index + #literal - 1) ~= literal then
        _build_error("invalid literal", index)
    end
    return value, index + #literal
end

local _parse_value

local function _parse_array(text, index)
    local cursor = _skip_whitespace(text, index + 1)
    local values = {}
    if string.byte(text, cursor) == _byte_close_bracket then
        return values, cursor + 1
    end
    while cursor <= #text do
        local value
        value, cursor = _parse_value(text, cursor)
        values[#values + 1] = value
        cursor = _skip_whitespace(text, cursor)
        local byte = string.byte(text, cursor)
        if byte == _byte_close_bracket then
            return values, cursor + 1
        end
        if byte ~= _byte_comma then
            _build_error("expected ',' or ']'", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
    end
    _build_error("unterminated array", index)
end

local function _parse_object(text, index)
    local cursor = _skip_whitespace(text, index + 1)
    local object = {}
    if string.byte(text, cursor) == _byte_close_brace then
        return object, cursor + 1
    end
    while cursor <= #text do
        if string.byte(text, cursor) ~= _byte_quote then
            _build_error("expected string key", cursor)
        end
        local key
        key, cursor = _parse_string(text, cursor)
        cursor = _skip_whitespace(text, cursor)
        if string.byte(text, cursor) ~= _byte_colon then
            _build_error("expected ':' after key", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
        object[key], cursor = _parse_value(text, cursor)
        cursor = _skip_whitespace(text, cursor)
        local byte = string.byte(text, cursor)
        if byte == _byte_close_brace then
            return object, cursor + 1
        end
        if byte ~= _byte_comma then
            _build_error("expected ',' or '}'", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
    end
    _build_error("unterminated object", index)
end

function _parse_value(text, index)
    local cursor = _skip_whitespace(text, index)
    local byte = string.byte(text, cursor)
    if byte == _byte_quote then
        return _parse_string(text, cursor)
    end
    if byte == _byte_open_brace then
        return _parse_object(text, cursor)
    end
    if byte == _byte_open_bracket then
        return _parse_array(text, cursor)
    end
    if byte == _byte_t then
        return _parse_literal(text, cursor, "true", true)
    end
    if byte == _byte_f then
        return _parse_literal(text, cursor, "false", false)
    end
    if byte == _byte_n then
        return _parse_literal(text, cursor, "null", nil)
    end
    if byte == _byte_minus or _digit_value(byte) ~= nil then
        return _parse_number(text, cursor)
    end
    _build_error("unexpected token", cursor)
end

function json_reader.decode(text)
    local raw_text = tostring(text or "")
    local value, cursor = _parse_value(raw_text, 1)
    cursor = _skip_whitespace(raw_text, cursor)
    if cursor <= #raw_text then
        _build_error("trailing content", cursor)
    end
    return value
end

return json_reader
