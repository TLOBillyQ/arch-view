-- src.store.migrate: fixed fixture module for arch_view golden-output tests.
local db = require("src.store.db")
local config = require("src.core.config")

local M = {}

function M.id()
  return "src.store.migrate"
end

return M
