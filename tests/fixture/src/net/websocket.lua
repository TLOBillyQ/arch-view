-- src.net.websocket: fixed fixture module for arch_view golden-output tests.
local codec = require("src.net.codec")
local events = require("src.core.events")

local M = {}

function M.id()
  return "src.net.websocket"
end

return M
