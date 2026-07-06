--- Knex-style query builder. Entry point: db:table("users").
---
--- ```lua
--- db:table("users")
---   :where({ active = true })
---   :where("age", ">", 18)
---   :order_by("name")
---   :limit(10)
---   :all()
---
--- db:table("users"):insert({ name = "x" })                 -- returns the row
--- db:table("users"):where({ id = 1 }):update({ age = 30 }) -- affected count
--- db:table("users"):where({ id = 1 }):delete()             -- affected count
--- ```

--- For typed rows, declare a builder subclass per table overriding the
--- fetch methods (chainable methods return `self`, so the type survives
--- the whole chain):
---
--- ```lua
--- ---@class User
--- ---@field id integer
--- ---@field name string
---
--- ---@class UserBuilder: fredy.Builder
--- ---@field all fun(self: UserBuilder): User[]
--- ---@field first fun(self: UserBuilder): User?
--- ---@field insert fun(self: UserBuilder, attrs: table): User
---
--- ---@return UserBuilder
--- local function Users() return db:table("users") --[[@as UserBuilder]] end
---
--- Users():where("id", 1):first()  -- typed as User?
--- ```
---@class fredy.Builder
---@field private _db fredy.Connection
---@field private _table string
---@field private _postgres boolean
---@field private _columns string
---@field private _wheres string[]
---@field private _params fredy.Value[]
---@field private _order string[]
---@field private _limit integer?
---@field private _offset integer?
local Builder = {}
Builder.__index = Builder

local OPERATORS = {
    ["="] = true, ["<>"] = true, ["!="] = true,
    ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
    ["like"] = true, ["not like"] = true,
    ["in"] = true, ["not in"] = true
}

local function check_identifier(name)
    assert(type(name) == "string" and name:match("^[%a_][%w_]*$"),
           ("invalid SQL identifier: %q"):format(tostring(name)))
    return name
end

local function quote(name)
    return '"' .. check_identifier(name) .. '"'
end

function Builder.new(db, table_name)
    return setmetatable({
        _db = db,
        _table = check_identifier(table_name),
        _postgres = db:adapter() == "postgres",
        _columns = "*",
        _wheres = {},
        _params = {},
        _order = {},
        _limit = nil,
        _offset = nil
    }, Builder)
end

function Builder:_placeholder()
    if self._postgres then return "$" .. #self._params end
    return "?"
end

function Builder:_push(value)
    table.insert(self._params, value)
    return self:_placeholder()
end

---@param columns string[]
---@return self
function Builder:select(columns)
    local quoted = {}
    for _, column in ipairs(columns) do table.insert(quoted, quote(column)) end
    self._columns = table.concat(quoted, ", ")
    return self
end

--- Three forms, all combined with AND:
---   :where({ active = true, kind = "x" })  equality map
---   :where("age", ">", 18)                 column, operator, value
---   :where("name", "x")                    column = value
---@param column_or_map string|table<string, fredy.Value>
---@param op_or_value? string|fredy.Value
---@param value? fredy.Value|fredy.Value[]
---@return self
function Builder:where(column_or_map, op_or_value, value)
    if type(column_or_map) == "table" then
        for column, v in pairs(column_or_map) do
            table.insert(self._wheres, quote(column) .. " = " .. self:_push(v))
        end
        return self
    end

    local column = quote(column_or_map)
    local op
    if value == nil then
        op, value = "=", op_or_value
    else
        op = tostring(op_or_value):lower()
        assert(OPERATORS[op], ("unsupported operator: %q"):format(op))
    end

    if op == "in" or op == "not in" then
        assert(type(value) == "table" and #value > 0,
               "'" .. op .. "' requires a non-empty list")
        local placeholders = {}
        for _, item in ipairs(value) do
            table.insert(placeholders, self:_push(item))
        end
        table.insert(self._wheres, ("%s %s (%s)"):format(
                         column, op, table.concat(placeholders, ", ")))
    else
        table.insert(self._wheres, ("%s %s %s"):format(column, op, self:_push(value)))
    end

    return self
end

--- Escape hatch for anything beyond the where() forms. Always uses '?';
--- placeholders are rewritten for the adapter.
--- :where_raw("(age >= ? or vip = ?)", { 18, 1 })
---@param fragment string
---@param params? fredy.Value[]
---@return self
function Builder:where_raw(fragment, params)
    params = params or {}
    local rewritten = fragment:gsub("%?", function()
        return self:_push(table.remove(params, 1))
    end)
    table.insert(self._wheres, "(" .. rewritten .. ")")
    return self
end

---@param column string
---@param direction? '"asc"'|'"desc"'
---@return self
function Builder:order_by(column, direction)
    direction = (direction or "asc"):lower()
    assert(direction == "asc" or direction == "desc",
           "order direction must be 'asc' or 'desc'")
    table.insert(self._order, quote(column) .. " " .. direction)
    return self
end

---@param n integer
---@return self
function Builder:limit(n)
    self._limit = n
    return self
end

---@param n integer
---@return self
function Builder:offset(n)
    self._offset = n
    return self
end

function Builder:_where_clause()
    if #self._wheres == 0 then return "" end
    return " where " .. table.concat(self._wheres, " and ")
end

function Builder:_build_select(columns)
    local sql = "select " .. (columns or self._columns) .. " from " ..
                    quote(self._table) .. self:_where_clause()
    if #self._order > 0 then
        sql = sql .. " order by " .. table.concat(self._order, ", ")
    end
    if self._limit then sql = sql .. " limit " .. self._limit end
    if self._offset then sql = sql .. " offset " .. self._offset end
    return sql, self._params
end

---@return fredy.Row[]
function Builder:all()
    return self._db:query(self:_build_select())
end

---@return fredy.Row?
function Builder:first()
    self._limit = 1
    return self:all()[1]
end

---@return integer
function Builder:count()
    local sql, params = self:_build_select("count(*) as n")
    return self._db:query(sql, params)[1].n --[[@as integer]]
end

--- Inserts and returns the created row (including generated ids).
---@param attrs table<string, fredy.Value>
---@return fredy.Row
function Builder:insert(attrs)
    local columns, placeholders = {}, {}
    for column, value in pairs(attrs) do
        table.insert(columns, quote(column))
        table.insert(placeholders, self:_push(value))
    end
    assert(#columns > 0, "insert requires at least one column")

    local sql = ("insert into %s (%s) values (%s) returning *"):format(
                    quote(self._table), table.concat(columns, ", "),
                    table.concat(placeholders, ", "))

    return self._db:query(sql, self._params)[1]
end

--- Updates rows matching the where clauses; returns the affected count.
--- Without a where clause it updates the whole table.
---@param attrs table<string, fredy.Value>
---@return integer
function Builder:update(attrs)
    -- set placeholders must come before the where ones in param order,
    -- so rebuild: sets first, then existing where params
    local where_clause = self:_where_clause()
    local where_params = self._params
    self._params = {}

    local sets = {}
    for column, value in pairs(attrs) do
        table.insert(sets, quote(column) .. " = " .. self:_push(value))
    end
    assert(#sets > 0, "update requires at least one column")

    if self._postgres then
        -- renumber where placeholders after the set ones
        local offset = #self._params
        where_clause = where_clause:gsub("%$(%d+)", function(n)
            return "$" .. (tonumber(n) + offset)
        end)
    end
    for _, param in ipairs(where_params) do
        table.insert(self._params, param)
    end

    local sql = ("update %s set %s%s"):format(quote(self._table),
                                              table.concat(sets, ", "),
                                              where_clause)

    return self._db:execute(sql, self._params)
end

--- Deletes rows matching the where clauses; returns the affected count.
--- Without a where clause it deletes the whole table.
---@return integer
function Builder:delete()
    local sql = "delete from " .. quote(self._table) .. self:_where_clause()
    return self._db:execute(sql, self._params)
end

return Builder
