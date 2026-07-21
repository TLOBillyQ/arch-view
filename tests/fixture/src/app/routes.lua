-- src.app.routes: fixed fixture module for arch_view golden-output tests.
local http = require("src.net.http")
local commands = require("src.app.commands")

local M = {}

function M.id()
  return "src.app.routes"
end

return M
