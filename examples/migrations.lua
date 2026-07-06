-- Programmatic migrations: each entry runs once, inside a transaction,
-- tracked in the _fredy_migrations table.
-- Run from the repo root after `make dev`:  lua5.4 examples/migrations.lua

local fredy = require("fredy")
local migrations = require("fredy.migrations")

local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })

local LIST = {
    { name = "0001_create_users",
      up = [[
          create table users (
              id integer primary key,
              name text not null
          )
      ]] },
    { name = "0002_add_email", up = {
        "alter table users add column email text",
        "create index users_email on users (email)"
    } }
}

local ran = migrations.run(db, LIST)
print("applied: " .. table.concat(ran, ", "))

local status = migrations.status(db, LIST)
print(("%d applied, %d pending"):format(#status.applied, #status.pending))

-- running again is a no-op
assert(#migrations.run(db, LIST) == 0)

db:close()
