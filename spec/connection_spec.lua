local helper = require("spec.helper")

describe("connection", function()
    local db

    before_each(function()
        db = helper.open_db()
    end)

    after_each(function()
        db:close()
    end)

    it("reports the adapter", function()
        assert.are.equal("sqlite", db:adapter())
    end)

    it("reports pool status", function()
        db:execute("select 1")

        local status = db:pool_status()

        assert.are.equal(1, status.size)  -- in-memory sqlite pins to 1
        assert.is_true(status.idle <= status.size)
    end)

    it("table() starts a builder bound to this connection", function()
        db:execute("create table eggs (id integer primary key)")
        db:execute("insert into eggs default values")

        assert.are.equal(1, db:table("eggs"):count())
    end)
end)
