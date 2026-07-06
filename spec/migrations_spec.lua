local migrations = require("fredy.migrations")
local helper = require("spec.helper")

describe("migrations", function()
    local db

    local LIST = {
        { name = "0001_create_eggs",
          up = "create table eggs (id integer primary key, label text)" },
        { name = "0002_create_boxes", up = {
            "create table boxes (id integer primary key)",
            "create index boxes_id on boxes (id)"
        } }
    }

    before_each(function()
        db = helper.open_db()
    end)

    after_each(function()
        db:close()
    end)

    it("applies pending migrations in order", function()
        local ran = migrations.run(db, LIST)

        assert.are.same({ "0001_create_eggs", "0002_create_boxes" }, ran)
        db:execute("insert into eggs (label) values ('x')")
        db:execute("insert into boxes default values")
    end)

    it("is idempotent", function()
        migrations.run(db, LIST)
        local ran = migrations.run(db, LIST)

        assert.are.same({}, ran)
    end)

    it("reports status", function()
        migrations.run(db, { LIST[1] })

        local status = migrations.status(db, LIST)

        assert.are.same({ "0001_create_eggs" }, status.applied)
        assert.are.same({ "0002_create_boxes" }, status.pending)
    end)

    it("rolls back a failing migration without losing previous ones", function()
        local bad = {
            LIST[1],
            { name = "0002_broken", up = {
                "create table half (id integer)",
                "this is not sql"
            } }
        }

        assert.has_error(function() migrations.run(db, bad) end)

        local status = migrations.status(db, bad)
        assert.are.same({ "0001_create_eggs" }, status.applied)
        assert.are.same({ "0002_broken" }, status.pending)

        -- the partial statement of the broken migration must be gone
        assert.has_error(function() db:query("select * from half") end)
    end)

    it("requires name and up", function()
        assert.has_error(function()
            ---@diagnostic disable-next-line: missing-fields
            migrations.run(db, { { up = "create table x (id integer)" } })
        end)
        assert.has_error(function()
            ---@diagnostic disable-next-line: missing-fields
            migrations.run(db, { { name = "0001_x" } })
        end)
    end)
end)
