-- Busted helper (loaded before every spec, see .busted).
-- Specs exercise the real native module against in-memory SQLite, so
-- `make dev` must have been run first (fredy_core.so at the repo root).

local fredy = require("fredy")

local helper = {}

function helper.open_db()
    return fredy.connect({ adapter = "sqlite", path = ":memory:" })
end

return helper
