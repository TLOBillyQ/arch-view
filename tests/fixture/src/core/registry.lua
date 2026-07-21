-- src.core.registry: fixed fixture module for arch_view golden-output tests.
local config = require("src.core.config")
local tables = require("src.util.tables")

local M = {}

function M.id()
  return "src.core.registry"
end

return M
