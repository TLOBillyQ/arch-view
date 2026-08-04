# arch_view

`arch_view` is a pure-Lua module dependency analyzer for Lua projects.

It scans configured source roots, extracts static `require(...)` dependencies,
classifies modules with JSON rules, checks forbidden dependencies, and exports a
self-contained viewer bundle.

## Repository Layout

- `lib/arch_view/init.lua`: public API entrypoint (`require("arch_view")`)
- `lib/arch_view/cli.lua`: public CLI facade (`require("arch_view.cli")`)
- `lib/arch_view/internal/analyzer.lua`: scan, classify, check, and view model generation
- `lib/arch_view/internal/layout.lua`: pure layout engine (Tarjan SCC, feedback edges: exact minimum-set enumeration for small components, Eades greedy otherwise, longest-path layering, unclebob geometry)
- `lib/arch_view/internal/service.lua`: public API orchestration and viewer export
- `lib/arch_view/runtime/*`: filesystem, JSON, and path helpers
- `lua/viewer/*`: static viewer assets (installed into the rock's lua dir by the builtin driver)
- `tests/*`: golden-output regression infra (fixture, compare, bench)

## CLI

The library ships Lua modules only — no standalone `bin/` entrypoint. The
public CLI facade is `require("arch_view.cli").run(args, env)`; any host can
invoke it directly:

```sh
lua -e 'package.path = "lib/?.lua;lib/?/init.lua;" .. package.path
        os.exit(require("arch_view.cli").run(arg, {
          command_name = "arch_view",
          default_config_path = "arch_view.config.json",
          script_dir = ".",
        }) and 0 or 1)' \
  scan --out <file> [--project-root <dir>] [--config <file>]
```

Commands: `scan`, `check`, `viewer` (see `--help`-less usage by running with
no command). Recognized `env` keys:

- `cwd`: working directory used to resolve relative paths (default: process cwd)
- `command_name`: display name in usage text
- `default_project_root`: project root when `--project-root` is absent
- `default_config_path`: config path when `--config` is absent
- `script_dir`: used as asset root only when a `viewer/` directory exists under it; otherwise assets resolve via `paths.default_asset_root()` (source tree `lua/viewer/`, installed rock `<lua_dir>/viewer`)
- `open_path`: function used to open the generated viewer (default: OS opener)

Hosts typically wrap this in a small script; see the next section.

## Using arch_view in a new project (eggy example)

1. Vendor the library, e.g. as a git submodule or a plain copy at
   `eggy/vendor/arch_view` (keep `lib/` and `lua/viewer/`).
2. Write `eggy/arch_view.config.json` with your `source_roots`,
   `component_rules`, `abstract_rules`, and `forbidden_dependency_rules`
   (schema shown in the Config section below).
3. Add a minimal wrapper, e.g. `eggy/tools/arch.lua`:

   ```lua
   package.path = "vendor/arch_view/lib/?.lua;vendor/arch_view/lib/?/init.lua;"
     .. package.path
   local cli = require("arch_view.cli")
   local ok = cli.run(arg or {}, {
     command_name = "tools/arch.lua",
     default_config_path = "arch_view.config.json",
     script_dir = "vendor/arch_view",
   })
   os.exit(ok and 0 or 1)
   ```

4. Run it from the project root:

   ```sh
   lua tools/arch.lua check                                  # gate check (forbidden deps, layers, projection cycles)
   lua tools/arch.lua scan --out .arch_view/architecture.json
   lua tools/arch.lua viewer --out-dir .arch_view/viewer --open
   ```

## Public API

```lua
local arch_view = require("arch_view")

local architecture = assert(arch_view.analyze({
  project_root = ".",
  config_path = "arch_view.config.json",
}))

assert(arch_view.write_scan({
  architecture = architecture,
  project_root = ".",
  out_path = ".arch_view/architecture.json",
}))

assert(arch_view.export_viewer({
  architecture = architecture,
  project_root = ".",
  out_dir = ".arch_view/viewer",
}))
```

Available entrypoints:

- `load_config(path)`
- `analyze(opts)`
- `check(opts)`
- `write_scan(opts)`
- `export_viewer(opts)`
- `run_cli(args, opts)`

## Config

```json
{
  "source_roots": ["src"],
  "component_rules": [
    { "name": "demo", "match": ["^src%.demo$", "^src%.demo%..+"], "component": "demo" }
  ],
  "abstract_rules": [],
  "forbidden_dependency_rules": [],
  "allowed_cycles": [
    { "view": "root", "nodes": ["registry", "plugin"], "reason": "self-registration pattern" }
  ]
}
```

### Projection-cycle gate (issue #3)

`check` fails closed on projection cycles: any dependency cycle visible in a
view (the same cycles the viewer renders red, from the same layout run) makes
`check.ok` false and the CLI exit non-zero. The gate facts live in
`check.projection_cycles` — one entry per cycle, owned by exactly one view:

- `view` — the owning view key (`"root"` or a dotted namespace path);
- `cycle` — the closed `"a->b->a"` full-name line, the string the viewer
  shows;
- `nodes` — the participant names in path order;
- `waived` — boolean; `reason` is added when a waiver matched.

Every unwaived cycle also appears once in `check.violations` as
`kind = "projection_cycle"` with its `view` and `cycle`.

`allowed_cycles` is the waiver list for cycles a project has ruled acceptable
(e.g. a registry self-registration pattern). An entry matches a reported cycle
by **exact view key plus participant-set equality** on `nodes` — the traversal
order of the cycle line does not matter. A matched cycle is reported with
`waived = true` (and its `reason`) and does not fail the gate; an entry that
matches nothing has no effect. `allowed_cycles` is optional; without it every
cycle fails.

### Layer gate (`layer` / `substrate`, ADR 0039 D2)

A `component_rules` entry may declare its position in a governance layer stack.
When it does, `check` enforces the layer order **as a gate fact source** — no
hand-written `forbidden_dependency_rules` pair is needed to forbid an upward
dependency. This is a gate feature (it changes what `check` rejects) and is
independent of the pinned-layer *presentation* mode below.

- `"layer": <integer>` — the component's layer. **L1 is the highest layer**, so
  a larger number is a lower layer. Dependencies must point downward
  (higher → lower, i.e. `from.layer < to.layer`). A **lower layer depending on a
  higher one** (`from.layer > to.layer`) is reported as a `layer_violation`.
- `"substrate": true` — marks a **substrate** component (e.g. a foundation
  layer): it carries no integer `layer` and takes no part in the integer
  inequality. The two `layer`/`substrate` forms are mutually exclusive on a
  rule; **do not** give a substrate an L0/L8 number. Substrate follows a
  qualitatively different rule:
  - anyone → substrate is **always legal**;
  - substrate → any integer-layered component is **always a violation**.

A `layer_violation` carries `kind`, `from`, `to`, and both declared layer
values `from_layer` / `to_layer` (each an integer, or the literal `"substrate"`
for a substrate endpoint). Edges where either end declares no layer are not
judged by this gate. A config that declares **no** `layer`/`substrate` anywhere
produces byte-identical output to before this feature — the gate is inert until
a layer is declared. The output-schema contract for these fields lives in
`tests/test_contract.lua`.

## Pinned-layer layout mode (issue #1)

An optional presentation mode for architectures with a declared layer model
(e.g. an L1..L7 governance hierarchy). Rows are pinned by declaration instead
of the longest-path topology, and edges that point *up* against the declared
direction are rendered as bold red upward arrows instead of triggering a
reorder — a review sees "there is a reverse dependency here", not "the
ordering changed".

- Config: `component_rules` entries take an optional integer `layer`; a
  top-level `"pinned_layers": true` turns the mode on globally. Components
  without a declared layer keep the topological behavior and sink below the
  pinned block.
- CLI/API: `scan`/`viewer` accept `--pinned-layers` (`pinned_layers = true`
  in API opts), which enables the mode without the config switch. Note the
  mode is baked in at analysis time — `viewer --in-json` re-exports whatever
  the scan produced.
- Output: rows use the dense rank of the distinct declared values (gaps in
  the numbering don't create empty rows); `node.component_layer` carries the
  declaration, every view edge gets `direction_violation` (true = upward
  against the declaration), and the top level records `"pinned_layers": true`.
  `cycle_break` semantics are unchanged, and with the mode off the presentation
  output is byte-identical to before. Note the pinned **switch** is presentation
  only; the layer **gate** (`layer`/`substrate` → `layer_violation`, see the
  Config section) reads the declared layers directly and fires regardless of
  whether this presentation switch is on.

## Tests

The output tests are split into two layers with distinct jobs (ADR 0039 D4):

- **Contract layer** — `tests/test_contract.lua`: small, hand-written
  assertions on the output *schema* (field presence, types, invariants:
  `schema_version` is an integer; `check.ok`/`check.violations` shape; every
  violation carries a `kind`, `forbidden_dependency` carries `rule`/`from`/`to`,
  `unclassified_module` carries `module_id`; `check.projection_cycles` lists
  every projection cycle with `view`/`cycle`/`nodes`/`waived` and unwaived
  cycles surface as `projection_cycle` violations; pinned-mode view edges
  carry a boolean `direction_violation`; view edges carry a boolean
  `cycle_break`).
  This is the **authoritative, human-readable statement of the output
  contract** — read it to know what the schema guarantees, and break any field
  to see it go red without a golden rewrite. It runs under `tests/run.lua`.
- **Regression layer** — `tests/golden/*` + `tests/compare.lua`: a
  machine-maintained byte baseline (exhaustive, not human-readable). It catches
  unintended drift. Regenerate it with `lua tests/gen_golden.lua` on its **own
  commit**, whose message / PR description lists which fields changed and why.

Golden-output regression: `tests/compare.lua` regenerates the scan and
viewer outputs for `tests/fixture` and byte-compares them against
`tests/golden`. Run from the repository root:

```sh
lua tests/run.lua       # unit tests (luaunit, exit 0 = all pass)
lua tests/compare.lua   # regression check (exit 0 = outputs match golden)
lua tests/bench.lua 50  # analyze benchmark (CPU ms per iteration)
tests/check_syntax.sh   # luac -p on lib/ + tests/, node --check lua/viewer/script.js
node tests/smoke_viewer.js  # viewer interaction smoke on a minimal DOM stub
node tests/viewer_search_smoke.js  # viewer search interaction smoke (minimal DOM stub)
node tests/viewer_pinned_smoke.js  # pinned-layer scene model / violation arrows (pure functions)
```

Unit tests live in `tests/test_*.lua`; each file returns a table of `test_*`
functions and `tests/run.lua` discovers and executes them — add a suite by
dropping another `test_*.lua` file into `tests/`. The suites use
[luaunit](https://github.com/bluebird75/luaunit), installed via luarocks
(`luarocks install luaunit`), following the 4lua-chain test convention
(ADR-0005/0006); the runner itself remains the only entry point.

Run `lua tests/gen_golden.lua` only when intentionally updating the baseline.

---

## 中文文档

`arch_view` 是纯 Lua 的模块依赖分析工具。它扫描 Lua 源码中的静态 `require(...)`，
按配置规则分类模块、检查禁止依赖，并导出可离线查看的静态 viewer。
