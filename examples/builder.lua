-- Knex-style query builder.
-- Run from the repo root after `make dev`:  lua5.4 examples/builder.lua

local fredy = require("fredy")

local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })

db:execute([[
    create table users (
        id integer primary key,
        name text not null,
        age integer,
        active integer default 1
    )
]])

-- insert returns the created row
local ana = db:table("users"):insert({ name = "ana", age = 28 })
print("created user #" .. ana.id)

db:table("users"):insert({ name = "bia", age = 17 })
db:table("users"):insert({ name = "carla", age = 35, active = 0 })
db:table("users"):insert({ name = "duda", age = 42 })

-- chainable filters
local adults = db:table("users"):where("age", ">=", 18):where({ active = 1 }):order_by("age", "desc"):limit(10):all()

for _, user in ipairs(adults) do
    print(("%s (%d)"):format(user.name, user.age))
end
-- duda (42)
-- ana (28)

-- aggregate, update, delete
print("active users:", db:table("users"):where({ active = 1 }):count())
db:table("users"):where("age", "<", 18):update({ active = 0 })
db:table("users"):where({ active = 0 }):delete()
print("after cleanup:", db:table("users"):count())

db:close()
