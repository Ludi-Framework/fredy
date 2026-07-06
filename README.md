# Fredy

A database library for Lua, powered by Rust. PostgreSQL and SQLite today;
MySQL and more planned. Companion project of the
[Ludi](https://github.com/Ludi-Framework/ludi) web framework — but works
anywhere Lua runs.

```lua
local fredy = require("fredy")

local db = fredy.connect({ adapter = "sqlite", path = "app.db" })

db:execute("insert into eggs (label, weight) values (?, ?)", { "brown", 52.5 })

local rows = db:query("select * from eggs where weight > ?", { 50 })
for _, egg in ipairs(rows) do
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

Prebuilt binary rocks are published for Linux and macOS (Lua 5.4 and
LuaJIT). On other platforms LuaRocks builds from source, which requires
[Rust](https://rustup.rs).

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

### Queries

```lua
local rows = db:query("select * from users where age > $1", { 18 })  -- postgres
local rows = db:query("select * from users where age > ?", { 18 })   -- sqlite
```

Placeholders follow the database's native syntax. `query` returns a list
of row tables; `execute` returns the number of affected rows.

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

## Roadmap

1. ✅ Core: connect, query, execute, transactions, pooling
2. Streaming cursor (`db:each(...)`) for constant-memory result sets
3. Query builder and models (pure Lua)
4. Migrations (`fredy-migrate` CLI, SQL files, `_fredy_migrations` table)
5. Async integration with ludi (handlers suspend instead of blocking)
6. MySQL adapter

Design decisions are recorded in [docs/adr/](docs/adr/).

## Development

```bash
make dev              # build the native module for Lua 5.4
make dev LUA=luajit   # ... or LuaJIT
make test             # cargo test + busted
```

Lua specs run against real in-memory SQLite through the native module,
so `make dev` must run before `busted`.

## License

MIT
