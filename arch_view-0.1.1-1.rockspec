rockspec_format = "3.0"
package = "arch_view"
version = "0.1.1-1"
source = {
   url = "git+http://lzxsvn:3000/qinyuanj/arch_view.git",
   tag = "v0.1.1",
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
   -- viewer 静态资源(index.html/script.js/styles.css)住 lua/viewer/:
   -- builtin 驱动会把仓库根 lua/ 目录整体拷进 lua_dir(<tree>/share/lua/5.4),
   -- 安装后 viewer 即 <lua_dir>/viewer,与 paths.default_asset_root() 的
   -- rock 形态定位一致(见 lib/arch_view/internal/paths.lua)。
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
