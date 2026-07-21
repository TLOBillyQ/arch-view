-- src.store.query: fixed fixture module for arch_view golden-output tests.
local iter = require("src.util.iter")
local db = require("src.store.db")

local M = {}

function M.id()
  return "src.store.query"
end

return M
