-- src.net.codec: fixed fixture module for arch_view golden-output tests.
local cjson = require("cjson")
local strings = require("src.util.strings")

local M = {}

function M.id()
  return "src.net.codec"
end

return M
