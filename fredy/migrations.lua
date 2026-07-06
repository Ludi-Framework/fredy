--- Programmatic migrations. Each migration is { name, up } where `up`
--- is one SQL statement or a list of statements (databases prepare one
--- statement at a time). Applied names are tracked in _fredy_migrations;
--- each migration runs inside its own transaction.
---
--- ```lua
--- migrations.run(db, {
---     { name = "0001_create_eggs", up = "create table eggs (...)" },
---     { name = "0002_add_index", up = {
---         "create index eggs_label on eggs (label)",
---         "create index eggs_weight on eggs (weight)"
---     } }
--- })
--- ```

local migrations = {}

local TRACKING_TABLE = [[
    create table if not exists _fredy_migrations (
        name text primary key,
        applied_at text not null
    )
]]

local function applied_set(db)
    db:execute(TRACKING_TABLE)
    local set = {}
    for _, row in ipairs(db:query("select name from _fredy_migrations")) do
        set[row.name] = true
    end
    return set
end

local function statements(up)
    if type(up) == "string" then return { up } end
    return up
end

---@class fredy.Migration
---@field name string
---@field up string|string[]

--- Applies pending migrations in list order. Returns the applied names.
---@param migration_list fredy.Migration[]
---@return string[]
function migrations.run(db, migration_list)
    local applied = applied_set(db)
    local ran = {}

    for _, migration in ipairs(migration_list) do
        assert(migration.name, "migration requires a name")
        assert(migration.up, "migration requires up SQL")

        if not applied[migration.name] then
            db:transaction(function(tx)
                for _, sql in ipairs(statements(migration.up)) do
                    tx:execute(sql)
                end
                tx:execute(
                    "insert into _fredy_migrations (name, applied_at) values (?, ?)",
                    { migration.name, os.date("!%Y-%m-%dT%H:%M:%SZ") })
            end)
            table.insert(ran, migration.name)
        end
    end

    return ran
end

--- Reports which migrations are applied and which are pending.
---@param migration_list fredy.Migration[]
---@return { applied: string[], pending: string[] }
function migrations.status(db, migration_list)
    local applied = applied_set(db)
    local result = { applied = {}, pending = {} }

    for _, migration in ipairs(migration_list) do
        if applied[migration.name] then
            table.insert(result.applied, migration.name)
        else
            table.insert(result.pending, migration.name)
        end
    end

    return result
end

return migrations
