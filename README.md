# arch_view

`arch_view` is a pure-Lua module dependency analyzer for Lua projects.

It scans configured source roots, extracts static `require(...)` dependencies,
classifies modules with JSON rules, checks forbidden dependencies, and exports a
self-contained viewer bundle.

## Repository Layout

- `lib/arch_view/init.lua`: public API entrypoint (`require("arch_view")`)
- `lib/arch_view/cli.lua`: public CLI facade (`require("arch_view.cli")`)
- `lib/arch_view/internal/analyzer.lua`: scan, classify, check, and view model generation
- `lib/arch_view/internal/service.lua`: public API orchestration and viewer export
- `lib/arch_view/runtime/*`: filesystem, JSON, and path helpers
- `viewer/*`: static viewer assets
- `tests/*`: golden-output regression infra (fixture, compare, bench)

## CLI

In Monopoly, the public CLI is the repository wrapper:

```sh
lua tools/quality/arch.lua scan --out <file> [--project-root <dir>] [--config <file>]
lua tools/quality/arch.lua check [--project-root <dir>] [--config <file>]
lua tools/quality/arch.lua viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--open]
lua tools/quality/arch.lua
```

The vendor package exposes Lua modules only. It does not ship a standalone
`bin/` entrypoint.

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
```

Unit tests live in `tests/test_*.lua`; each file returns a table of `test_*`
functions and `tests/run.lua` executes them — add a suite by listing it in
`tests/run.lua`. No external test framework is required.

Run `lua tests/gen_golden.lua` only when intentionally updating the baseline.

---

## 中文文档

`arch_view` 是纯 Lua 的模块依赖分析工具。它扫描 Lua 源码中的静态 `require(...)`，
按配置规则分类模块、检查禁止依赖，并导出可离线查看的静态 viewer。
