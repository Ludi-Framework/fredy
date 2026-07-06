--- Lua-side connection wrapper around the native core. Owns everything
--- users touch, so the Rust surface can stay minimal and the async
--- integration can later swap the internals without any API change.

local Builder = require("fredy.builder")

---@alias fredy.Value boolean|number|string|userdata
---@alias fredy.Row table<string, boolean|number|string>

---@class fredy.Transaction
---@field query fun(self: fredy.Transaction, sql: string, params?: fredy.Value[]): fredy.Row[]
---@field execute fun(self: fredy.Transaction, sql: string, params?: fredy.Value[]): integer

---@class fredy.PoolStatus
---@field size integer  connections currently open
---@field idle integer  connections open and unused

--- The native module's connection userdata (implemented in Rust).
---@class fredy.CoreConnection
---@field query fun(self: fredy.CoreConnection, sql: string, params?: fredy.Value[]): fredy.Row[]
---@field execute fun(self: fredy.CoreConnection, sql: string, params?: fredy.Value[]): integer
---@field transaction fun(self: fredy.CoreConnection, callback: fun(tx: fredy.Transaction))
---@field adapter fun(self: fredy.CoreConnection): string
---@field pool_status fun(self: fredy.CoreConnection): fredy.PoolStatus
---@field close fun(self: fredy.CoreConnection)

---@class fredy.Connection
---@field private _core fredy.CoreConnection
local Connection = {}
Connection.__index = Connection

function Connection.new(core_connection)
    return setmetatable({ _core = core_connection }, Connection)
end

--- Runs raw SQL and returns the rows. Placeholders use the database's
--- native syntax ($1 for postgres, ? for sqlite).
---@param sql string
---@param params? fredy.Value[]
---@return fredy.Row[]
function Connection:query(sql, params)
    return self._core:query(sql, params)
end

--- Runs raw SQL and returns the affected row count.
---@param sql string
---@param params? fredy.Value[]
---@return integer
function Connection:execute(sql, params)
    return self._core:execute(sql, params)
end

--- Commits when the callback returns, rolls back (and re-raises) when
--- it errors.
---@param callback fun(tx: fredy.Transaction)
function Connection:transaction(callback)
    return self._core:transaction(callback)
end

--- Starts a knex-style query builder for a table. See fredy/builder.lua
--- (or the README "Typed rows" section) for per-table typed builders.
---@param table_name string
---@return fredy.Builder
function Connection:table(table_name)
    return Builder.new(self, table_name)
end

---@return '"postgres"'|'"sqlite"'
function Connection:adapter()
    return self._core:adapter()
end

---@return fredy.PoolStatus
function Connection:pool_status()
    return self._core:pool_status()
end

function Connection:close()
    return self._core:close()
end

return Connection
