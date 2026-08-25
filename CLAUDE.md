# CLAUDE.md — Hazastudio Club Kit

This repo's actual agent workflow lives in [`AGENTS.md`](AGENTS.md) and [`.mimocode/skills/`](.mimocode/skills/) — written for Cursor/Mimo, but the discipline is the user's, not tool-specific. Follow it here too, always. This file condenses the load-bearing parts so they survive context compaction without a re-read; treat `AGENTS.md` as the source of truth if anything here drifts.

## Product

Hazastudio Club Kit (Basic Club Kit) — Roblox club/venue kit sold to multiple buyers (each runs their own Studio place: KASTA, RUST, vicenorth, Atlantis, PARKLAB, …). Luau via Rojo. Active version in [`VERSION`](VERSION).

Two hard architectural rules:
- **Engine vs. buyer-owned split** — `Hazastudio_ClubKit` folders (Replicated*/Server*/StarterPlayer*) are replaced wholesale on update. `ClubKitConfig.luau` and `Secrets.luau` are **never** overwritten — reconciled by additive "fill-forward" merge (ADR 0001). Never replace these two files in a diff; new config keys go into schema + template, not by editing the buyer's file directly.
- **~200 local-register ceiling per Luau chunk** (ADR 0002). `Main.server`/`Main.client` and fat UI binders are hottest. Prefer `Client/Init/*` or `Server/Init/*` bag modules over more top-level `local X = require(...)`. Check with `.\tools\count-locals.ps1`; ≥170 top-level locals = freeze, ≥185 = blocker.

Read [`CONTEXT.md`](CONTEXT.md) when a domain term is unfamiliar; update it (and offer an ADR in `docs/adr/` when the decision is hard-to-reverse with real trade-offs) **in the same turn** a decision crystallizes — don't batch doc updates.

## Code conventions

- `--!strict` on new Luau files.
- Minimize scope — do not refactor unless requested. Match surrounding file style.
- Do not commit unless the user asks.
- Live audio instances (`SoundEffect` on a playing `Sound`): mutate in place, never destroy/recreate — causes audible clicks. One-shot sounds are fine to churn. Setters driven by server state syncs must return early when the value is unchanged (server echoes full state, not deltas).

## Release workflow — trigger: user says "okay this is update X.Y"

1. Read old version from `VERSION` (+ `ClubKitManifest.KIT_VERSION`).
2. Collect changes from `UPGRADE_PROGRESS.md` + session/conversation.
3. Move `[Unreleased]` in `CHANGELOG.md` → `[X.Y.Z]` + today's date.
4. Create `docs/releases/<X.Y.Z>/` with `UPGRADE.md` (buyer guide) and `CHANGED_FILES.md` (Replace / Buyer-owned / Optional).
5. Bump version in `VERSION`, `KitProduct.luau` (`KitVersion`), `ClubKitManifest.luau` (`KIT_VERSION`) — all three, always in sync.
6. Reset `UPGRADE_PROGRESS.md` (clear unreleased entries, keep template).
7. Summarize for the user: new version, breaking changes, buyer files to review manually.

During normal development (not a release): add entries under `[Unreleased]` in `CHANGELOG.md`, update `UPGRADE_PROGRESS.md`'s file table. **Never bump `VERSION` until the user explicitly confirms release.** Daily releases are source-sync only (`.\tools\release.ps1 -Execute`); RBXM export is rare (fresh installs / GUI-only changes).

## Skill workflows to follow (from `.mimocode/skills/`)

These aren't in my Skill tool registry (that's Mimo's format), so I can't invoke them mechanically — but I should follow the same procedures by reading the file when the trigger applies, since this is the user's standing workflow, not a tool preference.

- **Before any non-trivial change** (new feature, config/schema change, DataStore migration, release planning) → [`grill-with-docs`](.mimocode/skills/grill-with-docs/SKILL.md): interview round-by-round until the design tree's frontier is empty, look up facts myself rather than asking the user, update `CONTEXT.md`/ADRs inline as decisions land. Don't implement until shared understanding is confirmed. Always check: does this touch buyer-owned files, DataStore keys, the register budget, or which release surface (engine vs. manual/RBXM)?
- **Bug reports / "doesn't work" / Studio-vs-production discrepancies** → [`diagnosing-bugs`](.mimocode/skills/diagnosing-bugs/SKILL.md): build a red-capable feedback loop *before* hypothesizing, reproduce and minimize, rank 3–5 falsifiable hypotheses, instrument one variable at a time, write the regression test before the fix, clean up debug prints/harnesses after. Never paste `Secrets.luau` contents — redact.
- **Review before a release / on request** → [`code-review`](.mimocode/skills/code-review/SKILL.md): two independent axes, Standards (AGENTS.md conventions, register budget, buyer-file/DataStore-key violations) vs. Spec (`UPGRADE_PROGRESS.md` + `CHANGELOG.md [Unreleased]`), reported separately, never merged. Any hard Standards violation blocks release.
- **New pure Luau logic in `Shared/`** (config merge, schema validation, key versioning, leaderboard math, formatters) → [`tdd-luau`](.mimocode/skills/tdd-luau/SKILL.md): red-green at pre-agreed public-interface seams, one seam/test/implementation at a time, independent expected values (not tautological), harnesses in `.tmp/` not `src/`.
- **Any live-Studio work via MCP** → [`mcp-studio`](.mimocode/skills/mcp-studio/SKILL.md) documents a *different* bridge (`@chrrxs/robloxstudio-mcp` on port 58741, driven by Cursor). My session's MCP servers (`Roblox_Studio`, `robloxstudio`) are a separate transport — don't assume its 14 hard-won footguns (dirty-flag on `.Source`, PowerShell `\n` escaping, playtest cloning stale config, etc.) apply unchanged. Treat that list as hypotheses to verify against my own tools, not facts to inherit; but the *shape* of the risks (persistent-vs-runtime edits, playtest snapshot staleness, save/publish being manual) is worth checking for on any bridge before trusting an edit stuck.

## Sensitive areas

- `Config.luau` (shared constants) vs. `ClubKitConfig.luau` (buyer's copy) — don't conflate.
- `Secrets.luau` — never expose to client, never paste contents anywhere.
- DataStore keys are versioned — any key change is a breaking migration, must be deliberate and documented.
