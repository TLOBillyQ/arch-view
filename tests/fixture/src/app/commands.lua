-- src.app.commands: fixed fixture module for arch_view golden-output tests.
local query = require("src.store.query")
local strings = require("src.util.strings")

local M = {}

function M.id()
  return "src.app.commands"
end

return M
