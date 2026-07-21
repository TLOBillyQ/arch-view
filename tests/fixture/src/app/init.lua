-- src.app.init: fixed fixture module for arch_view golden-output tests.
local main = require("src.app.main")
local bootstrap = require("src.app.bootstrap")

local M = {}

function M.id()
  return "src.app.init"
end

return M
