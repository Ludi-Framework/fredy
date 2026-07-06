# ADR 0001: Thin Rust driver on sqlx, ORM logic in Lua

**Status:** accepted

## Context

Fredy targets Lua developers (same audience and packaging model as ludi:
LuaRocks, prebuilt binary rocks, `require("fredy")`). It needs database
connectivity for PostgreSQL and SQLite now, MySQL and others later, with
an ORM layer on top.

## Decision

Split responsibilities by language:

- **Rust (`fredy_core`, mlua module mode):** connection pooling,
  parameter binding, row decoding, transactions. Built on **sqlx** with
  its `Any` driver — one code path covers PostgreSQL, SQLite and (later)
  MySQL. sqlx is a driver toolkit, not an ORM: no framework semantics
  leak into Lua.
- **Lua (`fredy/`):** everything users touch and contributors iterate
  on — query builder, models, relations, migrations.

## Alternatives considered

- **ORM in Rust** (SeaORM/diesel wrapped for Lua) — rejected: freezes
  API decisions in the slowest-to-change layer and locks out Lua
  contributors.
- **Pure Lua + C drivers** (luasql, pgmoon) — rejected: blocking-only,
  per-database code paths, no pooling; and pgmoon ties to OpenResty.
- **One crate per database** — rejected for now: sqlx `Any` covers the
  first three targets; per-database crates (Oracle, SQL Server) can join
  behind the same Lua API later.

## Consequences

- `Any` driver limitations apply: e.g. SQLite `BOOLEAN` columns are not
  mapped (use `integer` 0/1); some exotic Postgres types decode as text.
- MySQL support is mostly a feature flag away.
- Placeholders remain adapter-specific in raw SQL (`$1` postgres,
  `?` sqlite) until the query builder papers over it.
