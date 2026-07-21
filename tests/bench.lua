-- Micro benchmark for arch_view.analyze on tests/fixture.
-- Run from the repository root:
--   lua tests/bench.lua [iterations] [result_file]
-- Defaults: 50 iterations, no result file.
-- Prints iteration count and average CPU time per analyze in milliseconds
-- (os.clock); when result_file is given, appends one summary line so runs
-- can be compared before/after an optimization.

local helpers = dofile("tests/helpers.lua")

local iterations = tonumber(arg and arg[1]) or 50
if iterations < 1 then
  helpers.fail("error: iterations must be >= 1")
end
local result_file = arg and arg[2]

helpers.setup()
local arch_view = require("arch_view")

local opts = {
  project_root = helpers.PROJECT_ROOT,
  config_path = helpers.CONFIG_PATH,
}

-- Warm up: populate caches and validate the fixture once.
local architecture, err = arch_view.analyze(opts)
if architecture == nil then
  helpers.fail("error: analyze failed: " .. tostring(err))
end
local module_count = #(architecture.graph and architecture.graph.nodes or {})

local start = os.clock()
for _ = 1, iterations do
  local result, run_err = arch_view.analyze(opts)
  if result == nil then
    helpers.fail("error: analyze failed during benchmark: " .. tostring(run_err))
  end
end
local total_ms = (os.clock() - start) * 1000
local average_ms = total_ms / iterations

print(string.format("iterations: %d (fixture modules: %d)", iterations, module_count))
print(string.format("total: %.3f ms", total_ms))
print(string.format("average: %.3f ms per analyze (CPU time via os.clock)", average_ms))

if result_file ~= nil then
  local line = string.format(
    "%s iterations=%d modules=%d total_ms=%.3f avg_ms=%.3f\n",
    os.date("!%Y-%m-%dT%H:%M:%SZ"),
    iterations,
    module_count,
    total_ms,
    average_ms
  )
  local file = io.open(result_file, "ab")
  if file == nil then
    helpers.fail("error: cannot open result file for append: " .. tostring(result_file))
  end
  file:write(line)
  file:close()
  print("result appended to " .. tostring(result_file))
end
