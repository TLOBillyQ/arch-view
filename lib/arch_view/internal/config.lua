local common = require("arch_view.runtime.common")
local fs = require("arch_view.runtime.fs")
local json_reader = require("arch_view.runtime.json_reader")

local config = {}

local function _text(zh, en)
    return common.bilingual(zh, en)
end

local function _validate_array(field_name, values, item_is_valid, item_error)
    if values == nil then
        return true
    end
    if type(values) ~= "table" then
        return nil, field_name .. " must be an array"
    end
    for index, value in ipairs(values) do
        if not item_is_valid(value) then
            return nil, field_name .. "[" .. tostring(index) .. "] " .. item_error
        end
    end
    return true
end

local function _assert_array_of_strings(field_name, values)
    return _validate_array(field_name, values, function(value)
        return type(value) == "string" and value ~= ""
    end, "must be a non-empty string")
end

local function _validate_rule_list(field_name, rules)
    return _validate_array(field_name, rules, function(value)
        return type(value) == "table"
    end, "must be a table")
end

local function _validate_config_shape(loaded)
    if type(loaded) ~= "table" then
        return nil, _text(
            "架构配置无效: 配置必须是对象",
            "Invalid architecture config: config must be an object"
        )
    end

    local ok, err = _assert_array_of_strings("source_roots", loaded.source_roots or {})
    if not ok then
        return nil, err
    end

    for _, field_name in ipairs({ "component_rules", "abstract_rules", "forbidden_dependency_rules" }) do
        ok, err = _validate_rule_list(field_name, loaded[field_name])
        if not ok then
            return nil, err
        end
    end

    return true
end

function config.default_path(project_root)
    return fs.join_path(project_root, "arch_view.config.json")
end

function config.load(path)
    local content, err = fs.read_file(path)
    if content == nil then
        return nil, err
    end

    local ok, loaded = pcall(json_reader.decode, content)
    if not ok then
        return nil, _text(
            "架构配置不是有效 JSON: " .. tostring(path),
            "Architecture config is not valid JSON: " .. tostring(path)
        )
    end

    local valid, validate_err = _validate_config_shape(loaded)
    if not valid then
        return nil, validate_err
    end

    return loaded
end

function config.resolve(opts)
    opts = opts or {}
    local cwd = fs.current_dir()
    local project_root = fs.resolve_path(cwd, opts.project_root or cwd)
    local resolved_config_path = opts.config_path and fs.resolve_path(cwd, opts.config_path) or nil

    if opts.config ~= nil then
        local ok, err = _validate_config_shape(opts.config)
        if not ok then
            return nil, err
        end
        return {
            project_root = project_root,
            config = opts.config,
            config_path = resolved_config_path,
        }
    end

    local config_path = resolved_config_path or config.default_path(project_root)

    if not fs.path_exists(config_path) then
        return nil, _text(
            "未找到架构配置: " .. tostring(config_path),
            "Missing architecture config: " .. tostring(config_path)
        )
    end

    local loaded, err = config.load(config_path)
    if loaded == nil then
        return nil, err
    end

    return {
        project_root = project_root,
        config = loaded,
        config_path = config_path,
    }
end

return config
