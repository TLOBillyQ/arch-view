-- Regenerates the golden baseline under tests/golden from the CURRENT code.
-- Run from the repository root:  lua tests/gen_golden.lua
-- Only run this intentionally (initial baseline or after a verified output
-- change); tests/compare.lua treats these files as the expected output.
--
-- Update convention (ADR 0039 D4): the golden files are the machine
-- regression baseline, not the output contract (that is tests/test_contract.lua).
-- Commit a regeneration on its OWN, standalone commit whose message / PR
-- description lists which output fields changed and why — never bundle a
-- ~300KB golden rewrite into an unrelated behavior change.

local helpers = dofile("tests/helpers.lua")

local root = helpers.setup()
local fs = require("arch_view.runtime.fs")

local tmp_dir = fs.make_temp_path("arch_view_golden", "")
local ok, err = fs.ensure_dir(tmp_dir)
if not ok then
  helpers.fail("error: cannot create temp dir: " .. tostring(err))
end

local outputs = helpers.generate_outputs(root, tmp_dir)

local targets = {
  { generated = outputs.scan_json, golden = helpers.GOLDEN_DIR .. "/scan/architecture.json" },
  { generated = outputs.viewer_json, golden = helpers.GOLDEN_DIR .. "/viewer/architecture.json" },
  { generated = outputs.viewer_data_js, golden = helpers.GOLDEN_DIR .. "/viewer/architecture_data.js" },
}

for _, target in ipairs(targets) do
  local content = helpers.read_file(target.generated)
  if content == nil then
    helpers.fail("error: generated file missing: " .. tostring(target.generated))
  end
  local normalized = helpers.normalize(content, root)
  local dir_ok, dir_err = fs.ensure_parent_dir(target.golden)
  if not dir_ok then
    helpers.fail("error: " .. tostring(dir_err))
  end
  local write_ok, write_err = helpers.write_file(target.golden, normalized)
  if not write_ok then
    helpers.fail("error: " .. tostring(write_err))
  end
  print(string.format("wrote %s (%d bytes, normalized)", target.golden, #normalized))
end

fs.remove_path(tmp_dir)
print("golden baseline regenerated from current code")
