---
name: tdd-luau
description: Use when building or fixing pure Luau logic test-first — config fill-forward/merge, ClubKitConfigSchema validation, DataStore key versioning, leaderboard math, formatters, utils. Red-green-refactor at agreed ModuleScript seams. Trigger on "tdd", "test-first", "red-green", or when adding non-trivial pure logic to Shared/.
---

# TDD — Luau

Adapted from mattpocock/skills. The loop is red → green; this skill makes the loop produce tests worth keeping.

## What a good test is

Verifies behavior through a ModuleScript's **public interface**, not internals. Reads like a specification ("fill-forward adds missing keys without overwriting buyer values"). Survives refactors. Use CONTEXT.md vocabulary in test names.

## Seams — where tests go

A seam is a public boundary you can observe without reaching inside. For this kit, good seams are pure ModuleScripts under `Shared/` (Config, Domain, Leaderboards, Utils) — they return values, not side effects.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm with the user. Testing effort lands on critical paths (fill-forward, key versioning), not every edge case.

Bad seams here: anything requiring a running DataStore, Players service, or StarterGui — fake those at the boundary or don't unit-test them.

## Running tests (no runner is installed — pick per task)

1. **Pure-logic harness (default)** — a throwaway runner script that requires the module with stubbed Roblox globals and asserts. Keep harnesses out of `src/` (use `.tmp/`), or delete after the session per diagnosing-bugs cleanup rules.
2. **Lune** — if headless Luau is wanted longer-term, propose adding `lune` to `aftman.toml` first (user confirms; don't install unprompted).
3. **TestEZ in Studio** — only when the logic genuinely needs Roblox services.

Whichever you use: one command that runs the tests, shows red/green, in seconds.

## Anti-patterns

- **Implementation-coupled** — reaches into module internals or local helpers; breaks on refactor without behavior change.
- **Tautological** — expected value computed the same way the code does. Expected values come from an independent source: a worked example, a literal from the spec, the buyer-facing docs.
- **Horizontal slicing** — all tests first, then all implementation. Work vertical: one test → one implementation → repeat (tracer bullets).

## Rules of the loop

- **Red before green.** Failing test first, then only enough code to pass.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to code-review, not red → green.
- **Register budget applies to tests too** — fat test files hit the same ~200-local ceiling (ADR 0002). Split by seam, not by layer.
