-- Schema-as-code: definitions are the source of truth for columns.
-- Run from the repo root after `make dev`:  lua5.4 examples/schema.lua

local fredy = require("fredy")
local schema = require("fredy.schema")
local migrations = require("fredy.migrations")

-- in a real project each schema lives in its own file (schemas/users.lua)
local users = schema.table("users", {
    id = schema.integer({ primary = true }),
    name = schema.text({ required = true }),
    age = schema.integer({}),
    vip = schema.boolean({ default = false }),
})

local posts = schema.table("posts", {
    id = schema.integer({ primary = true }),
    user_id = schema.integer({ required = true, references = users }),
    title = schema.text({ required = true }),
})

local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })

-- schemas generate the migration DDL
migrations.run(db, {
    { name = "0001_create_users", up = users:create_sql(db:adapter()) },
    { name = "0002_create_posts", up = posts:create_sql(db:adapter()) },
})

-- db:table(schema) validates every column reference
local ana = db:table(users):insert({ name = "ana", age = 28 })
db:table(posts):insert({ user_id = ana.id, title = "hello" })

print(db:table(posts):where({ user_id = ana.id }):count()) -- 1

-- typos fail fast, before touching the database:
local ok, err = pcall(function()
    db:table(users):where("aeg", ">=", 18):all()
end)
print(ok, err) -- false  ...column "aeg" does not exist in schema "users"

db:close()
