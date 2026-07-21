-- src.store.init: fixed fixture module for arch_view golden-output tests.
local db = require("src.store.db")
local query = require("src.store.query")

local M = {}

function M.id()
  return "src.store.init"
end

return M
