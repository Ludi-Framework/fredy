# Fredy 🐀

A database library for Lua, powered by Rust. PostgreSQL and SQLite today;
MySQL and more planned. Companion project of the
[Ludi](https://github.com/Ludi-Framework/ludi) web framework — but works
anywhere Lua runs.

```lua
local fredy = require("fredy")

local db = fredy.connect({ adapter = "sqlite", path = "app.db" })

local egg = db:table("eggs"):insert({ label = "brown", weight = 52.5 })

local heavy = db:table("eggs")
    :where("weight", ">", 50)
    :order_by("weight", "desc")
    :limit(10)
    :all()

for _, egg in ipairs(heavy) do
    print(egg.label, egg.weight)
end
```

Parameterized queries, connection pooling and transactions are handled by
a native module built on [sqlx](https://github.com/launchbadge/sqlx);
everything above it is plain Lua. Full LuaCATS annotations ship with the
library, so editors with lua-language-server get autocomplete and type
checking out of the box.

## Installation

```bash
luarocks install fredy
```

Prebuilt binary rocks are published for Linux, macOS and Windows (Lua 5.4
and LuaJIT). Where no prebuilt rock matches, LuaRocks builds from source,
which requires [Rust](https://rustup.rs) — and, on Windows, **LuaRocks
3.11 or newer** (older releases can't run the Rust build backend there).

## Guide

### Connecting

```lua
local db = fredy.connect({ adapter = "postgres", url = os.getenv("DATABASE_URL") })
local db = fredy.connect({ adapter = "sqlite", path = "app.db" })
local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })
```

`connect` returns a pooled connection (default 5 connections,
`max_connections` to change; in-memory SQLite is pinned to 1 so all
queries share the same database).

### Query builder

Knex-style, chainable, adapter-aware (placeholders and quoting are
generated for the connected database):

```lua
-- insert returns the created row, including generated ids
local user = db:table("users"):insert({ name = "ana", age = 28 })

-- three where forms, combined with AND
db:table("users")
    :where({ active = 1 })                  -- equality map
    :where("age", ">=", 18)                 -- column, operator, value
    :where("name", "ana")                   -- column = value
    :order_by("age", "desc")
    :limit(10)
    :offset(20)
    :select({ "id", "name" })
    :all()                                  -- or :first(), :count()

db:table("users"):where("age", "in", { 28, 42 }):all()
db:table("users"):where_raw("(age >= ? or vip = ?)", { 18, 1 }):all()

db:table("users"):where({ id = 1 }):update({ age = 30 })  -- affected count
db:table("users"):where({ id = 1 }):delete()              -- affected count
```

Identifiers (table and column names) are validated and quoted; values
always travel as bound parameters.

### Schema as code

Define tables once; the schema becomes the source of truth for columns:

```lua
-- schemas/users.lua
local schema = require("fredy.schema")

return schema.table("users", {
    id    = schema.integer{ primary = true },
    name  = schema.text{ required = true },
    age   = schema.integer{},
    email = schema.text{ unique = true },
})
```

```lua
local users = require("schemas.users")

-- generates the DDL for migrations
migrations.run(db, {
    { name = "0001_create_users", up = users:create_sql(db:adapter()) }
})

-- db:table(schema) validates every column reference before touching
-- the database — a typo fails fast with a clear error
db:table(users):where("age", ">=", 18):all()
db:table(users):insert({ nmae = "ana" })
--> column "nmae" does not exist in schema "users"
```

Relations are declared with `references` and become foreign keys:

```lua
local posts = schema.table("posts", {
    id      = schema.integer{ primary = true },
    user_id = schema.integer{ required = true, references = users },
})
```

Column options: `primary`, `required` (NOT NULL), `unique`, `default`,
`references`. Types: `integer`, `text`, `real`, `boolean`.

### Typed rows

The LuaCATS equivalent of knex's `knex<User>('users')`: declare a row
class and a builder subclass per table. Chainable methods return `self`,
so the type survives the whole chain — editors with lua-language-server
autocomplete row fields after `:first()`, `:all()` and `:insert()`.

```lua
---@class User
---@field id integer
---@field name string
---@field age integer

---@class UserBuilder: fredy.Builder
---@field all fun(self: UserBuilder): User[]
---@field first fun(self: UserBuilder): User?
---@field insert fun(self: UserBuilder, attrs: table): User

---@return UserBuilder
local function Users() return db:table("users") --[[@as UserBuilder]] end

local user = Users():where("age", ">=", 18):first()  -- typed as User?
```

Pure annotations — zero runtime cost. See [examples/typed.lua](examples/typed.lua).

### Raw SQL

```lua
local rows = db:query("select * from users where age > $1", { 18 })  -- postgres
local rows = db:query("select * from users where age > ?", { 18 })   -- sqlite
```

Raw SQL uses each database's **native** placeholder syntax on purpose:
rewriting SQL strings is unsafe (postgres' jsonb `?` operator, `?` inside
literals), so fredy never touches your SQL. The query builder is the
portable layer. `query` returns a list of row tables; `execute` returns
the number of affected rows.

### Migrations

Ordered list, each migration applied once inside its own transaction,
tracked in `_fredy_migrations`:

```lua
local migrations = require("fredy.migrations")

migrations.run(db, {
    { name = "0001_create_users",
      up = "create table users (id integer primary key, name text not null)" },
    { name = "0002_add_email", up = {
        "alter table users add column email text",
        "create index users_email on users (email)"
    } }
})

migrations.status(db, list)  --> { applied = {...}, pending = {...} }
```

Relations are plain SQL (foreign keys in your DDL) — there is no schema
file per table. A schema-as-code layer that generates migrations is on
the roadmap.

### NULL

Parameter lists use the `fredy.NULL` sentinel for SQL NULL, because a
plain `nil` vanishes from Lua tables (passing `nil` is an error).
Reads come back as plain `nil`:

```lua
db:execute("insert into eggs (label, notes) values (?, ?)", { "x", fredy.NULL })
local row = db:query("select * from eggs")[1]
row.notes  --> nil
```

### Transactions

```lua
db:transaction(function(tx)
    tx:execute("update accounts set balance = balance - ? where id = ?", { 10, 1 })
    tx:execute("update accounts set balance = balance + ? where id = ?", { 10, 2 })
end)
```

Commits when the callback returns, rolls back (and re-raises) when it
errors.

### Type mapping

| SQL | Lua |
| --- | --- |
| integer | number (integer) |
| real / double | number (float) |
| text / varchar | string |
| boolean | boolean (Postgres); 0/1 (SQLite) |
| NULL | nil |

Caveat: declare SQLite flag columns as `integer`, not `boolean` — sqlx's
Any driver does not map SQLite's BOOLEAN type.

## Examples

Runnable scripts in [examples/](examples/): raw SQL and transactions
(`basic.lua`), the query builder (`builder.lua`) and migrations
(`migrations.lua`). From the repo root: `make dev`, then
`lua5.4 examples/builder.lua`.

## Roadmap 🐀

1. ✅ Core: connect, query, execute, transactions, pooling
2. ✅ Knex-style query builder (pure Lua)
3. ✅ Programmatic migrations
4. ✅ Schema-as-code: column validation, DDL generation, relations
5. Streaming cursor (`db:each(...)`) for constant-memory result sets
6. Schema diffing (generate alter-table migrations from schema changes)
   and LuaCATS codegen (schema → typed builder annotations)
7. Migrations CLI (`fredy-migrate`, SQL files)
8. Async integration with ludi (handlers suspend instead of blocking)
9. MySQL adapter

Design decisions are recorded in [docs/adr/](docs/adr/).

## Development

```bash
make dev              # build the native module for Lua 5.4
make dev LUA=luajit   # ... or LuaJIT
make test             # cargo test + busted
```

Lua specs run against real in-memory SQLite through the native module,
so `make dev` must run before `busted`.

On Windows, `make dev` works under Git Bash (it builds `fredy_core.dll`
and copies it into place instead of symlinking a `.so`).

## License

[MIT](LICENSE)

---

*Named after Fredy the rat 🐀 — the first rat in production, and you can
still hear him SQueaL in every query.*
