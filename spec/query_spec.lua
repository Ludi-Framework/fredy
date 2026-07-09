local fredy = require("fredy")
local helper = require("spec.helper")

describe("query", function()
    local db

    before_each(function()
        db = helper.open_db()
        -- note: declare flags as integer, not boolean — sqlx's Any driver
        -- does not map SQLite BOOLEAN columns (README documents this)
        db:execute([[
            create table eggs (
                id integer primary key,
                label text not null,
                weight real,
                fresh integer,
                notes text
            )
        ]])
    end)

    after_each(function()
        db:close()
    end)

    it("inserts with parameters and reads rows back", function()
        local affected = db:execute("insert into eggs (label, weight, fresh) values (?, ?, ?)", { "brown", 52.5, true })

        assert.are.equal(1, affected)

        local rows = db:query("select * from eggs")

        assert.are.equal(1, #rows)
        assert.are.equal("brown", rows[1].label)
        assert.are.equal(52.5, rows[1].weight)
        assert.are.equal(1, rows[1].fresh) -- SQLite stores booleans as 0/1
    end)

    it("filters with parameters", function()
        db:execute("insert into eggs (label, weight) values (?, ?)", { "a", 10 })
        db:execute("insert into eggs (label, weight) values (?, ?)", { "b", 90 })

        local rows = db:query("select label from eggs where weight > ?", { 50 })

        assert.are.equal(1, #rows)
        assert.are.equal("b", rows[1].label)
    end)

    it("roundtrips value types", function()
        db:execute("insert into eggs (label, weight, fresh) values (?, ?, ?)", { "unicode áçê 🥚", -12.75, false })

        local row = db:query("select * from eggs")[1]

        assert.are.equal("unicode áçê 🥚", row.label)
        assert.are.equal(-12.75, row.weight)
        assert.are.equal(0, row.fresh)
        assert.are.equal("number", math.type and "number" or type(row.id))
        assert.are.equal(1, row.id)
    end)

    it("returns multiple rows in order", function()
        for i = 1, 5 do
            db:execute("insert into eggs (label) values (?)", { "egg" .. i })
        end

        local rows = db:query("select label from eggs order by id")

        assert.are.equal(5, #rows)
        assert.are.equal("egg1", rows[1].label)
        assert.are.equal("egg5", rows[5].label)
    end)

    it("updates and deletes report affected rows", function()
        for i = 1, 3 do
            db:execute("insert into eggs (label, fresh) values (?, ?)", { "e" .. i, 1 })
        end

        assert.are.equal(3, db:execute("update eggs set fresh = 0"))
        assert.are.equal(2, db:execute("delete from eggs where id > ?", { 1 }))
    end)

    it("writes SQL NULL via fredy.NULL and reads it back as nil", function()
        db:execute("insert into eggs (label, notes) values (?, ?)", { "x", fredy.NULL })

        local rows = db:query("select label, notes from eggs")

        assert.are.equal("x", rows[1].label)
        assert.is_nil(rows[1].notes)
    end)

    it("rejects nil parameters with a helpful message", function()
        assert.error_matches(function()
            db:execute("insert into eggs (label, notes) values (?, ?)", { "x", nil, "y" })
        end, "fredy.NULL")
    end)

    it("rejects unsupported parameter types", function()
        assert.error_matches(function()
            db:execute("insert into eggs (label) values (?)", { { nested = true } })
        end, "unsupported type")
    end)

    it("raises on invalid SQL", function()
        assert.has_error(function()
            db:query("select from from nowhere")
        end)
    end)

    it("returns an empty table when nothing matches", function()
        local rows = db:query("select * from eggs where id = ?", { 999 })

        assert.are.same({}, rows)
    end)

    it("fails after close", function()
        db:execute("insert into eggs (label) values (?)", { "x" })
        db:close()

        assert.has_error(function()
            db:query("select * from eggs")
        end)

        db = helper.open_db() -- so after_each can close something
    end)
end)

describe("connect", function()
    it("rejects unknown adapters", function()
        assert.error_matches(function()
            ---@diagnostic disable-next-line: assign-type-mismatch
            fredy.connect({ adapter = "mongo" })
        end, "unknown adapter")
    end)

    it("requires url for postgres", function()
        assert.error_matches(function()
            fredy.connect({ adapter = "postgres" })
        end, "requires 'url'")
    end)

    it("requires path for sqlite", function()
        assert.error_matches(function()
            fredy.connect({ adapter = "sqlite" })
        end, "requires 'path'")
    end)
end)
