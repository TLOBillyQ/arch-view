-- src.app.main: fixed fixture module for arch_view golden-output tests.
local routes = require("src.app.routes")
local client = require("src.net.client")
local render = require("src.ui.render")

local M = {}

function M.id()
  return "src.app.main"
end

return M
