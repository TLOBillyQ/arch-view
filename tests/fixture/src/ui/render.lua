-- src.ui.render: fixed fixture module for arch_view golden-output tests.
local widget = require("src.ui.widget")
local panel = require("src.ui.panel")
local logger = require("src.core.logger")

local M = {}

function M.id()
  return "src.ui.render"
end

return M
