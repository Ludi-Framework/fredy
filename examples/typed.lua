-- Typed rows with LuaCATS annotations (lua-language-server).
-- Zero runtime cost: everything here is comments. Open this file in an
-- editor with lua-language-server to see completion on user.name etc.
-- Run from the repo root after `make dev`:  lua5.4 examples/typed.lua

local fredy = require("fredy")

local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })

db:execute([[
    create table users (
        id integer primary key,
        name text not null,
        age integer
    )
]])

---@class User
---@field id integer
---@field name string
---@field age integer

-- Per-table typed builder: chainable methods return `self`, so the
-- UserBuilder type survives the whole chain and the fetch methods
-- resolve to User instead of the generic row type.
---@class UserBuilder: fredy.Builder
---@field all fun(self: UserBuilder): User[]
---@field first fun(self: UserBuilder): User?
---@field insert fun(self: UserBuilder, attrs: table): User

---@return UserBuilder
local function Users()
    return db:table("users") --[[@as UserBuilder]]
end

local ana = Users():insert({ name = "ana", age = 28 })
print(ana.id, ana.name) -- editor autocompletes .id/.name/.age here

Users():insert({ name = "bia", age = 17 })

local adult = Users():where("age", ">=", 18):order_by("age"):first()
if adult then
    print("first adult: " .. adult.name)
end

db:close()
