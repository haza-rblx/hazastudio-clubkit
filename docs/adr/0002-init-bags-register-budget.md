# ADR 0002 — Init bags over top-level requires (Luau register budget)

**Status:** Accepted
**Date:** 2026-08-14

## Context

Luau crashes with `Out of local registers` when a chunk exceeds ~200 locals. `Main.server` / `Main.client` and fat UI binders naturally accumulate one top-level `local X = require(...)` per dependency, and were approaching the ceiling. Alternatives: (a) split Main into many tiny scripts (more moving parts, ordering headaches), (b) unpack dependencies lazily inside functions (scatters requires, hides dependency shape), (c) group dependencies behind one `require` that returns a table (an "Init bag").

## Decision

Group related dependencies into **Init bags** — modules under `Client/Init/*` or `Server/Init/*` that return a table of modules from a single `require`. Main scripts and fat binders consume bags; they do **not** unpack bag fields back into many top-level locals (that defeats the bag).

Thresholds, enforced by `tools/count-locals.ps1`: ≥170 top-level `local`s in a file = frozen (no new top-level locals); ≥185 = treat as blocker before merge.

## Consequences

- Main scripts stay compilable as the kit grows; dependency additions land in the bag, not Main.
- The bag interface is the seam: it shows what a subsystem depends on in one place.
- Slight indirection cost: finding a module means going through its bag. Accepted — the alternative is a hard crash.
- New fat UI binders start as bags by default rather than growing into the budget.
