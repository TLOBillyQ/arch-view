-- Minimal dependency-free unit test runner for arch_view (no busted).
-- Each suite file returns a table; every entry named test_* is one test.
-- Run from the repository root:  lua tests/run.lua
-- Exit code 0 when every test passes, 1 otherwise.

local helpers = dofile("tests/helpers.lua")
helpers.setup()

local suites = {
  "tests/test_api.lua",
  "tests/test_cli.lua",
  "tests/test_layout.lua",
}

local failures = {}
local total = 0

for _, suite_path in ipairs(suites) do
  local suite = dofile(suite_path)
  local names = {}
  for name, fn in pairs(suite) do
    if type(fn) == "function" and name:match("^test_") then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    total = total + 1
    local ok, err = xpcall(suite[name], debug.traceback)
    if ok then
      io.stdout:write(".")
    else
      io.stdout:write("F")
      failures[#failures + 1] = { name = suite_path .. " :: " .. name, err = err }
    end
  end
end

io.stdout:write("\n")

if #failures > 0 then
  for index, failure in ipairs(failures) do
    io.stderr:write(tostring(index), ") ", failure.name, "\n", tostring(failure.err), "\n")
  end
  io.stderr:write(string.format("tests: %d of %d failed\n", #failures, total))
  os.exit(1)
end

print(string.format("arch_view tests ok (%d)", total))
