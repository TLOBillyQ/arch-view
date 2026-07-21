-- src.store.cache: fixed fixture module for arch_view golden-output tests.
local tables = require("src.util.tables")
local codec = require("src.net.codec")

local M = {}

function M.id()
  return "src.store.cache"
end

return M
