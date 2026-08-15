---
name: diagnosing-bugs
description: Use when the user reports something broken, throwing, failing, or slow in the kit — Studio-vs-production discrepancies, DataStore bugs, replication issues, fill-forward not applying, UI not showing. Disciplined diagnosis loop that builds a red-capable feedback loop BEFORE hypothesizing. Trigger on "debug", "diagnose", "doesn't work", "works in Studio but...", bug reports.
---

# Diagnosing Bugs

Adapted from mattpocock/skills. Skip phases only when explicitly justified.

**Secrets hygiene:** the kit has `Secrets.luau` and buyers have live tokens. When showing commands, outputs, or captured logs, write `<REDACTED>` for every secret. Never paste Secrets contents into chat, tests, or artifacts.

## Phase 1 — Build a feedback loop (THE skill)

No tight pass/fail signal that goes red on *this* bug = no progress. Spend disproportionate effort here.

Roblox-flavored loop options, roughly in order:

1. **Headless Luau script** — pure logic (config merge, schema validation, key versioning, formatters): extract the module, drive it with a script. If no Luau runtime is installed, a minimal throwaway harness that stubs Roblox APIs still beats staring at code.
2. **Studio playtest with captured Output** — run the exact scenario in Play Solo / Start Server+Players, capture the console output, assert on the specific error line or missing value.
3. **Replay a captured artifact** — save the real payload (DataStore value dump, RemoteEvent args logged at the boundary, buyer's ClubKitConfig) to disk; replay through the code path in isolation.
4. **Differential loop** — same input through old version vs new version of a module; diff outputs. Strong for "broke after update X.Y" reports.
5. **Buyer-config matrix** — bug involves config? Loop over: default template, buyer-merged config, config with missing keys (fill-forward path).
6. **HITL script** — last resort: if a human must click in a live place, write the exact numbered steps for them and capture what they report back. Still structured.

**Tighten the loop:** faster? sharper signal (assert the exact symptom, not "didn't crash")? more deterministic (seed RNG, pin time)?

**Non-deterministic bugs** (replication races, DataStore throttling): goal is a higher reproduction rate — loop 100×, parallelize, narrow timing windows. 50% flake is debuggable; 1% is not.

**Cannot build a loop?** Stop, say so, list what you tried. Ask the user for: access to the reproducing place, a redacted captured artifact, or permission to add temporary instrumentation. Do NOT proceed to hypothesize.

**Phase 1 done when** you can name ONE command/steps you have already run that is: red-capable (catches *this* bug, asserts the user's exact symptom), deterministic, fast, agent-runnable.

## Phase 2 — Reproduce + minimise

Run the loop, watch it go red. Confirm the failure matches what the **user** described (wrong bug = wrong fix). Then shrink to the smallest scenario that still goes red — cut inputs, callers, config, one at a time. Done when every remaining element is load-bearing.

## Phase 3 — Hypothesise

3–5 **ranked, falsifiable** hypotheses before testing any: "If <X> is the cause, then <changing Y> makes the bug disappear." No prediction = vibe, discard. Show the ranked list to the user (cheap checkpoint; they often re-rank instantly: "we just shipped a change to #3").

## Phase 4 — Instrument

One variable at a time. Targeted prints at the boundaries that distinguish hypotheses — never "log everything". Tag every debug print with a unique prefix, e.g. `[DEBUG-a4f2]`, so cleanup is one grep. Perf bugs: measure a baseline first, bisect second.

## Phase 5 — Fix + regression test

Write the regression test **before the fix**, but only at a **correct seam** — one that exercises the real bug pattern as it occurs at the call site. No correct seam = that itself is the finding (architecture prevents locking the bug down; note it for later). If a seam exists: failing test → watch it fail → fix → watch it pass → re-run the Phase 1 loop on the original scenario.

## Phase 6 — Cleanup + post-mortem

- [ ] Original repro no longer reproduces (re-run Phase 1 loop)
- [ ] Regression test passes (or missing seam documented)
- [ ] All `[DEBUG-...]` prints removed (grep the prefix)
- [ ] Throwaway harnesses deleted or moved to a clearly-marked debug location
- [ ] The correct hypothesis stated in the commit message
- [ ] Ask: what would have prevented this? If architectural, record it after the fix is in (candidate for docs/adr or an AGENTS.md rule)
