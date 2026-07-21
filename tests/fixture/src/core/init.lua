-- src.core.init: fixed fixture module for arch_view golden-output tests.
local config = require("src.core.config")
local logger = require("src.core.logger")

local M = {}

function M.id()
  return "src.core.init"
end

return M
