-- src.ui.host_bridge: fixed fixture module for arch_view golden-output tests.
-- Bridges back into app so the root view carries an intentional ui <-> app
-- cycle (app.main requires src.ui.render), exercising cycle_break edges and
-- cycle-aware layering in the golden baseline.
local shell = require("src.app.shell")

local M = {}

function M.id()
  return "src.ui.host_bridge"
end

return M
