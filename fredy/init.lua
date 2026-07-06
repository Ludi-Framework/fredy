local core = require("fredy_core")

---@alias fredy.Value boolean|number|string|userdata
---@alias fredy.Row table<string, boolean|number|string>

---@class fredy.Transaction
---@field query fun(self: fredy.Transaction, sql: string, params?: fredy.Value[]): fredy.Row[]
---@field execute fun(self: fredy.Transaction, sql: string, params?: fredy.Value[]): integer

---@class fredy.Connection
---@field query fun(self: fredy.Connection, sql: string, params?: fredy.Value[]): fredy.Row[]
---@field execute fun(self: fredy.Connection, sql: string, params?: fredy.Value[]): integer
---@field transaction fun(self: fredy.Connection, callback: fun(tx: fredy.Transaction))
---@field close fun(self: fredy.Connection)

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
    return core.connect(opts)
end

return fredy
