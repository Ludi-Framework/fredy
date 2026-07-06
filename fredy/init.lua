local core = require("fredy_core")
local Connection = require("fredy.connection")

---@class fredy.ConnectOptions
---@field adapter '"postgres"'|'"sqlite"'
---@field url? string             postgres only, e.g. "postgres://user:pass@host/db"
---@field path? string            sqlite only, file path or ":memory:"
---@field max_connections? integer pool size, default 5 (1 for in-memory sqlite)

local fredy = {}

--- Sentinel for SQL NULL in parameter lists (a plain nil vanishes from
--- Lua tables). Reads come back as plain nil.
---@type userdata
fredy.NULL = core.NULL

--- Opens a connection pool.
---
--- ```lua
--- local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })
--- local db = fredy.connect({ adapter = "postgres", url = os.getenv("DATABASE_URL") })
--- ```
---@param opts fredy.ConnectOptions
---@return fredy.Connection
function fredy.connect(opts)
    return Connection.new(core.connect(opts))
end

return fredy
