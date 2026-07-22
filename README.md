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
- `viewer/*`: static viewer assets
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
- `script_dir`: directory containing `viewer/` assets (sets the viewer asset root)
- `open_path`: function used to open the generated viewer (default: OS opener)

Hosts typically wrap this in a small script; see the next section.

## Using arch_view in a new project (eggy example)

1. Vendor the library, e.g. as a git submodule or a plain copy at
   `eggy/vendor/arch_view` (keep `lib/` and `viewer/`).
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
   lua tools/arch.lua check                                  # forbidden-dependency check
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
  "forbidden_dependency_rules": []
}
```

## Tests

Golden-output regression: `tests/compare.lua` regenerates the scan and
viewer outputs for `tests/fixture` and byte-compares them against
`tests/golden`. Run from the repository root:

```sh
lua tests/run.lua       # unit tests (dependency-free mini harness, exit 0 = all pass)
lua tests/compare.lua   # regression check (exit 0 = outputs match golden)
lua tests/bench.lua 50  # analyze benchmark (CPU ms per iteration)
tests/check_syntax.sh   # luac -p on lib/ + tests/, node --check viewer/script.js
node tests/smoke_viewer.js  # viewer interaction smoke on a minimal DOM stub
node tests/viewer_search_smoke.js  # viewer search interaction smoke (minimal DOM stub)
```

Unit tests live in `tests/test_*.lua`; each file returns a table of `test_*`
functions and `tests/run.lua` executes them — add a suite by listing it in
`tests/run.lua`. No external test framework is required.

Run `lua tests/gen_golden.lua` only when intentionally updating the baseline.

---

## 中文文档

`arch_view` 是纯 Lua 的模块依赖分析工具。它扫描 Lua 源码中的静态 `require(...)`，
按配置规则分类模块、检查禁止依赖，并导出可离线查看的静态 viewer。
