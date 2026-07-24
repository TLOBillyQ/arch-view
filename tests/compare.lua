-- Compares freshly generated arch_view output for tests/fixture against the
-- golden baseline in tests/golden, byte for byte (after normalizing the
-- absolute repository root to __ARCH_VIEW_ROOT__ on the generated side).
-- Run from the repository root:  lua tests/compare.lua
-- Exit code 0 and prints OK when everything matches; otherwise prints the
-- first difference per mismatched file and exits non-zero.
--
-- REGRESSION LAYER — MACHINE BASELINE (ADR 0039 D4). The three golden files
-- under tests/golden are a machine-maintained byte baseline: exhaustive but
-- not human-readable, and a ~300KB rewrite on any output change. They catch
-- unintended drift; they do NOT state the output contract. The authoritative,
-- human-readable statement of that contract is tests/test_contract.lua — read
-- that to know what the schema guarantees; treat a golden diff as "something
-- changed, go check the contract layer explains it".
--
-- Updating the baseline: never fold a golden rewrite into a behavior change.
-- Run `lua tests/gen_golden.lua` in its OWN commit, and put a human-readable
-- "which fields changed and why" summary in that commit message / PR
-- description. A golden rewrite with no such summary is unreviewable.

local helpers = dofile("tests/helpers.lua")

local root = helpers.setup()
local fs = require("arch_view.runtime.fs")

local function line_number_at(content, index)
  local _, newlines = tostring(content):sub(1, index - 1):gsub("\n", "\n")
  return newlines + 1
end

local function line_at(content, line_number)
  local current = 1
  for line in (tostring(content) .. "\n"):gmatch("(.-)\n") do
    if current == line_number then
      return line
    end
    current = current + 1
  end
  return nil
end

local function shorten(text, limit)
  text = tostring(text or "")
  if #text <= limit then
    return text
  end
  return text:sub(1, limit) .. "...<truncated, " .. #text .. " bytes total>"
end

-- Returns nil when identical, otherwise a human-readable description of the
-- first differing position.
local function first_difference(expected, actual)
  if expected == actual then
    return nil
  end
  local common = 0
  local limit = math.min(#expected, #actual)
  while common < limit and expected:byte(common + 1) == actual:byte(common + 1) do
    common = common + 1
  end
  local line_number = line_number_at(expected, common + 1)
  local parts = {
    string.format("first difference at byte offset %d (0-based), line %d", common, line_number),
    string.format("expected line: %s", shorten(line_at(expected, line_number), 200)),
    string.format("actual   line: %s", shorten(line_at(actual, line_number), 200)),
    string.format("expected byte: %s, actual byte: %s",
      tostring(expected:byte(common + 1)), tostring(actual:byte(common + 1))),
    string.format("expected length: %d bytes, actual length: %d bytes", #expected, #actual),
  }
  return table.concat(parts, "\n    ")
end

local tmp_dir = fs.make_temp_path("arch_view_compare", "")
local ok, err = fs.ensure_dir(tmp_dir)
if not ok then
  helpers.fail("error: cannot create temp dir: " .. tostring(err))
end

local outputs = helpers.generate_outputs(root, tmp_dir)

local cases = {
  { name = "scan architecture.json (write_scan)", generated = outputs.scan_json, golden = helpers.GOLDEN_DIR .. "/scan/architecture.json" },
  { name = "viewer architecture.json (export_viewer)", generated = outputs.viewer_json, golden = helpers.GOLDEN_DIR .. "/viewer/architecture.json" },
  { name = "viewer architecture_data.js (export_viewer)", generated = outputs.viewer_data_js, golden = helpers.GOLDEN_DIR .. "/viewer/architecture_data.js" },
}

local failures = 0
for _, case in ipairs(cases) do
  local expected = helpers.read_file(case.golden)
  if expected == nil then
    helpers.fail("error: golden file missing: " .. case.golden
      .. " (run `lua tests/gen_golden.lua` to create the baseline)")
  end
  local actual_raw = helpers.read_file(case.generated)
  if actual_raw == nil then
    helpers.fail("error: generated file missing: " .. tostring(case.generated))
  end
  local actual = helpers.normalize(actual_raw, root)

  local difference = first_difference(expected, actual)
  if difference == nil then
    print(string.format("OK %s (%d bytes)", case.name, #actual))
  else
    failures = failures + 1
    print(string.format("FAIL %s\n    golden: %s\n    %s", case.name, case.golden, difference))
  end
end

fs.remove_path(tmp_dir)

if failures > 0 then
  print(string.format("compare: %d of %d outputs differ from tests/golden", failures, #cases))
  os.exit(1)
end
print(string.format("compare: all %d outputs match tests/golden", #cases))
