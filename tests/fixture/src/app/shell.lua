-- src.app.shell: fixed fixture module for arch_view golden-output tests.
local commands = require("src.app.commands")
local logger = require("src.core.logger")

local M = {}

function M.id()
  return "src.app.shell"
end

return M
