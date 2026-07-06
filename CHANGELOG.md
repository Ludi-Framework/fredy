# Changelog

## 0.1.1 — 2026-07-06

### Fixed

- Parameter lists with nil holes (`{ "a", nil, "b" }`) could silently
  drop parameters on some Lua builds, since `#t` is undefined on tables
  with holes. Holes are now detected deterministically on every Lua and
  rejected with a message pointing to `fredy.NULL`.

## 0.1.0 — 2026-07-06

Initial release.

- Connection pooling, raw SQL with native placeholders, transactions
  (PostgreSQL and SQLite via sqlx)
- Knex-style query builder
- Schema-as-code: column validation, DDL generation, foreign keys
- Programmatic migrations with per-migration transactions
- Typed rows via LuaCATS annotations
