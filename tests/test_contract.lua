-- Contract-layer assertions for the arch_view output schema (ADR 0039 D4/D2).
--
-- This suite is the SOLE AUTHORITATIVE, human-readable statement of the
-- arch_view output contract: every field a downstream gate consumes is
-- asserted here by name, type, and invariant. It is deliberately small and
-- self-contained (it builds its own fixtures under the system temp dir), so a
-- reviewer can read it end to end and know exactly what shape `analyze`
-- guarantees. The byte-for-byte golden regression in tests/compare.lua is a
-- machine baseline that backs this up; when the two disagree, THIS file states
-- the intent.
--
-- Break any asserted field (rename check.violations, drop a violation's kind,
-- stop emitting direction_violation in pinned mode, stop reporting a
-- layer_violation, ...) and this suite goes red without needing a golden
-- rewrite to notice.

local arch_view = require("arch_view")
local lu = require("luaunit")
local common = require("arch_view.runtime.common")

local tmp_root = common.join_path(common.system_tmp_dir(), "arch_view_test_contract")

local function _mkdir(path)
  local ok, err = common.ensure_dir(path)
  if not ok then
    error(err)
  end
end

local function _write_file(path, content)
  local ok, err = common.write_file(path, content)
  if not ok then
    error(err)
  end
end

-- Build a controlled project that triggers every check violation kind and,
-- with pinned layers on, exercises direction_violation / cycle_break on view
-- edges. L1 is the highest layer, so a larger number is a LOWER layer.
--
--   layers:   top = 1 (highest) > mid = 2 > base = 3 (lowest integer)
--             foundation = substrate (no integer layer)
--             orphan = no component rule
--
--   top  -> mid            downward (1<2), legal direction
--   top  -> base           downward (1<3), legal direction, but forbidden by
--                          the explicit rule top_no_base (forbidden_dependency)
--   mid  -> base           downward (2<3), legal direction
--   base -> top            UPWARD (3>1) -> layer_violation, closes a cycle,
--                          and direction_violation in the pinned layout
--   base -> foundation     integer -> substrate, always legal
--   foundation -> mid      substrate -> integer-layered -> layer_violation
--   orphan                 no component rule -> unclassified_module
local function _write_project(project_root)
  _mkdir(common.join_path(project_root, "src"))
  _write_file(common.join_path(project_root, "arch_view.config.json"), [[
{
  "source_roots": ["src"],
  "component_rules": [
    { "name": "top", "match": ["^src%.top$"], "component": "top", "layer": 1 },
    { "name": "mid", "match": ["^src%.mid$"], "component": "mid", "layer": 2 },
    { "name": "base", "match": ["^src%.base$"], "component": "base", "layer": 3 },
    { "name": "foundation", "match": ["^src%.foundation$"], "component": "foundation", "substrate": true }
  ],
  "abstract_rules": [],
  "forbidden_dependency_rules": [
    {
      "name": "top_no_base",
      "description": "top must not depend on base directly",
      "from": ["^src%.top$"],
      "to": ["^src%.base$"]
    }
  ]
}
]])
  _write_file(common.join_path(project_root, "src/top.lua"),
    'local mid = require("src.mid")\nlocal base = require("src.base")\nreturn {}')
  _write_file(common.join_path(project_root, "src/mid.lua"), 'local base = require("src.base")\nreturn {}')
  _write_file(common.join_path(project_root, "src/base.lua"),
    'local top = require("src.top")\nlocal foundation = require("src.foundation")\nreturn {}')
  _write_file(common.join_path(project_root, "src/foundation.lua"), 'local mid = require("src.mid")\nreturn {}')
  _write_file(common.join_path(project_root, "src/orphan.lua"), "return {}")
end

-- Analyze the controlled project once (pinned = true or false) and hand the
-- result to fn; the temp tree is removed either way.
local function _with_architecture(pinned, fn)
  common.remove_path(tmp_root)
  _mkdir(tmp_root)
  local ok, err = pcall(function()
    local project_root = common.join_path(tmp_root, "project")
    _write_project(project_root)
    local architecture, analyze_err = arch_view.analyze({
      project_root = project_root,
      config_path = common.join_path(project_root, "arch_view.config.json"),
      pinned_layers = pinned,
    })
    if architecture == nil then
      error(analyze_err)
    end
    fn(architecture)
  end)
  common.remove_path(tmp_root)
  if not ok then
    error(err)
  end
end

local function _find_violation(check, kind)
  for _, violation in ipairs(check.violations or {}) do
    if violation.kind == kind then
      return violation
    end
  end
  return nil
end

local function _find_violation_where(check, kind, from, to)
  for _, violation in ipairs(check.violations or {}) do
    if violation.kind == kind and violation.from == from and violation.to == to then
      return violation
    end
  end
  return nil
end

local function _each_view_edge(architecture, fn)
  local count = 0
  for _, view in pairs(architecture.views or {}) do
    for _, edge in ipairs(view.display_edges or {}) do
      count = count + 1
      fn(edge, view)
    end
  end
  return count
end

-- schema_version is present and an INTEGER (the cross-repo contract in ADR
-- 0039 D5 keys off exactly this value).
local function test_schema_version_is_integer()
  _with_architecture(true, function(architecture)
    lu.assertTrue(architecture.schema_version ~= nil, "schema_version must be present")
    lu.assertTrue(math.type(architecture.schema_version) == "integer",
      "schema_version must be an integer, got " .. tostring(architecture.schema_version))
  end)
end

-- check is the gate's payload: an `ok` boolean and a `violations` array.
local function test_check_shape()
  _with_architecture(true, function(architecture)
    local check = architecture.check
    lu.assertTrue(type(check) == "table", "architecture.check must be a table")
    lu.assertTrue(type(check.ok) == "boolean", "check.ok must be a boolean")
    lu.assertTrue(type(check.violations) == "table", "check.violations must be a table")
  end)
end

-- Every violation, whatever its kind, carries a non-empty string `kind`
-- discriminator. Downstream gates switch on it.
local function test_every_violation_has_kind()
  _with_architecture(true, function(architecture)
    local violations = architecture.check.violations
    lu.assertTrue(#violations > 0, "the controlled fixture must produce violations")
    for _, violation in ipairs(violations) do
      lu.assertTrue(type(violation.kind) == "string" and violation.kind ~= "",
        "every violation must carry a non-empty string kind")
    end
  end)
end

-- forbidden_dependency violations name the broken rule and both endpoints.
local function test_forbidden_dependency_violation_shape()
  _with_architecture(true, function(architecture)
    local violation = _find_violation(architecture.check, "forbidden_dependency")
    lu.assertTrue(violation ~= nil, "fixture must produce a forbidden_dependency violation")
    lu.assertTrue(violation.rule == "top_no_base",
      "forbidden_dependency must name its rule, got " .. tostring(violation.rule))
    lu.assertTrue(type(violation.from) == "string" and violation.from ~= "",
      "forbidden_dependency must carry a string `from`")
    lu.assertTrue(type(violation.to) == "string" and violation.to ~= "",
      "forbidden_dependency must carry a string `to`")
  end)
end

-- unclassified_module violations name the offending module.
local function test_unclassified_module_violation_shape()
  _with_architecture(true, function(architecture)
    local violation = _find_violation(architecture.check, "unclassified_module")
    lu.assertTrue(violation ~= nil, "fixture must produce an unclassified_module violation")
    lu.assertTrue(violation.module_id == "src.orphan",
      "unclassified_module must name its module_id, got " .. tostring(violation.module_id))
  end)
end

-- layer_violation (ADR 0039 D2): a lower layer depending on a higher one. The
-- violation carries both endpoints AND both declared layer values.
local function test_layer_violation_integer_shape()
  _with_architecture(true, function(architecture)
    local violation = _find_violation_where(architecture.check, "layer_violation", "src.base", "src.top")
    lu.assertTrue(violation ~= nil, "base(3) -> top(1) must report a layer_violation")
    lu.assertTrue(violation.from_layer == 3,
      "layer_violation must carry integer from_layer, got " .. tostring(violation.from_layer))
    lu.assertTrue(violation.to_layer == 1,
      "layer_violation must carry integer to_layer, got " .. tostring(violation.to_layer))
  end)
end

-- Substrate semantics (ADR 0039 D2): substrate -> any integer-layered
-- component is always a violation, reported as a layer_violation whose
-- from_layer is the literal "substrate".
local function test_substrate_upward_is_violation()
  _with_architecture(true, function(architecture)
    local violation = _find_violation_where(architecture.check, "layer_violation", "src.foundation", "src.mid")
    lu.assertTrue(violation ~= nil, "substrate foundation -> mid(2) must report a layer_violation")
    lu.assertTrue(violation.from_layer == "substrate",
      "substrate-origin layer_violation must carry from_layer == 'substrate', got "
      .. tostring(violation.from_layer))
    lu.assertTrue(violation.to_layer == 2,
      "substrate-origin layer_violation must carry the integer to_layer, got " .. tostring(violation.to_layer))
  end)
end

-- Substrate semantics (ADR 0039 D2): anyone -> substrate is always legal, so
-- an integer-layered component depending on substrate produces no violation.
local function test_dependency_into_substrate_is_legal()
  _with_architecture(true, function(architecture)
    local violation = _find_violation_where(architecture.check, "layer_violation", "src.base", "src.foundation")
    lu.assertTrue(violation == nil, "base(3) -> substrate foundation must NOT be a layer_violation")
  end)
end

-- In pinned mode every view edge carries a boolean direction_violation
-- (arch_view #1); this is the presentation-side fact the review reads.
local function test_pinned_view_edges_have_direction_violation()
  _with_architecture(true, function(architecture)
    local count = _each_view_edge(architecture, function(edge)
      lu.assertTrue(type(edge.direction_violation) == "boolean",
        "pinned-mode view edge must carry a boolean direction_violation")
    end)
    lu.assertTrue(count > 0, "fixture must produce at least one view edge")
    -- base -> top is the upward edge; at least one direction_violation is true.
    local saw_violation = false
    _each_view_edge(architecture, function(edge)
      if edge.direction_violation == true then
        saw_violation = true
      end
    end)
    lu.assertTrue(saw_violation, "the upward base->top edge must flag direction_violation = true")
  end)
end

-- Every view edge (both modes) carries a boolean cycle_break marking the
-- feedback edges the layout removed; the fixture's base<->top cycle forces one.
local function test_view_edges_have_cycle_break()
  _with_architecture(true, function(architecture)
    local saw_break = false
    local count = _each_view_edge(architecture, function(edge)
      lu.assertTrue(type(edge.cycle_break) == "boolean",
        "view edge must carry a boolean cycle_break")
      if edge.cycle_break == true then
        saw_break = true
      end
    end)
    lu.assertTrue(count > 0, "fixture must produce at least one view edge")
    lu.assertTrue(saw_break, "the base<->top cycle must produce at least one cycle_break edge")
  end)
end

-- With pinned mode OFF the output is byte-identical to before the feature: the
-- direction_violation field is absent entirely (not false). The layer gate
-- (check.violations) is independent of pinned mode and still fires.
local function test_default_mode_omits_direction_violation()
  _with_architecture(false, function(architecture)
    lu.assertTrue(architecture.pinned_layers == nil,
      "default mode must not set the top-level pinned_layers flag")
    _each_view_edge(architecture, function(edge)
      lu.assertTrue(edge.direction_violation == nil,
        "default-mode view edge must omit direction_violation entirely")
    end)
    lu.assertTrue(_find_violation(architecture.check, "layer_violation") ~= nil,
      "layer gate is independent of pinned mode and must still report violations")
  end)
end

return {
  test_schema_version_is_integer = test_schema_version_is_integer,
  test_check_shape = test_check_shape,
  test_every_violation_has_kind = test_every_violation_has_kind,
  test_forbidden_dependency_violation_shape = test_forbidden_dependency_violation_shape,
  test_unclassified_module_violation_shape = test_unclassified_module_violation_shape,
  test_layer_violation_integer_shape = test_layer_violation_integer_shape,
  test_substrate_upward_is_violation = test_substrate_upward_is_violation,
  test_dependency_into_substrate_is_legal = test_dependency_into_substrate_is_legal,
  test_pinned_view_edges_have_direction_violation = test_pinned_view_edges_have_direction_violation,
  test_view_edges_have_cycle_break = test_view_edges_have_cycle_break,
  test_default_mode_omits_direction_violation = test_default_mode_omits_direction_violation,
}
