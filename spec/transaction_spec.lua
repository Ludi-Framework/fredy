local helper = require("spec.helper")

describe("transaction", function()
    local db

    before_each(function()
        db = helper.open_db()
        db:execute("create table eggs (id integer primary key, label text)")
    end)

    after_each(function()
        db:close()
    end)

    it("commits when the callback succeeds", function()
        db:transaction(function(tx)
            tx:execute("insert into eggs (label) values (?)", { "a" })
            tx:execute("insert into eggs (label) values (?)", { "b" })
        end)

        local rows = db:query("select count(*) as n from eggs")
        assert.are.equal(2, rows[1].n)
    end)

    it("rolls back when the callback errors and propagates the error", function()
        assert.error_matches(function()
            db:transaction(function(tx)
                tx:execute("insert into eggs (label) values (?)", { "a" })
                error("kaboom")
            end)
        end, "kaboom")

        local rows = db:query("select count(*) as n from eggs")
        assert.are.equal(0, rows[1].n)
    end)

    it("queries inside the transaction see uncommitted writes", function()
        db:transaction(function(tx)
            tx:execute("insert into eggs (label) values (?)", { "a" })
            local rows = tx:query("select count(*) as n from eggs")
            assert.are.equal(1, rows[1].n)
        end)
    end)

    it("rejects using the tx handle after the transaction ends", function()
        local leaked
        db:transaction(function(tx)
            leaked = tx
        end)

        assert.error_matches(function()
            leaked:execute("insert into eggs (label) values (?)", { "x" })
        end, "already finished")
    end)
end)
