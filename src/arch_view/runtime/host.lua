local common = {}

local _tointeger = math and math.tointeger
local _numeric_type_names = {
  number = true,
  integer = true,
  fixed = true,
}

local function _is_numeric_type_name(value_type)
  return _numeric_type_names[value_type] == true
end

local function _to_integer_safe(value)
  if value == nil then
    return nil
  end
  if _tointeger then
    local ok, as_int = pcall(_tointeger, value)
    if ok and as_int ~= nil then
      return as_int
    end
  end
  if math and math.floor then
    local ok, floored = pcall(math.floor, value)
    if ok and floored ~= nil then
      return floored
    end
  end
  return nil
end

local function _parse_integer_string(value)
  if value == nil then
    return nil
  end
  if not string.match(value, "^-?%d+$") then
    return nil
  end
  local len = #value
  if len == 0 then
    return nil
  end
  local index = 1
  local sign = 1
  if string.sub(value, 1, 1) == "-" then
    sign = -1
    index = 2
    if index > len then
      return nil
    end
  end
  local num = 0
  for cursor = index, len do
    local byte = string.byte(value, cursor)
    local digit = byte - 48
    if digit < 0 or digit > 9 then
      return nil
    end
    num = num * 10 + digit
  end
  if _tointeger then
    return _tointeger(sign * num)
  end
  return sign * num
end


local _temp_counter = 0
local _base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function _entropy_token()
  local pointer = tostring({}):gsub("[^%w]+", "")
  if pointer == "" then
    pointer = "ptr"
  end
  _temp_counter = _temp_counter + 1
  return table.concat({
    tostring(os.time()),
    tostring(_temp_counter),
    pointer,
  }, "_")
end

local function _os_execute_success(ok, _, code)
  if ok == true and (code == nil or (_to_integer_safe(code) ~= nil and code == 0)) then
    return true, code or 0
  end
  if _to_integer_safe(code) ~= nil and code == 0 then
    return true, 0
  end
  return false, code or 1
end

local function _read_raw_file(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function _write_raw_file(path, content, mode)
  local file = io.open(path, mode or "wb")
  if file == nil then
    return nil
  end
  file:write(content)
  file:close()
  return true
end

local function _raw_file_exists(path)
  local file = io.open(path, "rb")
  if file == nil then
    return false
  end
  file:close()
  return true
end

-- 纯 Lua 目录探测：POSIX 上打开 "<dir>/." 仅当路径解析为已存在目录时成功，
-- 普通文件失败（ENOTDIR），符号链接按其目标处理，与 test -d 的语义一致。
local function _raw_dir_exists(path)
  if path == "" then
    return false
  end
  local probe = path:gsub("/+$", "") .. "/."
  local file = io.open(probe, "rb")
  if file == nil then
    return false
  end
  file:close()
  return true
end

local function _base64_encode(text)
  local source = tostring(text or "")
  local parts = {}
  local index = 1

  while index <= #source do
    local a = source:byte(index) or 0
    local b = source:byte(index + 1) or 0
    local c = source:byte(index + 2) or 0
    local chunk = a * 65536 + b * 256 + c

    local first = math.floor(chunk / 262144) % 64 + 1
    local second = math.floor(chunk / 4096) % 64 + 1
    local third = math.floor(chunk / 64) % 64 + 1
    local fourth = chunk % 64 + 1

    parts[#parts + 1] = _base64_alphabet:sub(first, first)
    parts[#parts + 1] = _base64_alphabet:sub(second, second)

    if index + 1 <= #source then
      parts[#parts + 1] = _base64_alphabet:sub(third, third)
    else
      parts[#parts + 1] = "="
    end

    if index + 2 <= #source then
      parts[#parts + 1] = _base64_alphabet:sub(fourth, fourth)
    else
      parts[#parts + 1] = "="
    end

    index = index + 3
  end

  return table.concat(parts)
end

local function _utf16le_encode(text)
  local source = tostring(text or "")
  local parts = {}
  local index = 1

  while index <= #source do
    local ok, codepoint = pcall(utf8.codepoint, source, index)
    if not ok or codepoint == nil then
      local byte = source:byte(index) or 0
      parts[#parts + 1] = string.char(byte, 0)
      index = index + 1
    else
      local next_index = utf8.offset(source, 2, index) or (#source + 1)
      if codepoint <= 0xFFFF then
        local low = codepoint % 256
        local high = math.floor(codepoint / 256)
        parts[#parts + 1] = string.char(low, high)
      else
        local value = codepoint - 0x10000
        local high_surrogate = 0xD800 + math.floor(value / 0x400)
        local low_surrogate = 0xDC00 + (value % 0x400)
        parts[#parts + 1] = string.char(high_surrogate % 256, math.floor(high_surrogate / 256))
        parts[#parts + 1] = string.char(low_surrogate % 256, math.floor(low_surrogate / 256))
      end
      index = next_index
    end
  end

  return table.concat(parts)
end

local function _powershell_literal(value)
  local text = tostring(value or "")
  return "'" .. text:gsub("'", "''") .. "'"
end

local function _windows_powershell_command(script)
  local wrapped_script = table.concat({
    "$ProgressPreference = 'SilentlyContinue'",
    "$WarningPreference = 'SilentlyContinue'",
    "$ErrorActionPreference = 'Stop'",
    tostring(script or ""),
  }, "\n")
  local encoded = _base64_encode(_utf16le_encode(wrapped_script))
  return "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " .. encoded
end

local function _windows_execute_powershell(script)
  return os.execute(_windows_powershell_command(script))
end

local function _windows_path(path)
  return tostring(path or ""):gsub("/", "\\")
end

local function _windows_copy_bytes(source_path, target_path, opts)
  local mode = opts and opts.mode or "write"
  local script = {
    "$source = " .. _powershell_literal(_windows_path(source_path)),
    "$target = " .. _powershell_literal(_windows_path(target_path)),
    "$parent = [System.IO.Path]::GetDirectoryName($target)",
    "try {",
    "  if ($parent -and $parent -ne '') {",
    "    [System.IO.Directory]::CreateDirectory($parent) | Out-Null",
    "  }",
    "  $bytes = [System.IO.File]::ReadAllBytes($source)",
  }

  if mode == "append" then
    script[#script + 1] = "  $stream = [System.IO.File]::Open($target, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)"
    script[#script + 1] = "  try {"
    script[#script + 1] = "    [void]$stream.Seek(0, [System.IO.SeekOrigin]::End)"
    script[#script + 1] = "    $stream.Write($bytes, 0, $bytes.Length)"
    script[#script + 1] = "  } finally {"
    script[#script + 1] = "    $stream.Dispose()"
    script[#script + 1] = "  }"
  else
    script[#script + 1] = "  [System.IO.File]::WriteAllBytes($target, $bytes)"
  end

  script[#script + 1] = "  exit 0"
  script[#script + 1] = "} catch {"
  script[#script + 1] = "  [Console]::Error.WriteLine($_.Exception.Message)"
  script[#script + 1] = "  exit 1"
  script[#script + 1] = "}"

  return _windows_execute_powershell(table.concat(script, "\n"))
end

local function _windows_process_quote(value)
  local text = tostring(value or "")
  if text == "" then
    return '""'
  end
  if text:find('[ \t\n\v"]') == nil then
    return text
  end

  local parts = { '"' }
  local backslashes = 0

  for index = 1, #text do
    local ch = text:sub(index, index)
    if ch == "\\" then
      backslashes = backslashes + 1
    elseif ch == '"' then
      parts[#parts + 1] = string.rep("\\", backslashes * 2 + 1)
      parts[#parts + 1] = '"'
      backslashes = 0
    else
      if backslashes > 0 then
        parts[#parts + 1] = string.rep("\\", backslashes)
        backslashes = 0
      end
      parts[#parts + 1] = ch
    end
  end

  if backslashes > 0 then
    parts[#parts + 1] = string.rep("\\", backslashes * 2)
  end
  parts[#parts + 1] = '"'

  return table.concat(parts)
end

local function _windows_argument_text(args)
  local parts = {}
  for index = 2, #(args or {}) do
    parts[#parts + 1] = _windows_process_quote(args[index])
  end
  return table.concat(parts, " ")
end

local function _windows_known_command_dirs()
  local dirs = {}

  local function _push(path)
    local normalized = common.normalize_path(path)
    if normalized ~= "" then
      dirs[#dirs + 1] = normalized
    end
  end

  for entry in tostring(os.getenv("PATH") or ""):gmatch("[^;]+") do
    _push(entry)
  end

  return dirs
end

local function _windows_resolve_command_path(name)
  local command_name = tostring(name or "")
  if command_name == "" then
    return nil
  end

  if command_name:find("[/\\]") ~= nil or command_name:match("^%a:") ~= nil then
    if _raw_file_exists(command_name) then
      return common.normalize_path(command_name)
    end
    return nil
  end

  local candidates = {}
  if command_name:match("%.[^./\\]+$") ~= nil then
    candidates[1] = command_name
  else
    candidates[1] = command_name .. ".exe"
    candidates[2] = command_name .. ".cmd"
    candidates[3] = command_name .. ".bat"
    candidates[4] = command_name
  end

  for _, dir in ipairs(_windows_known_command_dirs()) do
    for _, candidate in ipairs(candidates) do
      local full_path = common.join_path(dir, candidate)
      if _raw_file_exists(full_path) then
        return common.normalize_path(full_path)
      end
    end
  end

  return nil
end

function common.bilingual(zh, en)
  return tostring(zh or "") .. " / " .. tostring(en or "")
end

function common.sorted_pairs(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local index = 0
  return function()
    index = index + 1
    local key = keys[index]
    if key == nil then
      return nil
    end
    return key, map[key]
  end
end

function common.sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

-- package.config 在进程内不变，加载时求值一次即可。
local _is_windows_host = package.config:sub(1, 1) == "\\"

function common.is_windows()
  return _is_windows_host
end

-- uname 结果在进程内不变，首次调用后缓存，避免重复 popen。
local _cached_is_macos = nil

function common.is_macos()
  if _cached_is_macos ~= nil then
    return _cached_is_macos
  end
  if common.is_windows() then
    _cached_is_macos = false
    return _cached_is_macos
  end
  local process = io.popen("uname")
  if process == nil then
    _cached_is_macos = false
    return _cached_is_macos
  end
  local content = process:read("*l") or ""
  process:close()
  _cached_is_macos = common.normalize_path(content) == "Darwin"
  return _cached_is_macos
end

function common.normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

function common.split(text, delimiter)
  local parts = {}
  local source = tostring(text or "")
  if source == "" then
    return parts
  end
  local start_index = 1
  while true do
    local hit_start, hit_end = string.find(source, delimiter, start_index, true)
    if hit_start == nil then
      parts[#parts + 1] = string.sub(source, start_index)
      break
    end
    parts[#parts + 1] = string.sub(source, start_index, hit_start - 1)
    start_index = hit_end + 1
  end
  return parts
end

function common.join(parts, delimiter)
  return table.concat(parts or {}, delimiter or "")
end

function common.simplify_path(path)
  local normalized = common.normalize_path(path)
  local prefix = ""
  local remainder = normalized

  if normalized:match("^%a:/") then
    prefix = normalized:sub(1, 2)
    remainder = normalized:sub(4)
  elseif normalized:sub(1, 1) == "/" then
    prefix = "/"
    remainder = normalized:sub(2)
  end

  local parts = {}
  for _, segment in ipairs(common.split(remainder, "/")) do
    if segment ~= "" and segment ~= "." then
      if segment == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then
          parts[#parts] = nil
        elseif prefix == "" then
          parts[#parts + 1] = segment
        end
      else
        parts[#parts + 1] = segment
      end
    end
  end

  local simplified = table.concat(parts, "/")
  if prefix == "" then
    return simplified
  end
  if simplified == "" then
    if prefix == "/" then
      return "/"
    end
    return prefix .. "/"
  end
  if prefix == "/" then
    return "/" .. simplified
  end
  return prefix .. "/" .. simplified
end

-- 纯 Lua 进程无法切换工作目录，cwd 在进程内不变，首次解析后缓存，
-- 避免每次 analyze 重复 popen pwd。各分支返回值与原实现逐字节一致。
local _cached_current_dir = nil

function common.current_dir()
  if _cached_current_dir ~= nil then
    return _cached_current_dir
  end

  local resolved = nil
  if common.is_windows() then
    local env_path = os.getenv("CD") or os.getenv("PWD")
    if env_path ~= nil and env_path ~= "" then
      resolved = common.normalize_path(env_path)
    else
      local process = io.popen("cd")
      if process ~= nil then
        local path = process:read("*l") or "."
        process:close()
        resolved = common.normalize_path(path)
      else
        resolved = "."
      end
    end
  else
    local process = io.popen("pwd")
    if process == nil then
      resolved = "."
    else
      local path = process:read("*l") or "."
      process:close()
      resolved = common.normalize_path(path)
    end
  end

  _cached_current_dir = resolved
  return resolved
end

function common.is_absolute_path(path)
  local normalized = common.normalize_path(path)
  if normalized:match("^%a:/") then
    return true
  end
  return normalized:sub(1, 1) == "/"
end

function common.join_path(base, child)
  local normalized_base = common.normalize_path(base)
  local normalized_child = common.normalize_path(child)
  if normalized_base == "" then
    return normalized_child
  end
  if normalized_child == "" then
    return normalized_base
  end
  return normalized_base:gsub("/+$", "") .. "/" .. normalized_child:gsub("^/+", "")
end

function common.resolve_path(base, path)
  local normalized_path = common.normalize_path(path)
  if normalized_path == "" then
    return common.simplify_path(base)
  end
  if common.is_windows() and normalized_path:sub(1, 1) == "/" then
    if normalized_path:match("^/[A-Za-z]/") then
      return common.simplify_path(normalized_path:sub(2, 2) .. ":" .. normalized_path:sub(3))
    end
    local tmpdir = common.system_tmp_dir()
    if normalized_path == "/tmp" or normalized_path:match("^/tmp/") then
      local suffix = normalized_path:sub(5)
      return common.simplify_path(common.join_path(tmpdir, suffix))
    end
  end
  if common.is_absolute_path(normalized_path) then
    return common.simplify_path(normalized_path)
  end
  return common.simplify_path(common.join_path(base or "", normalized_path))
end

function common.parent_dir(path)
  local normalized = common.normalize_path(path)
  return normalized:match("^(.*)/[^/]+$")
end

function common.system_tmp_dir()
  local env = nil
  if common.is_windows() then
    env = os.getenv("TEMP") or os.getenv("TMP")
  else
    env = os.getenv("TMPDIR")
  end
  if env == nil or env == "" then
    if common.is_windows() then
      env = "C:/Windows/Temp"
    else
      env = "/tmp"
    end
  end
  return common.normalize_path(env)
end

function common.is_numeric(value)
  local value_type = type(value)
  if value_type == "nil" then
    return false
  end
  if _is_numeric_type_name(value_type) then
    return true
  end
  if value_type == "string" then
    return false
  end
  return _to_integer_safe(value) ~= nil
end

function common.to_integer(value)
  local value_type = type(value)
  if value_type == "string" then
    local parsed = _parse_integer_string(value)
    if parsed ~= nil then
      return parsed
    end
    return nil
  end
  if common.is_numeric(value) then
    local parsed = _to_integer_safe(value)
    if parsed ~= nil then
      return parsed
    end
  end
  if value ~= nil then
    local ok, as_text = pcall(tostring, value)
    if ok and type(as_text) == "string" then
      local parsed = _parse_integer_string(as_text)
      if parsed ~= nil then
        return parsed
      end
    end
  end
  return nil
end

function common.shell_quote(value)
  local text = tostring(value or "")
  if common.is_windows() then
    return '"' .. text:gsub('"', '""') .. '"'
  end
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function common.build_command(args)
  local parts = {}
  for index, value in ipairs(args or {}) do
    local resolved = value
    if common.is_windows() then
      if index == 1 then
        resolved = _windows_path(_windows_resolve_command_path(value) or value)
      end
      parts[#parts + 1] = _windows_process_quote(resolved)
    else
      parts[#parts + 1] = common.shell_quote(resolved)
    end
  end
  return table.concat(parts, " ")
end

function common.build_open_command(path)
  local normalized = common.normalize_path(path)
  if common.is_windows() then
    return 'start "" ' .. common.shell_quote(_windows_path(normalized))
  end
  if common.is_macos() then
    return common.build_command({ "open", normalized })
  end
  return common.build_command({ "xdg-open", normalized })
end

function common.make_temp_path(prefix, suffix)
  local base_dir = common.join_path(common.system_tmp_dir(), "arch_view")
  common.ensure_dir(base_dir)
  local name = table.concat({
    tostring(prefix or "tmp"),
    _entropy_token(),
  }, "_")
  return common.join_path(base_dir, name .. tostring(suffix or ""))
end

function common.command_exists(name)
  local command_name = tostring(name or "")
  if command_name == "" then
    return false
  end

  if common.is_windows() then
    if _windows_resolve_command_path(command_name) ~= nil then
      return true
    end
    local command = "where.exe " .. common.shell_quote(command_name) .. " >nul 2>nul"
    local ok, kind, code = os.execute(command)
    return _os_execute_success(ok, kind, code)
  end

  local command = "command -v " .. common.shell_quote(command_name) .. " >/dev/null 2>&1"
  local ok, kind, code = os.execute(command)
  return _os_execute_success(ok, kind, code)
end

function common.read_file(path)
  local normalized = common.normalize_path(path)
  local content = _read_raw_file(normalized)
  if content ~= nil then
    return content
  end
  if not common.is_windows() then
    return nil, common.bilingual(
      "无法打开文件: " .. tostring(path),
      "Cannot open file: " .. tostring(path)
    )
  end

  local output_path = common.make_temp_path("read_file", ".txt")
  local ok, kind, code = _windows_copy_bytes(normalized, output_path, { mode = "write" })
  local success = _os_execute_success(ok, kind, code)
  if not success then
    common.remove_path(output_path)
    return nil, common.bilingual(
      "无法打开文件: " .. tostring(path),
      "Cannot open file: " .. tostring(path)
    )
  end

  local content = _read_raw_file(output_path)
  common.remove_path(output_path)
  if content == nil then
    return nil, common.bilingual(
      "无法读取临时输出: " .. tostring(path),
      "Cannot read temporary output: " .. tostring(path)
    )
  end
  return content
end

function common.ensure_dir(path)
  if path == nil or path == "" then
    return true
  end

  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    -- 目录已存在时 mkdir -p 本就静默成功，纯 Lua 探测命中即可直接返回；
    -- 探测失败（不存在、或同名普通文件等）一律走原 mkdir -p，错误消息不变。
    if _raw_dir_exists(normalized) then
      return true
    end
    local command = "mkdir -p " .. common.shell_quote(normalized)
    local ok, kind, code = os.execute(command)
    local success = _os_execute_success(ok, kind, code)
    if not success then
      return nil, common.bilingual(
        "创建目录失败: " .. tostring(path),
        "Failed to create directory: " .. tostring(path)
      )
    end
    return true
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "try {",
    "  [void](New-Item -ItemType Directory -Force -Path $path)",
    "  exit 0",
    "} catch {",
    "  exit 1",
    "}",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  local success = _os_execute_success(ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "创建目录失败: " .. tostring(path),
      "Failed to create directory: " .. tostring(path)
    )
  end
  return true
end

function common.ensure_parent_dir(path)
  return common.ensure_dir(common.parent_dir(path))
end

function common.write_file(path, content)
  local ok, err = common.ensure_parent_dir(path)
  if not ok then
    return nil, err
  end

  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    local write_ok = _write_raw_file(normalized, tostring(content or ""), "wb")
    if write_ok == nil then
      return nil, common.bilingual(
        "无法写入文件: " .. tostring(path),
        "Cannot write file: " .. tostring(path)
      )
    end
    return true
  end

  local temp_path = common.make_temp_path("write_file", ".txt")
  local wrote_temp = _write_raw_file(temp_path, tostring(content or ""), "wb")
  if wrote_temp == nil then
    return nil, common.bilingual(
      "无法写入临时文件: " .. tostring(temp_path),
      "Cannot write temporary file: " .. tostring(temp_path)
    )
  end

  local exec_ok, kind, code = _windows_copy_bytes(temp_path, normalized, { mode = "write" })
  common.remove_path(temp_path)
  local success = _os_execute_success(exec_ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "无法写入文件: " .. tostring(path),
      "Cannot write file: " .. tostring(path)
    )
  end
  return true
end

function common.append_file(path, content)
  local ok, err = common.ensure_parent_dir(path)
  if not ok then
    return nil, err
  end

  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    local write_ok = _write_raw_file(normalized, tostring(content or ""), "ab")
    if write_ok == nil then
      return nil, common.bilingual(
        "无法追加文件: " .. tostring(path),
        "Cannot append file: " .. tostring(path)
      )
    end
    return true
  end

  local temp_path = common.make_temp_path("append_file", ".txt")
  local wrote_temp = _write_raw_file(temp_path, tostring(content or ""), "wb")
  if wrote_temp == nil then
    return nil, common.bilingual(
      "无法写入临时文件: " .. tostring(temp_path),
      "Cannot write temporary file: " .. tostring(temp_path)
    )
  end

  local exec_ok, kind, code = _windows_copy_bytes(temp_path, normalized, { mode = "append" })
  common.remove_path(temp_path)
  local success = _os_execute_success(exec_ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "无法追加文件: " .. tostring(path),
      "Cannot append file: " .. tostring(path)
    )
  end
  return true
end

function common.path_exists(path)
  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    -- POSIX 上 io.open 对文件与目录都能打开，可作存在性探测；
    -- 仅在无法确定时（如无读权限 EACCES）回退原 test -e 子进程，语义不变。
    local probe_file, _, probe_errno = io.open(normalized, "rb")
    if probe_file ~= nil then
      probe_file:close()
      return true
    end
    if probe_errno == 2 then
      return false
    end
    local command = "[ -e " .. common.shell_quote(normalized) .. " ]"
    local ok, kind, code = os.execute(command)
    return _os_execute_success(ok, kind, code)
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "if ((Test-Path -LiteralPath $path -PathType Leaf) -or (Test-Path -LiteralPath $path -PathType Container)) {",
    "  exit 0",
    "}",
    "exit 1",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  return _os_execute_success(ok, kind, code)
end

function common.path_mtime(path)
  local normalized = common.normalize_path(path)
  if not common.path_exists(normalized) then
    return nil
  end

  if not common.is_windows() then
    local command = nil
    if common.is_macos() then
      command = { "stat", "-f", "%m", normalized }
    else
      command = { "stat", "-c", "%Y", normalized }
    end
    local result = common.run_command(command)
    if not result.ok then
      return nil
    end
    return common.to_integer((result.output or ""):match("^%s*(.-)%s*$"))
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "$item = Get-Item -LiteralPath $path",
    "$epoch = [DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()",
    "Write-Output $epoch",
  }, "\n")
  local result = common.run_command(_windows_powershell_command(script))
  if not result.ok then
    return nil
  end
  return common.to_integer((result.output or ""):match("^%s*(.-)%s*$"))
end

function common.is_dir(path)
  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    -- 探测命中即可确定为目录；不命中（文件、不存在、无权限等）回退原 test -d。
    if _raw_dir_exists(normalized) then
      return true
    end
    local command = "[ -d " .. common.shell_quote(normalized) .. " ]"
    local ok, kind, code = os.execute(command)
    return _os_execute_success(ok, kind, code)
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "if (Test-Path -LiteralPath $path -PathType Container) {",
    "  exit 0",
    "}",
    "exit 1",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  return _os_execute_success(ok, kind, code)
end

function common.remove_path(path)
  if not common.path_exists(path) then
    return true
  end

  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    -- 普通文件/符号链接用 os.remove 等价于 rm -rf（同为 unlink），省去子进程；
    -- 目录或 os.remove 失败时走原 rm -rf，行为与错误消息不变。
    if not _raw_dir_exists(normalized) then
      local removed = os.remove(normalized)
      if removed then
        return true
      end
    end
    local command = "rm -rf " .. common.shell_quote(normalized)
    local ok, kind, code = os.execute(command)
    local success = _os_execute_success(ok, kind, code)
    if not success then
      return nil, common.bilingual(
        "删除路径失败: " .. tostring(path),
        "Failed to remove path: " .. tostring(path)
      )
    end
    return true
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "try {",
    "  if (Test-Path -LiteralPath $path) {",
    "    Remove-Item -LiteralPath $path -Recurse -Force",
    "  }",
    "  exit 0",
    "} catch {",
    "  exit 1",
    "}",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  local success = _os_execute_success(ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "删除路径失败: " .. tostring(path),
      "Failed to remove path: " .. tostring(path)
    )
  end
  return true
end

function common.copy_file(source_path, target_path)
  local ok, err = common.ensure_parent_dir(target_path)
  if not ok then
    return nil, err
  end
  local source_text, read_err = common.read_file(source_path)
  if source_text == nil then
    return nil, read_err
  end
  return common.write_file(target_path, source_text)
end

function common.copy_tree(source_path, target_path)
  local normalized_source = common.normalize_path(source_path)
  local normalized_target = common.normalize_path(target_path)
  local removed, remove_err = common.remove_path(normalized_target)
  if not removed then
    return nil, remove_err
  end

  local ok, err = common.ensure_parent_dir(normalized_target)
  if not ok then
    return nil, err
  end

  if not common.is_windows() then
    local command = "cp -R " .. common.shell_quote(normalized_source) .. " " .. common.shell_quote(normalized_target)
    local exec_ok, kind, code = os.execute(command)
    local success, exit_code = _os_execute_success(exec_ok, kind, code)
    if not success then
      return nil, common.bilingual(
        "目录拷贝失败，退出码: " .. tostring(exit_code),
        "Copy tree failed with exit code: " .. tostring(exit_code)
      )
    end
    return true
  end

  local script = table.concat({
    "$source = " .. _powershell_literal(_windows_path(normalized_source)),
    "$target = " .. _powershell_literal(_windows_path(normalized_target)),
    "try {",
    "  Copy-Item -LiteralPath $source -Destination $target -Recurse -Force",
    "  exit 0",
    "} catch {",
    "  exit 1",
    "}",
  }, "\n")
  local exec_ok, kind, code = _windows_execute_powershell(script)
  local success = _os_execute_success(exec_ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "目录拷贝失败: " .. tostring(source_path),
      "Copy tree failed: " .. tostring(source_path)
    )
  end
  return true
end

function common.wrap_command_with_cwd(command, cwd)
  local cwd_path = cwd and common.normalize_path(cwd) or nil
  if cwd_path == nil or cwd_path == "" then
    return tostring(command or "")
  end
  if common.is_windows() then
    return "cd /d " .. common.shell_quote(_windows_path(cwd_path)) .. " && " .. tostring(command or "")
  end
  return "cd " .. common.shell_quote(cwd_path) .. " && " .. tostring(command or "")
end

function common.run_command(command, options)
  local args = command
  if type(command) == "string" then
    if common.is_windows() then
      args = { "cmd.exe", "/d", "/s", "/c", tostring(command) }
    else
      args = { "sh", "-lc", tostring(command) }
    end
  end

  if type(args) ~= "table" or #args == 0 then
    return {
      ok = false,
      code = 1,
      output = common.bilingual("命令参数无效", "Invalid command arguments"),
    }
  end

  local output_path = common.make_temp_path("command_output", ".log")
  local cwd_path = options and options.cwd and common.normalize_path(options.cwd) or nil
  local stdin_path = options and options.stdin_path and common.normalize_path(options.stdin_path) or nil

  if common.is_windows() then
    local resolved_args = {}
    for index, value in ipairs(args) do
      if index == 1 then
        resolved_args[index] = _windows_resolve_command_path(value) or value
      else
        resolved_args[index] = value
      end
    end

    local script_lines = {
      "$exe = " .. _powershell_literal(_windows_path(resolved_args[1])),
      "$out = " .. _powershell_literal(_windows_path(output_path)),
      "$cwd = " .. _powershell_literal(_windows_path(cwd_path or common.current_dir())),
      "$stdin = " .. _powershell_literal(_windows_path(stdin_path or "")),
      "$argList = New-Object System.Collections.Generic.List[string]",
    }
    for index = 2, #resolved_args do
      script_lines[#script_lines + 1] = "$argList.Add(" .. _powershell_literal(tostring(resolved_args[index])) .. ") | Out-Null"
    end
    script_lines[#script_lines + 1] = "$pushed = $false"
    script_lines[#script_lines + 1] = "try {"
    script_lines[#script_lines + 1] = "  Push-Location -LiteralPath $cwd"
    script_lines[#script_lines + 1] = "  $pushed = $true"
    script_lines[#script_lines + 1] = "  if ($stdin -ne '') {"
    script_lines[#script_lines + 1] = "    $content = [System.IO.File]::ReadAllText($stdin, [System.Text.UTF8Encoding]::new($false))"
    script_lines[#script_lines + 1] = "    $output = $content | & $exe @($argList.ToArray()) 2>&1 | Out-String"
    script_lines[#script_lines + 1] = "  } else {"
    script_lines[#script_lines + 1] = "    $output = & $exe @($argList.ToArray()) 2>&1 | Out-String"
    script_lines[#script_lines + 1] = "  }"
    script_lines[#script_lines + 1] = "  $exitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }"
    script_lines[#script_lines + 1] = "  [System.IO.File]::WriteAllText($out, $output, [System.Text.UTF8Encoding]::new($false))"
    script_lines[#script_lines + 1] = "  exit $exitCode"
    script_lines[#script_lines + 1] = "} catch {"
    script_lines[#script_lines + 1] = "  [System.IO.File]::WriteAllText($out, $_.Exception.ToString(), [System.Text.UTF8Encoding]::new($false))"
    script_lines[#script_lines + 1] = "  exit 1"
    script_lines[#script_lines + 1] = "} finally {"
    script_lines[#script_lines + 1] = "  if ($pushed) {"
    script_lines[#script_lines + 1] = "    Pop-Location"
    script_lines[#script_lines + 1] = "  }"
    script_lines[#script_lines + 1] = "}"
    local script = table.concat(script_lines, "\n")
    local ok, kind, code = _windows_execute_powershell(script)
    local success, exit_code = _os_execute_success(ok, kind, code)
    local output = _read_raw_file(output_path) or ""
    common.remove_path(output_path)
    return {
      ok = success,
      code = exit_code,
      output = output,
    }
  end

  local command_text = common.build_command(args)
  local wrapped = common.wrap_command_with_cwd(command_text, cwd_path)
  local redirected = wrapped
  if stdin_path ~= nil and stdin_path ~= "" then
    redirected = redirected .. " < " .. common.shell_quote(stdin_path)
  end
  redirected = redirected .. " > " .. common.shell_quote(output_path) .. " 2>&1"
  local ok, kind, code = os.execute(redirected)
  local success, exit_code = _os_execute_success(ok, kind, code)
  local output = _read_raw_file(output_path) or ""
  common.remove_path(output_path)
  return {
    ok = success,
    code = exit_code,
    output = output,
  }
end

function common.collect_files(root, extension)
  local normalized_root = common.normalize_path(root)
  local normalized_extension = tostring(extension or "")
  if normalized_extension ~= "" and normalized_extension:sub(1, 1) ~= "." then
    normalized_extension = "." .. normalized_extension
  end

  if not common.path_exists(normalized_root) then
    return nil, common.bilingual(
      "目录不存在: " .. tostring(root),
      "Directory does not exist: " .. tostring(root)
    )
  end

  if not common.is_windows() then
    local command = {
      "find",
      normalized_root,
      "-type",
      "f",
    }
    if normalized_extension ~= "" then
      command[#command + 1] = "-name"
      command[#command + 1] = "*" .. normalized_extension
    end
    local result = common.run_command(command)
    if not result.ok then
      return nil, common.bilingual(
        "收集文件失败: " .. tostring(root),
        "Failed to collect files: " .. tostring(root)
      )
    end

    local files = {}
    for line in (result.output .. "\n"):gmatch("(.-)\n") do
      if line ~= "" then
        files[#files + 1] = common.normalize_path(line)
      end
    end
    table.sort(files)
    return files
  end

  local output_path = common.make_temp_path("collect_files", ".txt")
  local script = table.concat({
    "$root = " .. _powershell_literal(_windows_path(normalized_root)),
    "$out = " .. _powershell_literal(_windows_path(output_path)),
    "$extension = " .. _powershell_literal(normalized_extension:lower()),
    "try {",
    "  $files = Get-ChildItem -LiteralPath $root -Recurse -File",
    "  if ($extension -ne '') {",
    "    $files = $files | Where-Object { $_.Extension.ToLowerInvariant() -eq $extension }",
    "  }",
    "  $lines = @()",
    "  foreach ($file in $files) {",
    "    $lines += $file.FullName",
    "  }",
    "  [System.IO.File]::WriteAllLines($out, $lines, [System.Text.UTF8Encoding]::new($false))",
    "  exit 0",
    "} catch {",
    "  exit 1",
    "}",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  local success = _os_execute_success(ok, kind, code)
  if not success then
    common.remove_path(output_path)
    return nil, common.bilingual(
      "收集文件失败: " .. tostring(root),
      "Failed to collect files: " .. tostring(root)
    )
  end

  local content = _read_raw_file(output_path) or ""
  common.remove_path(output_path)
  local files = {}
  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    if line ~= "" then
      files[#files + 1] = common.normalize_path(line)
    end
  end
  table.sort(files)
  return files
end

function common.collect_lua_files(root)
  return common.collect_files(root, ".lua")
end

function common.open_path(path)
  local normalized = common.normalize_path(path)
  if not common.is_windows() then
    local result = common.run_command(common.build_open_command(normalized))
    if not result.ok then
      return nil, common.bilingual(
        "打开路径失败: " .. tostring(path),
        "Failed to open path: " .. tostring(path)
      )
    end
    return true
  end

  local script = table.concat({
    "$path = " .. _powershell_literal(_windows_path(normalized)),
    "try {",
    "  Start-Process -FilePath $path",
    "  exit 0",
    "} catch {",
    "  exit 1",
    "}",
  }, "\n")
  local ok, kind, code = _windows_execute_powershell(script)
  local success = _os_execute_success(ok, kind, code)
  if not success then
    return nil, common.bilingual(
      "打开路径失败: " .. tostring(path),
      "Failed to open path: " .. tostring(path)
    )
  end
  return true
end

return common
