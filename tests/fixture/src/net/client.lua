-- src.net.client: fixed fixture module for arch_view golden-output tests.
local http = require("src.net.http")
local config = require("src.core.config")

local M = {}

function M.id()
  return "src.net.client"
end

return M
