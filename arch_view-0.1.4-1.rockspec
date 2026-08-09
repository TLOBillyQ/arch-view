rockspec_format = "3.0"
package = "arch_view"
version = "0.1.4-1"
source = {
   url = "git+http://lzxsvn:3000/qinyuanj/arch_view.git",
   tag = "v0.1.4",
}
description = {
   summary = "Static module dependency analyzer for Lua projects",
   detailed = [[
      arch_view is a pure-Lua module dependency analyzer for Lua projects.
      It scans configured source roots, extracts static require(...) dependencies,
      classifies modules with JSON rules, checks forbidden dependencies, and
      exports a self-contained viewer bundle.
   ]],
   homepage = "http://lzxsvn:3000/qinyuanj/arch_view",
   license = "MIT",
}
dependencies = {
   "lua >= 5.4",
}
test_dependencies = {
   "luaunit == 3.5-1",
}
build = {
   type = "builtin",
   -- Viewer static assets (index.html/script.js/styles.css) live in
   -- lua/viewer/: the builtin driver copies the repo-root lua/ directory
   -- into the lua dir (<tree>/share/lua/5.4), so the installed rock carries
   -- them at <lua_dir>/viewer, matching paths.default_asset_root()'s rock
   -- form (see src/arch_view/internal/paths.lua).
   modules = {
      ["arch_view"] = "src/arch_view/init.lua",
      ["arch_view.cli"] = "src/arch_view/cli.lua",
      ["arch_view.internal.analyzer"] = "src/arch_view/internal/analyzer.lua",
      ["arch_view.internal.cli_runner"] = "src/arch_view/internal/cli_runner.lua",
      ["arch_view.internal.config"] = "src/arch_view/internal/config.lua",
      ["arch_view.internal.layout"] = "src/arch_view/internal/layout.lua",
      ["arch_view.internal.paths"] = "src/arch_view/internal/paths.lua",
      ["arch_view.internal.service"] = "src/arch_view/internal/service.lua",
      ["arch_view.runtime.common"] = "src/arch_view/runtime/common.lua",
      ["arch_view.runtime.fs"] = "src/arch_view/runtime/fs.lua",
      ["arch_view.runtime.host"] = "src/arch_view/runtime/host.lua",
      ["arch_view.runtime.json_reader"] = "src/arch_view/runtime/json_reader.lua",
      ["arch_view.runtime.json_writer"] = "src/arch_view/runtime/json_writer.lua",
      ["arch_view.runtime.module_path"] = "src/arch_view/runtime/module_path.lua",
   },
}
