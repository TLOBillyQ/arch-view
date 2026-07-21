-- src.app.bootstrap: fixed fixture module for arch_view golden-output tests.
local core = require("src.core")
local db = require("src.store.db")
local commands = require("src.app.commands")

local M = {}

function M.id()
  return "src.app.bootstrap"
end

return M
