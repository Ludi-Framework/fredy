# ADR 0002: Synchronous first, with an async-ready API

**Status:** accepted

## Context

Inside a ludi handler, a blocking database call stalls the whole Lua VM
(see ludi ADR 0004). But fredy must also work standalone — scripts, other
frameworks, REPLs — where there is no coroutine scheduler to yield to.
An API that only works inside ludi would be a mistake; so would blocking
forever.

## Decision

v1 is synchronous: every call does `block_on` on an internal tokio
runtime. The API is deliberately shaped so that nothing changes when the
async integration arrives: `db:query(...)` returns rows directly today
(blocking) and will suspend the calling coroutine tomorrow (yield →
future → resume via ludi's dispatcher). No callbacks, no promise objects,
no `:await()` — those would freeze blocking semantics into the API
surface.

sqlx is async internally from day one precisely so the `block_on` is a
removable shell, not an architecture.

## Alternatives considered

- **Async-only, ludi-required** — rejected: kills standalone use.
- **Callback/promise API** — rejected: alien to the direct style, and
  unnecessary once coroutines carry the suspension.
- **Blocking C drivers** (no tokio) — rejected: would require a rewrite,
  not a swap, to ever go async.

## Consequences

- v1 blocks the VM on every call; documented, acceptable for scripts and
  moderate loads.
- When running inside ludi, a future release detects the scheduler and
  yields instead of blocking — zero API change for applications.
- Large result sets need a streaming cursor (`db:each(...)`) to keep
  memory constant; planned, same sync-now/async-later rule applies.
