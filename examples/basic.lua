-- Raw SQL: parameterized queries and transactions.
-- Run from the repo root after `make dev`:  lua5.4 examples/basic.lua

local fredy = require("fredy")

local db = fredy.connect({ adapter = "sqlite", path = ":memory:" })

db:execute([[
    create table accounts (
        id integer primary key,
        owner text not null,
        balance real not null default 0
    )
]])

db:execute("insert into accounts (owner, balance) values (?, ?)", { "ana", 100 })
db:execute("insert into accounts (owner, balance) values (?, ?)", { "bia", 50 })

-- transfer inside a transaction: all or nothing
db:transaction(function(tx)
    tx:execute("update accounts set balance = balance - ? where owner = ?", { 30, "ana" })
    tx:execute("update accounts set balance = balance + ? where owner = ?", { 30, "bia" })
end)

for _, account in ipairs(db:query("select * from accounts order by owner")) do
    print(("%s: %.2f"):format(account.owner, account.balance))
end
-- ana: 70.00
-- bia: 80.00

db:close()
