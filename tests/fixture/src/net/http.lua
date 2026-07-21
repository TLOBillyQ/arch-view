-- src.net.http: fixed fixture module for arch_view golden-output tests.
local api = require("src.net.api")
local codec = require("src.net.codec")
local logger = require("src.core.logger")

local M = {}

function M.id()
  return "src.net.http"
end

return M
