---
name: grill-with-docs
description: Use before implementing any non-trivial Club Kit change — new engine feature, config/schema change, DataStore migration, or release planning. Relentlessly interviews the user round-by-round until every branch of the design tree is resolved, updating CONTEXT.md and docs/adr inline. Trigger on "grill me", "let's plan X", feature requests with fuzzy requirements, or any change touching buyer-owned files or versioned DataStore keys.
---

# Grill With Docs

Adapted from mattpocock/skills (`grilling` + `domain-modeling`). Two jobs in one session: reach shared understanding with the user, and sharpen the project's domain docs as decisions crystallize.

## Part 1 — The interview

Interview the user until shared understanding. Map the work as a **design tree**: every decision branches into decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are settled — questions you can ask now without guessing. Ask the whole frontier in one round: number each question, give your recommended answer. Wait for answers before the next round.

```
❓ **Q1** - **<title>**: <question body, with choices if applicable>

➡️ <your recommended answer>
```

Each answered round reshapes the tree: settled decisions push the frontier outward. A question whose answer depends on one still open belongs to a later round.

**Finding facts is your job, never the user's.** When a frontier question needs a fact from the codebase (does module X already do Y? what does the schema say?), look it up yourself or dispatch a sub-agent — don't ask the user for anything you could read. Decisions are the user's; facts are yours.

Done when the frontier is empty: every branch visited, nothing silently assumed. Do not implement until the user confirms shared understanding.

## Part 2 — Docs side effects (inline, not batched)

As decisions crystallize, update the domain docs **in the same turn**:

- **Term resolved or sharpened?** Update [`CONTEXT.md`](../../../CONTEXT.md) immediately. Glossary only — no implementation details. Create lazily if missing.
- **Hard-to-reverse decision with real trade-offs?** Offer an ADR in `docs/adr/` (format: number-title, Status / Context / Decision / Consequences). Only when all three hold: hard to reverse, surprising without context, genuine alternatives existed. Skip ephemeral reasons.
- **User says something that contradicts the glossary or the code?** Call it out immediately: "CONTEXT.md defines X as ..., but you seem to mean ... — which is it?"

## Club Kit watch-items (always on the frontier when relevant)

- **Buyer-owned files** — does this change touch `ClubKitConfig.luau` or `Secrets.luau`? If it adds config keys, the plan must include schema + template updates (fill-forward handles the rest — see ADR 0001).
- **DataStore keys** — versioned. Any migration is breaking for existing buyers; pin the migration story before implementation.
- **Register budget** — if the change touches `Main.server`/`Main.client` or a fat UI binder, ask where the code lives (Init bag vs new top-level locals) before writing it — see ADR 0002.
- **Release surface** — engine (source sync) vs StarterGui/Workspace/ServerStorage (manual/RBXM). Which surface does this change ship on?
