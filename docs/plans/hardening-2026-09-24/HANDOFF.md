# Production hardening — session handoff (keep current; commit after every milestone)

Purpose: a fresh session (any agent) must be able to continue from here without the chat history.
The **status board in `../production-hardening-2026-09-24.md` §0** is the source of truth for phase
state; this file holds the operational context around it. Update both together.

## Where things are (last updated 2026-09-24, after P1 sync)

| Item | State |
|---|---|
| P0 VPS safety | deployed 07:26 UTC (`p0-deploy-steps.md`) |
| P2 VPS routes | deployed 09:45 UTC (`p2-deploy-steps.md`); rate limits in log mode; prod migrations 0023/0025/0026/0027 — **never ship 0024 / `license-routes.js`** |
| P1 kit | commit `55bdbf4`; synced to **THE BASIC TEST 1.3** (placeId 75916114543452), owner pressed Ctrl+S; solo playtest clean; 48 h soak running |
| P3 kit (write + HTTP discipline) | agent working **in the main working tree** (uncommitted files under `Shared/Domain/*Policy*`, `Server/Net/BackendClient.luau`, `PlayerLookupBatcher.luau`, …). Scope + ownership: §"Agent briefs" below |
| P4 kit (perf at 200) | agent working in git worktree `.claude/worktrees/agent-*` on branch `worktree-agent-*` (see `git worktree list`); commits there; **to be merged into `ui-motion` by the orchestrator** |
| P5 | not started (after ≥ 95 % of games run a P3 kit) |
| Owner-side open | Google Drive rclone auth (postponed by owner); secret rotation after P5; `GAME_RATE_LIMIT_MODE`/`IP_RATE_LIMIT_MODE`/`WEBHOOK_RATE_LIMIT_MODE` → `enforce` after ~7 days of clean journal |

## How to resume cold

1. `git status` + `git worktree list`. Uncommitted files in the main tree belong to P3; the worktree
   belongs to P4. If an agent died mid-way, read its row in `UPGRADE_PROGRESS.md` and the plan §0 row,
   then either re-launch the brief below (an agent picks up from the working tree) or finish by hand.
2. Verify locally before any sync: `lune run .tmp/compile-dir.luau src` (0 failed),
   `for f in .tmp/*-spec.luau; do lune run $f; done` (all green; `.tmp/` is gitignored — specs live
   only on this machine, re-create from the P1/P3/P4 rows if missing),
   `powershell -NoProfile -File tools/count-locals.ps1` (Main.server < 170, Main.client < 170).
3. Sync to THE BASIC TEST: start `tools/ClubKitPackagerPlugin/dev-serve.ps1 -Port 8798`, export HEAD
   copies (`git show HEAD:<path> > .tmp/head-sync/<path>`), run `tools/SyncFromDevServe.editmode.luau`
   in MODE `check` (expect SAME, or DIFF only where the place lags HEAD), then MODE `sync`. Owner must
   Ctrl+S afterwards.
4. Playtest: `solo_playtest start play`, read `get_runtime_logs` (filter `[ERROR]`, `budget `), and the
   Studio Output via the *other* MCP server (`Roblox_Studio get_console_output`) after stop — the
   runtime-log buffer is dropped when the playtest stops. Stop can exceed the 40 s tool timeout
   (BindToClose wait): poll `status`, do not retry stop.
5. Update plan §0 + `UPGRADE_PROGRESS.md` + this file, then `git commit` (owner asked for periodic
   checkpoints so a lost session can be continued).

## Merge protocol for P3 ∥ P4

- Both may add blocks to `Shared/Constants/Config.luau`, `Server/Main.server.luau`,
  `Server/Init/ServerModuleBag.luau`, `CHANGELOG.md`, `UPGRADE_PROGRESS.md`, `CONTEXT.md`, plan §0.
  They were told to keep each edit one contiguous block in NEW named Config blocks, so conflicts
  should be textual only. Resolve by keeping both blocks; never drop a switch.
- Order: commit P3 in the main tree first (review diff, specs, compile, locals), then
  `git merge worktree-agent-<id>` (P4), resolve, re-run compile/specs/locals, sync, playtest, then run
  the P4 crowd harness (`.tmp/README-crowd-harness.md` in the worktree — copy it to the main `.tmp/`).
- File ownership (do not cross): P3 = Repositories, DonationService, OverheadService,
  ProfileSocialService, JoinCommunityMembersService, EventBoardProvider, MusicLibraryProvider,
  LevelService/LevelController, EventBoard/Shop/Donation controllers, `Server/Net/*`,
  CrossServerCache/PlayerSessionStore/BudgetGate/DataStoreScheduler/BudgetMeter.
  P4 = OverheadController, ProximityInterestService, MovementGuard, NetworkManager/NetworkCoalesce/
  NetworkFlushScheduler/DeltaCompressor, everything under `StarterPlayerScripts`.

## Agent briefs (re-launch text, condensed)

**P3:** implement plan §2 A + B + C behind Config switches with legacy reachable (`WRITE_POLICY =
"legacy"`, `BACKEND_CLIENT = false`); secrets only in `Authorization: Bearer`; use the live P2 routes
(`players/lookup` ≤ 50 ids, `has_commands`, honour 429 `retry_after`); XP flush 90 s (K1); ReliabilityV2
batching then default ON (K7); stagger the 120 s venue flush; cache the VPS 403 "groups endpoint not
enabled" per server; keep `BudgetMeter.recordHttp` counting; TDD in `.tmp/`; no Studio MCP; no commit;
docs in the same turn; final report = changes per workstream + switches, spec/compile/locals, sync file
list, contradictions, ≤ 4 owner decisions, merge notes.

**P4:** synthetic-crowd harness first (`.tmp/`, one `eval_server_runtime` call returns JSON), then H
items in plan order (H1 → H6/H7 → H2/H3 → H12/H13 → rest; H6 done in P1) behind `Config.NetworkPerf.*` /
`Config.Overhead.*` switches; MovementGuard window 2 s (K8); **no RBXM/StarterGui changes** (K9, P4b
only after measuring); strong tables + `Destroying` for Instance keys; TDD + lune benchmarks; commits on
the worktree branch; no Studio MCP; final report = commits, per-H changes + switches, benchmark
before/after, harness snippet, sync list (client/server), contradictions, ≤ 4 owner decisions, merge
notes.

## Standing constraints (from the owner)

Never paste `Secrets.luau` or any secret value (lengths only); never overwrite buyer-owned
`ClubKitConfig.luau` / `Secrets.luau` (schema + template only); DataStore keys versioned + documented;
never bump `VERSION` without the owner saying "this is update X.Y"; VPS deploys diff + backup first;
owner presses Ctrl+S; Google Drive backup postponed; secret rotation after P5.
