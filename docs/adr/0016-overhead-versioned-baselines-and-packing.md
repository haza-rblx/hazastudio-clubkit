# ADR 0016 — Versioned overhead baselines and per-viewer packing

Status: Accepted, 2026-09-24 — built in the P4 worktree (production hardening, plan §2 H2/H7/H3),
awaiting merge and the Studio crowd-harness measurement on THE BASIC TEST; kit unreleased.

## Context

Target since 2026-09-24: one Roblox server holds 200 players, most of them on one dance floor.
The overhead system then had three costs that grow with n²:

1. **Per-pair baselines.** `OverheadController` kept one `DeltaCompressor` key per viewer–subject
   pair (`overhead:<subject>:<viewer>`), each holding a deep copy of the last payload sent
   (`DEEP_DELTA_NESTED = true`): up to ~40,000 copies of a ~50-field payload. A lune run with
   realistic payloads measured **~160 MB** of Lua heap for the copies alone, ~11 s of work for one
   `refreshAll`, and ~70 ms for one leave (`cleanup(prefix)` scans every key).
2. **One `FireClient` per message.** Every delta to every viewer was its own engine call; a dense
   frame (200 subjects changing, 30 viewers each) is 6,000 calls.
3. **Unbounded interest.** Every player within 55 studs subscribed: ~40,000 pairs on a packed floor,
   recomputed in full every 0.5 s.

## Decision

1. **Versioned baselines** (`DeltaCompressor.createVersioned`). Each subject keeps its current
   payload, a deep-copied baseline (one per subject change, not per pair) and a version per field.
   A pair stores only the version its viewer last received (one number). `commit(subject, payload)`
   diffs once per change; `deltaFor(subject, viewer)` returns the full payload on first send /
   after `resetPair`, else the fields newer than the viewer's version (`"__NIL__"` for removals).
   Viewers one change behind share one delta table. Leaves are O(k) through a viewer index.
   Switch: `Config.NetworkPerf.OVERHEAD_BASELINE = "versions"` (`"legacy"` = the per-pair copies).
2. **Owner-only fields** (plan H1, broadcast side). `xp`, `xpProgress`, `xpNeeded` go to the
   subject every change; other viewers get them only in a full snapshot or riding along another
   changed field — their version is not advanced by an XP-only change, so the current values ride
   along later. Switch: `Config.Overhead.PERF_XP_OWNER_ONLY`.
3. **Per-viewer packing** (plan H7). A `NetworkManager` created with `packKind` sends each viewer's
   reliable messages of one flush in one `FireClient` as `{ kind = "pack", items = {...} }`, after
   the existing coalesce (H6 merge still applies). Wire rules: a viewer with one message gets it
   **unwrapped** (the pre-P4 wire); broadcasts (`all` / `allExcept`) are **ordering barriers** —
   per-viewer messages queued before a broadcast are sent before it; `list` messages expand to one
   entry per viewer (no sort + join of recipient ids). Enabled on `OverheadUpdate` and `ChatTagSync`
   only; every kit listener of those remotes unpacks with `NetworkCoalesce.forEachMessage`.
   Switch: `Config.NetworkPerf.PACK_PER_VIEWER` (+ `PACK_MESSAGE_KIND`).
4. **Bounded interest** (plan H3). `ProximityInterestService` "incremental" mode: 4 staggered
   groups, squared distances, an 8-stud grid, at most the 30 nearest viewers per subject with an
   8-stud swap margin, at most 20 new subscriptions per viewer per 0.5 s, per-player recompute on
   spawn. Switch: `Config.NetworkPerf.PROXIMITY_MODE`.

## Alternatives considered

- **Bounded LRU of per-pair copies.** Caps memory but keeps the per-pair diff CPU and still loses
  baselines (full resends) under churn.
- **Shallow copies per pair.** The nested tables (title style, layer maps, badges) are exactly the
  fields that change by replacement; shallow copies would keep the n² table count.
- **Pack everything, including broadcasts.** Turning one `FireAllClients` into n `FireClient`s
  costs more engine calls, not fewer; broadcasts stay as they are.
- **A new remote for packs.** Would need a new `EarlyRemotes` entry and a place-side listener
  change; the in-band `kind = "pack"` keeps the remote set unchanged.

## Consequences

- Memory from overhead baselines drops from O(n²) payload copies to O(n) payloads + O(pairs)
  numbers; a leave is O(k). Lune, 200 dense: heap +159 MB → +3.7 MB; refreshAll ~11 s → ~0.1 s.
- **Wire compatibility:** any script outside the kit that listens to `OverheadUpdate` or
  `ChatTagSync` sees `{ kind = "pack" }` messages whenever a viewer gets two or more in a frame.
  Kit listeners: client `OverheadController`, `AdminController`, `SettingsController`,
  `CinematicDockController`, `ChatTagStore` — all unpack. A buyer's own listener must do the same
  (or the venue sets `PACK_PER_VIEWER = false`).
- A viewer outside a subject's 30 nearest does not get that subject's overhead deltas (it keeps the
  last payload it had). The client shows at most 40 overheads anyway (H13). The `sync:` channel
  shares the set, but `SyncService` only asks whether a leader has *any* subscriber in range (it
  always has itself), so dance sync is unaffected.
- XP bars on other players' overheads refresh only when something else about them changes.
- Rollback per item is one Config line (see the P4 block after `Config.NetworkPerf`).
