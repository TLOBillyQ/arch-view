-- src.store.db: fixed fixture module for arch_view golden-output tests.
local tx = require("src.store.tx")
local logger = require("src.core.logger")

local M = {}

function M.id()
  return "src.store.db"
end

return M
