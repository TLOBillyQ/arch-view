rockspec_format = "3.0"
package = "arch_view"
version = "0.1.0-1"
source = {
   url = "git+http://lzxsvn:3000/qinyuanj/arch_view.git",
   tag = "v0.1.0",
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
   modules = {
      ["arch_view"] = "lib/arch_view/init.lua",
      ["arch_view.cli"] = "lib/arch_view/cli.lua",
      ["arch_view.internal.analyzer"] = "lib/arch_view/internal/analyzer.lua",
      ["arch_view.internal.cli_runner"] = "lib/arch_view/internal/cli_runner.lua",
      ["arch_view.internal.config"] = "lib/arch_view/internal/config.lua",
      ["arch_view.internal.layout"] = "lib/arch_view/internal/layout.lua",
      ["arch_view.internal.paths"] = "lib/arch_view/internal/paths.lua",
      ["arch_view.internal.service"] = "lib/arch_view/internal/service.lua",
      ["arch_view.runtime.common"] = "lib/arch_view/runtime/common.lua",
      ["arch_view.runtime.fs"] = "lib/arch_view/runtime/fs.lua",
      ["arch_view.runtime.host"] = "lib/arch_view/runtime/host.lua",
      ["arch_view.runtime.json_reader"] = "lib/arch_view/runtime/json_reader.lua",
      ["arch_view.runtime.json_writer"] = "lib/arch_view/runtime/json_writer.lua",
      ["arch_view.runtime.module_path"] = "lib/arch_view/runtime/module_path.lua",
   },
}
