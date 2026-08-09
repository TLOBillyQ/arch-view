-- luaunit test runner for arch_view (4lua-chain convention, ADR-0005/0006).
-- Run from the repository root:  lua tests/run.lua
-- Discovers tests/test_*.lua (fixture/golden are test data, not suites;
-- bench/compare/gen_golden are tooling), loads each file, and runs the
-- returned luaunit test tables as a single suite.
-- Exit code 0 when every test passes, 1 otherwise.

local script = arg[0] or "tests/run.lua"
local root = script:match("^(.+)/tests/run%.lua$") or "."
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path

-- luaunit comes from luarocks, like the rest of the 4lua chain; make the
-- per-user tree visible so a bare `lua tests/run.lua` works without a
-- wrapper script injecting LUA_PATH.
local luarocks = (os.getenv("HOME") or "") .. "/.luarocks/share/lua/5.4/?.lua"
package.path = package.path .. ";" .. luarocks

local lu = require("luaunit")

local function shell_quote(text)
  return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function discover_test_files()
  local files = {}
  local pipe = io.popen("find " .. shell_quote(root .. "/tests")
    .. " -name 'test_*.lua' -type f"
    .. " -not -path '*/fixture/*'"
    .. " -not -path '*/golden/*' 2>/dev/null")
  for line in pipe:lines() do
    files[#files + 1] = line
  end
  pipe:close()
  table.sort(files)
  return files
end

local function suite_name_for(path)
  local base = tostring(path):match("([^/]+)%.lua$") or tostring(path)
  return (base:gsub("[^%w_]", "_"))
end

local instances = {}
for _, file in ipairs(discover_test_files()) do
  local chunk, load_err = loadfile(file)
  if chunk == nil then
    io.stderr:write("cannot load test file " .. file .. ": " .. tostring(load_err) .. "\n")
    os.exit(1)
  end
  local ok, suite = pcall(chunk)
  if not ok then
    io.stderr:write("test file " .. file .. " failed to load: " .. tostring(suite) .. "\n")
    os.exit(1)
  end
  if type(suite) ~= "table" then
    io.stderr:write("test file " .. file .. " must return a luaunit test table\n")
    os.exit(1)
  end
  instances[#instances + 1] = { suite_name_for(file), suite }
end

local runner = lu.LuaUnit.new()
os.exit(runner:runSuiteByInstancesNoCmdLineParsing(instances) > 0 and 1 or 0)
