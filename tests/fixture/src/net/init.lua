-- src.net.init: fixed fixture module for arch_view golden-output tests.
local client = require("src.net.client")
local http = require("src.net.http")

local M = {}

function M.id()
  return "src.net.init"
end

return M
