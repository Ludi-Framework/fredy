# ADR 0003: fredy.NULL sentinel for writes, plain nil for reads

**Status:** accepted

## Context

Lua tables cannot hold `nil`: `{ "a", nil, "b" }` has holes and
`#params` becomes unreliable, so a NULL parameter would silently corrupt
positional binding. Reading is the opposite case — a missing key already
reads as `nil`, which is exactly what SQL NULL means to Lua code.

## Decision

Asymmetric handling:

- **Writes (parameters):** SQL NULL must be written as the `fredy.NULL`
  sentinel. A literal `nil` in a parameter list is an error with a
  message pointing to `fredy.NULL` — never a silent hole.
- **Reads (rows):** SQL NULL columns are simply absent from the row
  table (`row.notes == nil`). No sentinel on the way out.

## Alternatives considered

- **Sentinel both ways** (Lapis' `db.NULL` style) — rejected:
  `row.x == db.NULL` checks everywhere are noise; `nil` is the natural
  Lua reading of NULL.
- **`nil` accepted in writes** — impossible to do reliably; holes make
  the parameter count ambiguous.
- **Named parameters instead of positional** — orthogonal; may come with
  the query builder, doesn't solve the literal-table case.

## Consequences

- Reads are idiomatic (`if row.deleted_at then ...`).
- The asymmetry must be documented prominently (README + error message).
- Row tables lose "column present but NULL" information; `SELECT` result
  shape must come from the query, not the row table keys.
