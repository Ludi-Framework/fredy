local helper = require("spec.helper")

describe("builder", function()
    local db

    before_each(function()
        db = helper.open_db()
        db:execute([[
            create table eggs (
                id integer primary key,
                label text not null,
                weight real,
                fresh integer default 1
            )
        ]])
    end)

    after_each(function()
        db:close()
    end)

    local function seed()
        db:table("eggs"):insert({ label = "small", weight = 40 })
        db:table("eggs"):insert({ label = "medium", weight = 55 })
        db:table("eggs"):insert({ label = "big", weight = 70, fresh = 0 })
    end

    it("insert returns the created row with generated id", function()
        local egg = db:table("eggs"):insert({ label = "first", weight = 50 })

        assert.are.equal(1, egg.id)
        assert.are.equal("first", egg.label)
        assert.are.equal(50.0, egg.weight)
        assert.are.equal(1, egg.fresh) -- column default applied
    end)

    it("where with an equality map", function()
        seed()

        local rows = db:table("eggs"):where({ fresh = 1 }):all()

        assert.are.equal(2, #rows)
    end)

    it("where with column, operator, value", function()
        seed()

        local rows = db:table("eggs"):where("weight", ">", 50):all()

        assert.are.equal(2, #rows)
    end)

    it("where with column, value defaults to equality", function()
        seed()

        local row = db:table("eggs"):where("label", "big"):first()

        assert.are.equal(70.0, row.weight)
    end)

    it("chained wheres combine with AND", function()
        seed()

        local rows = db:table("eggs"):where("weight", ">", 50):where({ fresh = 1 }):all()

        assert.are.equal(1, #rows)
        assert.are.equal("medium", rows[1].label)
    end)

    it("where in expands the list", function()
        seed()

        local rows = db:table("eggs"):where("label", "in", { "small", "big" }):order_by("label"):all()

        assert.are.equal(2, #rows)
        assert.are.equal("big", rows[1].label)
        assert.are.equal("small", rows[2].label)
    end)

    it("where_raw takes free-form fragments", function()
        seed()

        local rows = db:table("eggs"):where_raw("(weight < ? or weight > ?)", { 45, 65 }):all()

        assert.are.equal(2, #rows)
    end)

    it("select, order_by, limit and offset", function()
        seed()

        local rows = db:table("eggs"):select({ "label" }):order_by("weight", "desc"):limit(2):offset(1):all()

        assert.are.equal(2, #rows)
        assert.are.equal("medium", rows[1].label)
        assert.is_nil(rows[1].weight) -- not selected
    end)

    it("first returns one row or nil", function()
        seed()

        assert.are.equal("small", db:table("eggs"):order_by("weight"):first().label)
        assert.is_nil(db:table("eggs"):where("weight", ">", 999):first())
    end)

    it("count respects wheres", function()
        seed()

        assert.are.equal(3, db:table("eggs"):count())
        assert.are.equal(2, db:table("eggs"):where("weight", ">", 50):count())
    end)

    it("update returns the affected count and applies wheres", function()
        seed()

        local affected = db:table("eggs"):where("weight", ">", 50):update({ fresh = 0 })

        assert.are.equal(2, affected)
        -- medium and big now 0; small untouched
        assert.are.equal(2, db:table("eggs"):where({ fresh = 0 }):count())
        assert.are.equal(1, db:table("eggs"):where({ fresh = 1 }):count())
    end)

    it("update without where hits the whole table", function()
        seed()

        assert.are.equal(3, db:table("eggs"):update({ fresh = 0 }))
    end)

    it("delete returns the affected count and applies wheres", function()
        seed()

        assert.are.equal(1, db:table("eggs"):where("label", "big"):delete())
        assert.are.equal(2, db:table("eggs"):count())
    end)

    it("rejects invalid identifiers", function()
        assert.error_matches(function()
            db:table("eggs; drop table eggs"):all()
        end, "invalid SQL identifier")

        assert.error_matches(function()
            db:table("eggs"):where("label = 'x' or 1=1", "y"):all()
        end, "invalid SQL identifier")
    end)

    it("rejects unknown operators", function()
        assert.error_matches(function()
            db:table("eggs"):where("label", "matches", "x")
        end, "unsupported operator")
    end)
end)

describe("builder placeholders", function()
    local function fake_db(adapter)
        return {
            adapter = function()
                return adapter
            end,
            captured = {},
            query = function(self, sql, params)
                self.captured = { sql = sql, params = params }
                return {}
            end,
            execute = function(self, sql, params)
                self.captured = { sql = sql, params = params }
                return 0
            end,
        }
    end

    local Builder = require("fredy.builder")

    it("numbers placeholders for postgres", function()
        local db = fake_db("postgres")
        Builder.new(db, "eggs"):where("a", 1):where("b", ">", 2):all()

        assert.are.equal('select * from "eggs" where "a" = $1 and "b" > $2', db.captured.sql)
        assert.are.same({ 1, 2 }, db.captured.params)
    end)

    it("uses ? for sqlite", function()
        local db = fake_db("sqlite")
        Builder.new(db, "eggs"):where("a", 1):where("b", ">", 2):all()

        assert.are.equal('select * from "eggs" where "a" = ? and "b" > ?', db.captured.sql)
    end)

    it("renumbers where placeholders after update sets on postgres", function()
        local db = fake_db("postgres")
        Builder.new(db, "eggs"):where("id", 7):update({ label = "x" })

        assert.are.equal('update "eggs" set "label" = $1 where "id" = $2', db.captured.sql)
        assert.are.same({ "x", 7 }, db.captured.params)
    end)
end)
