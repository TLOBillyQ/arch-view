-- src.core.events: fixed fixture module for arch_view golden-output tests.
local errors = require("src.core.errors")
local fun = require("src.util.fun")

local M = {}

function M.id()
  return "src.core.events"
end

return M
