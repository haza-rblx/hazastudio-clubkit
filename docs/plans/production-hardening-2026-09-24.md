# Production hardening — 200 players in one server (plan, 2026-09-24)

Status: **Draft for owner review.** Nothing here is built yet. Source: the audit of 2026-09-24, with every finding this plan relies on re-checked in the code (kit `src/`, infra `clubkit-infra/`). Line numbers are from the working tree on 2026-09-24.
Abbreviations: **S** = `src/ServerScriptService/Hazastudio_ClubKit/Server`, **C** = `src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client`, **Sh** = `src/ReplicatedStorage/Hazastudio_ClubKit/Shared`, **API** = `clubkit-infra/apps/api/src`.

Owner requirement: "enterprise and production grade, 200 CCU in one game; no leaks in performance, DataStore, etc.; tidy the files and names." **Target changed 2026-09-24: one Roblox server holds 200 players.** Overflow servers may exist, so everything must still be correct across servers.

## 0. Status board (keep this current — the plan must survive a lost session)

| Phase | Status | Where | Notes |
|---|---|---|---|
| P0 VPS safety | **Deployed 2026-09-24 07:26 UTC** | VPS | Steps + rollback: `hardening-2026-09-24/p0-deploy-steps.md`; rollback copies `/root/p0-rollback-20260924T072607Z`; Google Drive off-site **postponed by the owner** (backup log says `offsite: SKIPPED` until `rclone config` is done); 48 h gate started |
| P1 Kit correctness + budget telemetry | **synced to THE BASIC TEST 2026-09-24, playtest clean, 48 h soak running** (committed) | kit (THE BASIC TEST first) | Files — new: `Sh/Utils/{BoundedLru,BudgetMeter,NetworkCoalesce}.luau`, `S/Net/HttpRequest.luau`; changed: `Sh/Constants/Config.luau`, `Sh/Utils/{BudgetGate,CrossServerCache,DataStoreScheduler,NetworkManager,PlayerSessionStore}.luau`, `S/Main.server.luau`, `S/Init/{ServerModuleBag,PersistenceFabricHooks}.luau`, `S/Controllers/{EventBoardController,OverheadController,SettingsController}.luau`, `S/Repositories/{AvatarLikeRepository,GiftPendingRepository,OverheadRepository,ProfileLoader,SettingsRepository}.luau`, `S/Services/{DonationService,EventBoardProvider,JoinCommunityMembersService,MusicLibraryProvider,OverheadService,ProfileSocialService,ProximityInterestService,RoleToolService,SyncService}.luau`, `C/Controllers/AvatarContextController.luau`. Specs `.tmp/{session-store,overhead-repo-replay,gift-pending,profile-loader,datastore-scheduler,network-coalesce,budget-meter-lru}-spec.luau`. Not done here: Studio memory-gate harness + kill-tests (need TEST), budget window to the VPS (P3, `BackendClient`), stagger of the 120 s venue flush (A8). Deviations from §A: GiftPending tombstone sets `toUserId = 0` (+ `consumedToUserId`) so older kits in a mixed fleet also read it as consumed; replay uses the existing `_version` (no new `rev` field) |
| P2 VPS routes for the kit | **deployed 2026-09-24 09:45 UTC** — migration 0027 applied, health/v1/v2/v3/event-board/`players/lookup`/social all 200, `has_commands` present, no journal errors; rollback copies `/root/p2-rollback-<ts>`, DB snapshot `backups/pre-p2-<ts>.sqlite` | VPS | Steps, file list, kit API contract: `hardening-2026-09-24/p2-deploy-steps.md`; migration `0027_p2_query_indexes` (indexes only); rate limits ship in log mode; `donor_totals` table / stored `total_after` / `donor_name` alias not built (per-game cache instead) |
| P3 Write + HTTP discipline | **committed `4a80b7b`, synced to THE BASIC TEST with P4 (merge `d8c2ff9`) 2026-09-24, solo playtest clean (BackendClient/lookup batch/GlobalDocWriter/groups cache all seen in the budget line); 48 h soak running; kill-tests still open** | kit | ADR 0016. Files — new: `S/Net/{BackendClient,PlayerLookupBatcher,BudgetTelemetry}.luau`, `S/Persistence/{PlayerDocWriter,GlobalDocWriter}.luau`, `Sh/Domain/{HttpBudgetPolicy,PlayerLookupBatch,FlushPolicy,DeliveryReportQueue,GlobalDocPolicy,InvalidateBatch,LeaderboardCacheCodec}.luau`; changed: `Sh/Constants/Config.luau` (new blocks `PlayerDocWriter`, `InvalidateBus`, `VerifyCache`, `LeaderboardCacheV2`, `GlobalDocWriter`, `BackendClient`, `Telemetry`; `Donation.RELIABILITY_V2_ENABLED = true`), `Sh/Config/{ClubKitConfigSchema,ConfigBootstrap}.luau`, template `ClubKitConfig.luau` (`Telemetry.Enabled`, `ReliabilityV2` default), `Sh/Domain/EventBoardDomain.luau`, `Sh/Utils/{BudgetMeter,CrossServerCache,PlayerSessionStore}.luau`, `S/Main.server.luau`, `S/Init/{ServerModuleBag,PersistenceFabricHooks}.luau`, `S/Controllers/EventBoardController.luau`, `S/Repositories/{AvatarLikeRepository,DonationLeaderboardRepository,MusicRepository,OverheadRepository,ProgressLeaderboardRepository,SettingsRepository,VenueQuestProgressRepository}.luau`, `S/Services/{DonationService,EventBoardProvider,JoinCommunityMembersService,MusicLibraryProvider,OverheadService,ProfileSocialService}.luau`. Specs `.tmp/{http-budget-policy,player-lookup-batch,flush-policy,delivery-report-queue,global-doc-policy,invalidate-batch,leaderboard-cache-codec,event-board-prune,session-store-v2,overhead-repo-p3,backend-client,cross-server-cache-v2,budget-telemetry}-spec.luau`. Deviations from §A–C: `PlayerDocWriter` lives in `S/Persistence/` and schedules through `PlayerSessionStore` (no new `rev` field — P1's `_version` replay stays); the 90 s stagger is a fixed per-player phase (`userId % 90`); batching uses the GET `v2/players/lookup` (not a new `JoinLookupBatcher` POST) and covers only background lookups (join cash, rank resolution, connections warm) — the group rank stays per-user because the first overhead payload waits for it (a 3 s window would delay every join), made cheap by the 30-min "groups disabled" cache, per-user dedup and a 30 s failure cache; global-doc revisions ride in DataStore key metadata (no value-shape change). **Not done in P3:** community-increment aggregation (A6 — would weaken the Robux receipt's exactly-once flags; owner decision), ProfileLoader priority classes / lazy P2 kinds (A2 rest), H1 XP fan-out (P4). |
| P4 Performance at 200 | not started | kit (+RBXM if P4b) | needs the P1 NetworkManager fix + the synthetic-crowd harness |
| P4 Performance at 200 | **merged `d8c2ff9`, synced to THE BASIC TEST, measured in Studio 2026-09-24** — results `hardening-2026-09-24/p4-crowd-harness-results.md`: H1/H2/H7 met (heap 119.6→3.7 MB, XP fan-out 39,800→0, 6,000→200 FireClient); H3 2.47 ms/tick (target 1.5, storm max 285 ms), H4 9.8 ms/tick (target 0.5, raycast-bound); template 106 instances/head → **P4b decision for the owner** | kit (+RBXM if P4b) | ADR 0017 + ADR 0008 addendum. Done: H1 broadcast side (xp owner-only), H2 versioned baselines, H3 incremental proximity (30 nearest, 4 groups, 8-stud grid, enter budget 20/0.5 s, per-player spawn recompute), H4 MovementGuard slices >60 + shared RaycastParams, H7 per-viewer packing (`OverheadUpdate`, `ChatTagSync`), H8 O(1) join check + join batch skips sent pairs + settle rebuilds only when unresolved + roster catch-up dedupe, H9 chat-tag chunks of 50, H12, H13 (40 nearest, Far 90, gradient cull), H15, H16. Files — new: `C/Utils/OverheadCullBudget.luau`; changed: `Sh/Constants/Config.luau` (one P4 block after `Config.NetworkPerf`), `Sh/Domain/MovementPolicy.luau`, `Sh/Utils/{DeltaCompressor,NetworkCoalesce,NetworkManager,InterestManager}.luau`, `S/Controllers/OverheadController.luau`, `S/Services/ProximityInterestService.luau`, `S/Init/MovementGuard.luau`, `C/Controllers/{OverheadController,AdminController,SettingsController,CinematicDockController}.luau`, `C/Services/ChatTagStore.luau`, `C/UI/{OverheadUI,AdminPanelV3UI}.luau`, `C/Utils/AvatarPrewarmPool.luau`. Harness `.tmp/crowd-harness-server.luau` (+ `.tmp/perf-bench.luau`, `.tmp/README-crowd-harness.md`); specs `.tmp/{delta-baseline,network-pack,proximity-incremental,overhead-cull-budget,movement-spread}-spec.luau`. Studio numbers TODO. Not here: H10 (`DonationController`), H11, H17 (`OverheadService`), H18 (`ShopController`), H8 compact payload, H14/P4b (decide after the template count). **P4b design: `hardening-2026-09-24/p4b-overhead-template.md`** (designed 2026-09-24, not built; inventory `p4b-template-inventory.md`, ADR 0018 Proposed) |
| P5 Cut-overs | not started | VPS | after ≥95 % of active games run a P3 kit |
| G Naming cleanup | rides along | kit | |

**Parallel execution (owner, 2026-09-24):** run P1 ∥ P2, then P3 ∥ P4 with file ownership — P3 owns
`Server/Repositories/*`, `Services/DonationService`, the new `BackendClient`/`PlayerDocWriter`; P4 owns
`OverheadController`, `ProximityInterestService`, `MovementGuard`, `NetworkManager`, client overhead/avatar
modules. Both touch `Shared/Constants/Config.luau` and `Main.server.luau`: merge those hunks sequentially at
the end. One THE BASIC TEST build can soak P1+P3+P4 together.

**Resuming a lost session:** read `hardening-2026-09-24/HANDOFF.md` first (agent briefs, worktree, merge protocol, sync recipe `tools/SyncFromDevServe.editmode.luau`).

**Supporting files:** `hardening-2026-09-24/audit-findings.md` (DataStore / HTTP / VPS audit),
`hardening-2026-09-24/perf-audit-200-players.md` (server + client hotspots), `hardening-2026-09-24/p0-deploy-steps.md`.

## Corrections to the audit

- **`RequestAsync` `Timeout` is documented** (Roblox API reference, checked 2026-09-24: integer seconds, > 0, ≤ default). The finding "probably not honoured" was wrong. Keep it and pass integers.
- **Community increment** (`DonationLeaderboardRepository.luau:757-776`) is keyed per community, not one global key, and `IncrementAsync` is atomic: a throughput issue, not correctness.
- **Music duration** (`MusicService.luau:654` → `MusicRepository.luau:473-493`) merges by revision rather than rewriting blindly. It still rewrites all of `Tracks`, and in web mode it keeps web-deleted entries (`:682-683`).
- **ReliabilityV2** is off by default (`Config.luau:3041`); THE BASIC enables it. The VPS already accepts batches of 200 (`v3-routes.js:38,143-159,235-246`), so batching is a kit-only change.
- **Group lookup** has a 30 s negative cache when the Worker *and* GroupService both fail (`OverheadService.luau:292-293`). The Worker call alone has none.
- **Messaging limits in the audit are stale.** Current docs: sends 600 + 240·players/min per server; **receives 40 + 80·servers per topic and 400 + 200·servers per game**. Receiving is what binds.
- **Mixed Indonesian/English identifiers:** none found in `local`/`function` names. Indonesian appears only in strings and comments, so this is out of scope.
- **New bugs found during verification:**
  - `Init/PersistenceFabricHooks.luau:19-25` clears the session after a failed leave flush.
  - Venue progress is flushed only in `onDestroy`, which runs *after* BindToClose's 25 s wait (`EventBoardController.luau:510-512`).
  - `app.js:172` returns a poll URL containing `?secret=`.
  - The comment at `GiftPendingRepository.luau:106` wrongly says the key is deleted.

## 1. Goals, non-goals, budgets

**Goals**
1. Every Roblox budget stays at or below **50 %** at 200 players, both at steady state and during a join storm of 200 players in 180 s.
2. No player data is lost on a normal leave or shutdown. A server crash loses at most one flush interval.
3. No unbounded document, table, log or queue, in the kit or on the VPS.
4. The VPS survives a hostile client: rate limits, body caps, no secrets in logs, backups off-site.

**Non-goals**
- Renaming DataStore keys or buyer config keys. Aliases only (ADR 0001).
- Moving buyer secrets to Roblox's `HttpService:GetSecret` store. It changes buyer setup; noted for 3.x.
- Rewriting the GUI.

**Budgets at n = 200 players in one server** ("50 %" is the design ceiling)

| Resource | Limit | 50 % ceiling | Now at 200 (est.) | Target |
|---|---|---|---|---|
| DataStore Get (UpdateAsync bills Get **and** Set) | 60+10n = 2060/min | 1030 | 700–1300 | ≤ 450 steady, ≤ 900 storm |
| DataStore Set/Update | 2060/min | 1030 | 700–1300 (XP) | ≤ 300 steady |
| GetSorted | 5+2n = 405/min | 202 | ~5 | ≤ 20 |
| Per key | 1 write / 6 s; 4 MB value | — | XP key every 3–10 s | ≥ 7 s gap enforced; no value > 1 MB |
| HttpService (per server, **independent of n**) | 500/min | 250 | non-donor cash refetch ~260 steady; storm ~500–700; ReliabilityV2 ~400 POST per donation | ≤ 120 steady, ≤ 200 storm + donation burst |
| Messaging receive, per topic | 40+80·S | 60 (S=1) | up to 80/topic | ≤ 12 publishes/min/topic/server |
| Messaging receive, whole game | 400+200·S | 300 (S=1) | ~320 | ≤ 60 |
| MemoryStore memory | 64 KB + 1 KB·users = 264 KB | 132 KB | LB cache 60–100 KB (overflows at low CCU) | ≤ 16 KB total |
| MemoryStore item | 32 KB | 16 KB | Robux top-100 ≈ 15–25 KB | ≤ 4 KB |

The storm front binds before the steady state does. The Get budget grows with players already in the server, so it averages about 60 + 10·33 ≈ 390/min in the first minute of a storm. Loads must therefore be prioritized, not merely capped. HTTP is the resource that does not scale with n, so **no per-player HTTP call may remain on the join path or in any recurring loop.**

## 2. Workstreams

### A. DataStore write discipline

**Problems (all verified)**
- **XP writes too often.** XP writes ~1 `UpdateAsync` per player every 3–10 s. The path is `LevelController.luau:94-110` → `LevelService.luau:71-77` (`SAVE_BATCH_SIZE = 2`, and every grant is ≥ 2) → `OverheadRepository:update` → `PlayerSessionStore.scheduleFlush` (3 s debounce, `PlayerSessionStore.luau:200-222`) → `durableWrite` (`OverheadRepository.luau:51-78`). Nothing enforces a minimum gap per key.
- **Dirty data dropped.** A cross-server invalidate drops dirty sessions (`OverheadRepository.luau:41-45`, `SettingsRepository.luau:44-47`, `PlayerSessionStore.luau:109`), and so does a failed leave flush (`PersistenceFabricHooks.luau:19-25`).
- **Join loads abandoned.** `ProfileLoader.luau:169-171` breaks on `budget_low`, and `Main.server.luau:671-711` requeues only `overhead`. VenueQuestProgress bypasses the loader (`EventBoardController.luau:440-453`).
- **GiftPending never deleted.** `GiftPendingRepository.luau:122-131` returns nil, which cancels the write.
- **Leaderboard verify reads.** `ProgressLeaderboardRepository.luau:197-265` does up to 30 uncached Overhead reads per 120 s. The cache TTL is 60 s, so every refresh misses. `forget()` (`:95`) is never called.
- **Likes metadata.** `AvatarLikeRepository.luau:699-714` does 20 uncached reads per rebuild.
- **Scheduler ordering.** `DataStoreScheduler.luau:209-274` reserves an in-flight slot before taking the key mutex.
- **Venue progress.** `EventBoardController.luau:490-496` flushes every session in one tick; `:456-463` drops the session before its flush result is known; `EventBoardDomain.luau:256-306` never prunes.
- **Messaging.** `CrossServerCache.luau:145-159` does not requeue a failed publish; `:175-189` puts an uncapped id list in one message; `:84-102` does a non-atomic MemoryStore lease on every publish.
- **MemoryStore rows.** Leaderboard cache rows carry names and thumbnails (`DonationLeaderboardRepository.luau:989,1110,1212,1297`).

**Design**

1. **`S/Persistence/PlayerDocWriter.luau`** wraps `PlayerSessionStore`; its pure policy lives in `Sh/Domain/FlushPolicy.luau`.
   - Per-document state: `{dirty, urgent, lastWriteAt, baseRevision, pending: {mutator}, stale}`.
   - `nextFlushAt`:
     - Dirty documents flush at `lastWriteAt + 90 s`, staggered by `userId % 90`.
     - Urgent documents (level-up, membership, title, currency, role, leave, shutdown) flush at `max(now, lastWriteAt + 7 s)`.
   - One 1 Hz scheduler takes at most `ceil(dirty/60)+2` flushes per tick (≈ 2.2 writes/s at 200).
   - XP only marks a document dirty; `SAVE_BATCH_SIZE` flushing is removed.
   - **No lost writes:**
     - The transform replays the pending mutators when `stored.rev ~= baseRevision`. `rev` is a new additive field in `OverheadStoredData`/`Settings`, and `sanitize()` defaults it to 0.
     - A cross-server invalidate or `version_conflict` on a dirty session marks it `stale` instead of clearing it.
   - **Leave:** retries at 2/4/8 s with the entry in a `departed` map (cap 400). `clear` runs only after a write succeeds.
   - **BindToClose:**
     - Writes dirty documents only, in the order Overhead → VenueQuestProgress → Settings → the rest.
     - At most 12 writes/s across the 25 s window.
     - `ServerRestartHooks` starts the same flush 60 s early.
2. **ProfileLoader**
   - Requeues *every* kind on `budget_low` or `budget_exhausted`: backoff 10/20/40/80 s ± 20 %, 5 attempts, then a `load_gave_up` event.
   - Priority classes:
     - P0: `overhead`, `profile`.
     - P1: `settings`, a new `venue_quest` kind that replaces the direct load.
     - P2: `stickers`, `favorites`, `music_favorites`, `likes_summary`. These load lazily on first use or 60 s after join.
   - A job is admitted only while the GetAsync budget exceeds `20 + 2·inFlight`.
3. **GiftPending:** the transform returns a tombstone `{state="consumed", consumedAt, toUserId}` that `parseEntry` treats as empty. The consume is atomic, the shape is additive, and the `isExpired` sweep removes old tombstones.
4. **Verify reads**
   - Online sessions are read first.
   - Offline documents are cached in an LRU (256 entries, 600 s).
   - `forget()` is called on leave.
   - Likes metadata is cached in an LRU (500 entries, 30 min).
5. **DataStoreScheduler:** take the key mutex *before* reserving the in-flight slot.
6. **Community increments** are aggregated per `communityId` and flushed every 30 s and at BindToClose.
7. **MemoryStore rows** become compact: `{u,t}` for users and `{c,t}` for communities, ≤ 4 KB per item. Names are resolved locally.
8. **Venue progress**
   - Flushes are staggered by `userId % 120`.
   - On leave: flush first, then remove.
   - `EventBoardDomain.prune` drops quests more than 30 days past their due date or gone from the board, and caps `seenPosts` at 50.
9. **CrossServerCache**
   - Publishes only identity-visible changes. XP never publishes, because a player is only ever in one server.
   - 5 s coalescing, ≤ 60 ids per message (split beyond that), one requeue after a failure.
   - A local 12/min/topic bucket replaces the MemoryStore lease.
   - The legacy `userId` field is kept so old servers still parse the message.

**Acceptance**
- `UpdateAsync` on `Overhead_v1`: ≤ 1 per player per 60 s steady, and 0 writes to the same key within 6.5 s (counter `samekey_gap_violation` = 0).
- Set/Update ≤ 300/min and Get ≤ 450/min at 200 players steady.
- Storm of 200 in 180 s: P0 loaded p95 ≤ 15 s; all kinds p95 ≤ 90 s; `load_gave_up` = 0.
- Kill-test: invalidate during dirty, a leave flush failing twice, and shutdown with 200 dirty documents each lose 0 XP.
- Messaging ≤ 12 publishes/min/topic/server; payload ≤ 1 KB.

**Tests**
- Lune specs: `FlushPolicy`, the replay transform, the GiftPending tombstone, `EventBoardDomain.prune`, and CrossServerCache splitting at ≤ 1 KB.
- Studio harness (`.tmp/`): 200 synthetic userIds pushed through ProfileLoader on a TEST place, recording the lowest budget reached.

**Surface:** engine source sync. Kill switches `Config.Persistence.WRITE_POLICY = "v2"|"legacy"` and `LOADER_REQUEUE_ALL` (engine constants, not buyer config).
**Keys:**
- No new DataStore keys; `rev` and the tombstone are additive.
- The MemoryStore map becomes `ClubKitLeaderboardCache_v2`, a 60 s TTL cache, so old and new row shapes never mix.

**Registers:** `PlayerDocWriter` goes in `ServerModuleBag`; Main.server stays at 125.

### B. Global-document discipline

**Problems:**
- `EventBoardProvider.luau:85-93`: every server runs `SetAsync("board", raw)` per revision, with no gate and no retry, and stores the raw HTTP body.
- `MusicRepository.luau:685-719` + `MusicLibraryProvider.luau:232-234`: every server rewrites `Tracks` and `Playlists` per revision.
- The duration update rewrites the whole `Tracks` value.
- The web-mode merge keeps deleted entries (`:682-683`), so the document grows without bound.

**Design:** one helper, `S/Persistence/GlobalDocWriter.writeIfNewer(store, key, doc, revision)`, used by both.
- It runs `UpdateAsync` whose transform returns nil (cancels) when `old.rev == revision` or `old.rev` is newer. One writer wins; the other servers cancel.
- Writes go through BudgetGate with 3 retries (2/5/15 s) and a random start delay of 0–20 s, so overflow servers rarely collide.
- Before writing, the helper encodes the document and refuses anything over `MAX_DOC_BYTES = 1 MB` with a `doc_oversize` telemetry event.
- It stores the **sanitized** board (`EventBoardDomain.readBoard` output), plus `rev` and `writtenAt`.
- **Music in web mode (the only mode in 3.0):**
  - The cache is the snapshot, written as-is: no merge, so tombstones are gone.
  - `updateTrackDuration` writes to an in-memory overlay and the existing duration report to the VPS. It never writes the DataStore.
- **Split strategy, only if a measured library exceeds 1 MB:** shards `Tracks:1..n` (≤ 900 KB each) plus `TracksManifest {rev, n}`. Readers fall back to the legacy `Tracks` key. These are new keys and would get their own migration note. First measure THE BASIC's encoded size; ~5–10 k tracks would reach 4 MB.

**Acceptance:**
- ≤ 1 committed write per revision per experience; other servers' attempts cancel.
- 0 writes when the revision is unchanged.
- Largest global value ≤ 1 MB, logged at boot.

**Tests:** lune spec of the revision-gated transform (equal, newer, older, nil); size-guard spec; Studio check that two servers with the same revision produce one committed write (read `GetVersionAsync`/`ListVersionsAsync` on the key).
**Surface:** engine.
**Keys:** unchanged unless sharding is triggered.
**Registers:** none.

### C. HTTP discipline (500/min per server, whatever n is)

**Problems**
- **Eight separate `RequestAsync` paths**, none counted or limited. The inventory is in `DonationService.luau:440-580`, `LicenseService.luau:103,204`, `IntegrityTripwire.luau:23`, `MusicLibraryProvider.luau:85,136`, `EventBoardProvider.luau:133`, `OverheadService.luau:73`, `ProfileSocialService.luau:56,122` and `JoinCommunityMembersService.luau:625,767,816`.
- **Secret in the query string** at `OverheadService.luau:71`, `ProfileSocialService.luau:48,113` and `JCMS.luau:613`.
- **ReliabilityV2 flushes after every single insert** (`DonationService.luau:719,739`), and display does not need a pending entry (`:726-740`).
- **Commands are polled after every notification poll** (`:1962`).
- **Social lookups cost up to 9 GETs per join** (`ProfileSocialService.luau:146-154`, `Main.server.luau:992-1022`).
- **Non-donors are refetched about every 45 s: roughly 260 requests/min at 200 players, over the 250 ceiling on its own.**
  - Every payload rebuild (every 10 s) resolves the cash rank chip. When the workspace board has no rank, it calls `getPlayerCashStats` (`OverheadService.luau:560-580`) and negative-caches the answer for only 5 s (`:314`).
  - `getPlayerCashStats` ignores a cached total of 0 (`DonationService.luau:2191`).
  - So it falls through to `fetchDonorCashProfile`, which does cache the 0, but only for 45 s (`:2027`, `Config.luau:2939`).
- **The music import sends the whole library** with no size check (`MusicLibraryProvider.luau:115-136`).

**Design**

1. **`S/Net/BackendClient.luau`** is the only caller of `RequestAsync`.
   - Signature: `request{endpoint, method, path, body?, auth="donation"|"gamedata", priority="critical"|"normal"|"bulk", timeoutSec}` → `Result`.
   - One server-wide token bucket, 400/min with a burst of 40:
     - `critical` (license, notifications, delivery register) may drain it.
     - `normal` stops at 25 % left.
     - `bulk` (lookups, telemetry, import, beacons) stops at 50 % left and is deferred, never dropped.
   - Counters per endpoint: calls, failures, 429s, timeouts, p95 latency.
   - Circuit breaker per endpoint group: opens after 5 straight failures or ≥ 50 % failures in 30 s; half-open after 30/60/120 s.
   - Auth is always `Authorization: Bearer`, read by one `readSecret`.
   - `Timeout` is an integer: 5 s by default, 10 s for license, 15 s for import. Only idempotent GETs get their single retry.
2. **Join lookups are batched.**
   - New VPS route: `POST /game/<key>/v3/players/lookup {userIds≤50, want:["cash","groupRank","connections"]}`.
   - `S/Net/JoinLookupBatcher` collects joins over a 3 s window. At 67 joins/min that is ≤ 20 requests/min, down from 200–600 today.
   - The per-user routes stay for old kits.
   - Caches:
     - Success: groups and social 600 s, cash 120 s.
     - Negative results: 300 s, **including a zero total**. `getPlayerCashStats` honours a cached 0, and the rank-chip negative cache goes from 5 s to 300 s for players with a 0 total. Both are cleared by a notification or `DonorCashSync_v1` that names the player. Target: ≤ 1 cash request per player per session without a donation (P1, because it is small and on its own exceeds the ceiling).
     - Cash is also invalidated by `DonorCashSync_v1` or by a notification that names the donor.
   - No warm retries.
3. **ReliabilityV2 batching**
   - Ack and display queues flush every 3 s or at 100 entries (the VPS accepts 200).
   - Entries are deduped by `(donationId, userId)`.
   - A display needs a pending entry or a known donation.
   - Each player is limited to 4 events per 10 s.
   - Result: ≤ 40 POST/min whatever n is, against ~400 per donation today.
4. **Command polling piggybacks on notifications.** The VPS adds `has_commands` to `/v2/notifications` (an additive field). The kit polls commands only when the flag is set, plus a 60 s safety poll.
5. **Music import:** a body over 900 KB is refused with an `import_oversize` event, and the game keeps playing from cache. Chunked import gets built only if that event is ever seen.
6. **HTTP after the change**
   - Idle ≈ 11 notifications + 1 commands + 0.5 leaderboards + 1 music + 1 event board + ~0.1 license/telemetry = **~15/min**.
   - Storm plus a donation burst ≈ 15 + 20 lookups + 40 ReliabilityV2 + 13 extra notification polls = **~90/min** (18 % of the limit).

**Acceptance**
- Grep gates: `BackendClient` is the only `RequestAsync` caller, and no secret appears in a query string.
- ≤ 120/min steady and ≤ 200/min in a storm, measured by the client's own counters.
- 0 HTTP 429s in a synthetic 200-join storm.

**Tests**
- Lune: token bucket and priorities, breaker, batcher, ReliabilityV2 dedup.
- API node tests: `players/lookup`, `has_commands`.
- Studio: DonationService dry-run against a mock server.

**Surface:** engine plus VPS. The VPS routes ship first; the kit falls back to the per-user routes on a 404.
**Keys:** none.
**Registers:** both new modules go in `ServerModuleBag`.

### D. VPS API hardening

**Problems (all verified; paths under API unless noted):**
- **Webhooks** (`app.js`): overwriting upsert (`:1166-1181`), `Date.now()` fallback id (`:122-126,256-264`), path token only (`:1151`).
- **Secrets:**
  - Compared with plain `===` (`app.js:135,146,315,989,1151`; `v2-routes.js:29,32`; `v3-routes.js:64,67`; `social-routes.js:100`).
  - `?secret=` accepted everywhere; v1 accepts only the query string (`app.js:989`).
- **Unguarded routes:** v1 has no licence gate (`app.js:986-1145`); `/v2/beacon` is unthrottled (`license-routes.js:222-275`).
- **Limits:** `server.js:43-47` sets no body cap or idle timeout; telemetry checks size only after parsing (`v3-routes.js:351-357`).
- **Heavy queries:**
  - Cash runs up to 3 CTE aggregations (`lib/game-data.js:57-149`).
  - Leaderboards are rebuilt per call (`:151-204`).
  - `total_after` is a correlated `SUM` (`:277-285`).
  - `DELIVERY_COUNTS_SQL` (`owner-routes.js:245-255`).
- **Event board:** uncapped (`event-routes.js:105-117`); expiry filtered in JS (`lib/event-board.js:210`).
- **Dashboard auth:** no login throttle and a username timing leak (`auth-routes.js:84-99`); SSE uncapped (`lib/sse-hub.js`).
- **Platform:**
  - Un-awaited handler returns (`app.js:1595-1643`).
  - `HOST` defaults to 0.0.0.0 (`config.js:67`).
  - `SESSION_SECRET` falls back to a constant (`config.js:36`).
  - Caddy logs full URIs (`caddy/Caddyfile:6-11`).

**Design**

1. **Webhooks**
   - `ON CONFLICT DO NOTHING`. A payload that differs from the stored row is logged as `webhook_conflict` and never overwrites it. Status only moves forward.
   - The fallback id is `sha256(provider + canonical body)`.
   - Provider signatures (Saweria HMAC, BagiBagi, SociaBuzz) are all **to verify** against provider docs. Until then: path token, constant-time compare, 60/min per IP, and idempotency.
2. **Secrets**
   - Export `constantTimeEqual` (`lib/auth.js:13-20`) and use it everywhere.
   - Drop the secret from `gameEndpoints` (`app.js:172`).
   - `?secret=` starts answering 400 once ≥ 95 % of active games send headers, or 30 days after the release, whichever the owner picks.
   - Rotation: migration `0026_game_secret_next`. Both secrets are accepted during the switch: set `next` → buyer updates `Secrets.luau` → promote → clear.
3. **Rate limits** (in process, LRU of 10k keys):
   - `/game/*`: 600/min per game key.
   - Webhooks: 60/min per IP.
   - Login: 5/min per IP and 10 per 15 min per username.
   - Beacons: 1 row per (game, reason) per minute, and at most one Discord alert per game per 10 min.
4. **Size:**
   - `Bun.serve({maxRequestBodySize: 2 MB, idleTimeout: 30})` plus Caddy `request_body max_size 2MB`.
   - Telemetry checks the byte length before parsing.
5. **Queries**
   - Migration `0027_donor_totals`: a `donor_totals` table and a stored `donations.total_after`, both maintained in the insert/void transaction and backfilled once.
   - Leaderboards are cached 15 s per (game, board) and invalidated on insert.
   - The daily board filters on an indexed `received_at` range.
   - `DELIVERY_COUNTS_SQL` becomes a single `GROUP BY donation_id` with an index on `(donation_id, status)`.
6. **Event board:** at most 50 posts and 30 quests per venue; the due-date filter moves into SQL with an index on `(game_id, deleted_at, due_date)`.
7. **Auth**
   - A dummy bcrypt compare runs when the username is unknown.
   - SSE is capped at 5 connections per user and 50 per game.
   - The server refuses to boot on a missing, default or short `SESSION_SECRET`.
8. **Platform**
   - `await` every handler; `HOST=127.0.0.1`.
   - systemd: `MemoryMax=1G`, `LimitNOFILE=65536`, `StartLimitIntervalSec=0`, plus a health-check timer.
   - Bun gets a SIGTERM handler that runs `db.close()`.
   - The v1 route gets the licence gate.
9. **Logs:** a Caddy `format filter` deletes the `secret` query parameter; purge the 1,403 lines already logged.
10. **brm-api**
    - `silencedetect` runs through async `spawn` in a queue of 1.
    - The rate limit is keyed on the authenticated principal, not the raw header.
    - A `bodyLimit` is added and uploads stream to disk.
    - Open Cloud polling honours `Retry-After`.

**Acceptance:**
- The API suite passes, plus new tests: a duplicate webhook does not change the amount, retries without an id produce one row, a 3 MB body gets 413, 6 logins in a minute get 429, a beacon flood writes 1 row per minute.
- p95 of `players/:id/cash` < 5 ms at 10 k donations (bench script).
- 0 `secret=` in new Caddy log lines.

**Surface:** VPS deploy only (API restart auto-migrates; dashboard untouched).
**Keys:** migrations 0026–0028 are additive.

### E. Data lifecycle and backups

**Problems:**
- Only `telemetry_events` is pruned (`v3-routes.js:364-368`).
- Row counts on 2026-09-24: acks 22 k, deliveries 13.8 k, webhook events 1.1 k, beacons 1.2 k. Growth ≈ 15 MB/day at 15 venues.
- Backups: daily, on the same disk, no off-site copy (`scripts/backup.sh:28-29` commented out), `brm.sqlite` not included, verify not scheduled.

**Design**

1. **Nightly prune:** `scripts/prune.js` on a systemd timer at 03:30 WIB, deleting in batches of 5,000.

   | Table | Deleted after |
   |---|---|
   | `delivery_acks` | 30 days |
   | `notification_deliveries` | 90 days, after its counts are rolled into `donation_delivery_stats` (migration `0028`) |
   | `webhook_events` | 30 days (`donations.raw_payload` keeps the evidence) |
   | `license_beacons` | 180 days |
   | done or failed `game_commands` | 30 days |

   Then `incremental_vacuum` and `optimize`. This needs a one-time `auto_vacuum=INCREMENTAL` + `VACUUM` (seconds at 8.7 MB) and `journal_size_limit` set to 64 MB.
2. **Backups**
   - **Litestream** streams `db.sqlite` **and** `brm.sqlite` to object storage: RPO ≤ 1 min, 30-day retention.
   - The daily gzip backup stays, and rclone copies it to a second prefix kept for 12 weeks.
   - A nightly verify restores to a temp file, runs `integrity_check` and compares row counts within ±1 %. It alerts Discord on failure or when no heartbeat has arrived for 26 h.
   - `docs/RESTORE.md` is the runbook, with an RTO of 30 min or less.

**Acceptance:**
- DB size flat ±10 % week over week.
- One restore drill done and recorded.
- A forced failure raises the alert.

**Surface:** VPS only.

### F. Observability

**Design**
- **Kit:** a minimal ADR 0007 Phase B `TelemetryService` with kind `budget`, built **first** so every later phase has a baseline.
  - One aggregate per 15 min through `BackendClient`, at bulk priority. No UserIds.
  - Contents (per-minute maxima and p95s):
    - DataStore requests by type and the lowest remaining budget; `budget_low`/`exhausted`
    - `samekey_gap_violation` and the oldest dirty document
    - loader queue depth, p95 load time and `load_gave_up`
    - HTTP by endpoint and the bucket's lowest fill
    - Messaging per topic
    - players, heartbeat p50/p99, server memory
  - Gated by `ClubKitConfig.Telemetry.Enabled` (schema + template, as ADR 0007 decided).
- **VPS:** a master-only "Budgets" panel on the Fleet page, plus Discord alerts:
  - **Warn:** any budget p95 above 50 % for 2 flushes in a row, or a dirty document older than 300 s.
  - **Critical:** any `budget_exhausted`, any HTTP 429, a failed backup verify, or 5xx above 1 % over 5 min.
- **Redaction:** `Logger` masks keys matching `/secret|token|authorization|cookie/i`; the VPS never logs query strings.

**Acceptance:** the budget panel shows THE BASIC TEST within 30 min of boot; a forced `budget_exhausted` in Studio raises an alert.
**Surface:** engine + schema/template key + VPS.
**Registers:** `TelemetryService` goes through `ServerModuleBag`.

### G. File and naming cleanup

**Safe** = internal to the engine, and client and server ship together. **Compat** = needs an alias or fill-forward.

| # | Now | Target | Class |
|---|---|---|---|
| G1 | `Config.Donation.SHEETS_WEB_APP_URL` (8 refs, 7 files; set in `ConfigBootstrap.luau:292`) | use the existing `Config.Donation.API_URL`; keep the old field set for one release, then delete | Safe (engine constant; the buyer key `Donation.ApiUrl` is unchanged) |
| G2 | `MSG_SHEETS_ERROR`, `SHEETS_REFRESH_SIGNAL_ONLY`, `computeSheetsFingerprint`, `broadcastSheetsLeaderboardSignal`, `sheetsBroadcastRevision` (`DonationService.luau:270-318`), payload type `"donation_sheets_refresh"` (`ShopController.luau:826`) | `…Web…` / `"donation_web_refresh"` | Safe (the remote payload stays inside one server's version) |
| G3 | `saweriaName` (94 kit refs), API/DB `saweria_name` (174 refs in API) | kit `donorName`. The API adds `donor_name` next to `saweria_name`, the kit reads `donor_name or saweria_name`, and the DB column is kept (SELECT alias) | Kit safe; **API compat** |
| G4 | Buyer keys `Features.DonationSaweria`, `SaweriaWorldTiers` (`ClubKitConfigSchema.luau:22,605`) | keep; document them as provider-neutral legacy names | **Compat — no rename** |
| G5 | `ManualBagibagiRepository` | `ManualDonationAdjustmentRepository`; the store `ManualBagibagiAdjustments_v1` is **unchanged** | Module safe; key compat |
| G6 | `Sh/Utils/HttpApi`, `HttpApiCounter`, client `ClientHttpApi` (these wrap Roblox engine web APIs) | `RobloxWebApi`, `RobloxWebApiCounter`, `ClientRobloxWebApi`; `BackendClient` is the VPS client | Safe |
| G7 | Server-only modules replicated to every client: `Sh/Utils/{DataStoreScheduler, DataStoreThrottleLockout, BudgetGate, CrossServerCache, MemoryStoreCache, PlayerSessionStore, HttpApi, HttpApiCounter}`, `Sh/Tools/{RopeServer, SignServer}` | `S/Persistence/*`, `S/Net/*`, `S/Tools/*`. Not replicated, which also means less client memory and less exposure | Safe. Verify first that no client requires them and that Update Engine deletes files dropped from the manifest |
| G8 | `Sh/ContextModule/{AnimationLoader, AnimatorUtils}` | `Sh/Animation/*` | Safe |
| G9 | Local `filterForBroadcast` copies: `CrowdController.luau:51`, `ShopController.luau:130`, `DonationService.luau:508` | `TextFilterUtil.filterForBroadcast` (`Sh/Utils/TextFilterUtil.luau:89`) with thin adapters (the return types differ) | Safe |
| G10 | `readSecret` copies (`MusicLibraryProvider.luau:22`, `EventBoardProvider.luau:25`), base-URL trimming in 6 places, `IntegrityTripwire.beacon` ≈ `LicenseService.postBeacon` | `BackendClient` | Safe |
| G11 | `S/Services/DemoDataProvider`, `S/Debug/LeaderboardScaleAudit` (required by `DonationController.luau:20,25`) | `S/Dev/*`, required lazily, only when `Config.Demo` or `RunService:IsStudio()` | Safe |
| G12 | 32 lune specs in `.tmp/` (git-ignored, so **not version-controlled**) | `tests/spec/*.spec.luau` (tracked) plus `tools/run-specs.ps1`. Scratch harnesses stay in `.tmp/` | Safe |
| G13 | Place-side scratch `ServerStorage.CK_REPUSH_EXEC` and `_G.__CK_REPUSH` (from `.tmp-sync-mcp/_repush`) | remove from places at the next sync; `PlaceSecurityScan` flags them | Safe (place hygiene) |
| G14 | Template `ClubKitConfig.luau:10,76,85` still describes Cloudflare Worker/D1/wrangler and a `workers.dev` ApiUrl | template text and default point to `api.hazastudio.id` | **Template only**; buyer copies are never touched |
| G15 | Messaging topics `OverheadInvalidate`, `SettingsInvalidate`, … (unversioned) | keep the names; payload changes stay additive because old and new servers coexist during a rollout | Compat |

DataStore keys, buyer config keys, GUI instance names and API fields are **not renamed**. Where a rename is desired, it gets an alias and a release note.

### H. Server and client performance at 200 players

From the performance audit, re-checked in the code. "Dense" means most players are within the 55-stud overhead range.

**Server CPU and memory**

| # | Finding (verified) | Decision | Metric | Phase |
|---|---|---|---|---|
| H1 | **XP fan-out.** Every 10 s XP tick calls `refreshPlayer` (`LevelController.luau:28-49,103-111`). `xp`, `xpProgress` and `xpNeeded` sit in the payload and its fingerprint (`Types.luau:173-176`, `OverheadController.luau:425-426`), so each tick means a full rebuild plus a delta to every viewer. Dense, that is ≈ 4,000 sends/s. | XP values go to the owner only (`kind="self_progress"`, at most every 5 s). Viewers see only `level`/`levelText`, and `refreshPlayer` runs only on level-up. One 1 Hz `OnlineXpTicker` (buckets by `userId % 10`) replaces the 200 per-player loops. | Overhead deltas ≤ 0.2/s per subject; kit threads do not grow with n | P3 |
| H2 | **Per-pair deep copies** (my earlier "already fine" was wrong). DeltaCompressor deep-clones the last payload for every viewer–subject pair (`DeltaCompressor.luau:73-78`, `DEEP_DELTA_NESTED = true` at `Config.luau:4170`). Dense, that is ~40k copies, about 40–100 MB. `cleanup(prefix)` scans every key on each leave (`:176-181`, called at `OverheadController.luau:1565`), so a leave costs O(n²). | **Per-field versions.** Each subject keeps its current payload and a version number per field; each pair stores only `lastSentVersion` (one number). A delta is the set of fields newer than that. Pairs are indexed `[subject][viewer]`, so a leave costs O(k). | Pair state ≤ 16 B; server memory from the overhead system ≤ 10 MB dense | P4 |
| H3 | **Proximity recompute.** Runs every 0.5 s. The grid cell equals the leave radius (~70 studs, `ProximityInterestService.luau:289-328`), so a dance floor falls into one or two cells: 40k distance checks twice per second, plus a prune pass over every pair (`:267-285`). `recomputeNow` runs on every spawn (`:400-410`). | Squared distances; subjects staggered in 4 groups (each re-evaluated every 1 s); at most **30 nearest subscribers per subject** (by distance); a spawn triggers an O(n) recompute of that player's row only. | Recompute ≤ 1.5 ms per tick at 200 dense | P4 |
| H4 | **MovementGuard in one frame.** Samples every player in a single Heartbeat every 0.5 s (`MovementGuard.luau:323-343`). Each sample builds a list excluding every character, a new `RaycastParams` and 2–3 raycasts (`:151-156`): O(n²) work in one frame. | One `RaycastParams` whose exclude list is maintained on `CharacterAdded`/`Removing`. A round-robin quarter of players per tick above 60 players (2 s per player). | ≤ 0.5 ms per tick | P4 (ADR 0008 addendum) |
| H5 | **Keyed tables and connections never cleared on leave** (verified: no `= nil` path): `SettingsController.luau:68` `publicSyncTokenByUserId`, `RoleToolService.luau:20`, `SyncService.luau:172` `prewarmGeneration`, `DonationService` `knownDonors` (277), `sessionRobuxTotals` (338), `userInfoCache` (896), `donorCashCache`/`donorFailureCache` (93), `AvatarLikeRepository.luau:55-56`, client `AvatarContextController.luau:51,54`. `ProximityInterestService.luau:411` adds a `CharacterAdded` connection per player to a module-lifetime cleaner. | Clear on `PlayerRemoving`. Where values must outlive the visit (`knownDonors`, `sessionRobuxTotals`, `userInfoCache`), use an LRU of 1,000. The proximity connection is stored per player and disconnected on leave. Every keyed table joins the **memory gate** below. | Gate green | P1 (leak fixes) |

**Network (remotes)**

| # | Finding (verified) | Decision | Metric | Phase |
|---|---|---|---|---|
| H6 | **Coalescing drops deltas (correctness bug).** `NetworkManager` coalesces per frame on key `viewer + kind + subject` and keeps only the *last* entry (`NetworkManager.luau:47-58,95-116`; `ENABLE_FRAME_COALESCE = true`, `Config.luau:4147`). Two `overhead_delta`s for the same pair in one frame drop the first, while the server baseline has already moved on, so the client never receives those fields. | Entries marked `merge = "fields"` (overhead delta, chat tag) are **merged** field by field, later wins; other kinds stay last-wins. Lune spec with two deltas in one frame. | 0 missing fields in the spec and in a 10-minute burst test | **P1** |
| H7 | **One `FireClient` per message.** No packing (`:137-153`), and `fireList` sorts and joins recipient ids per message (`:62-72`). | Pack each viewer's frame queue into one `{kind="pack", items}` per remote per frame; drop `listIdentity` sorting (the key is the remote plus the viewer). | `FireClient` calls ≤ 2 per player per frame; ≤ 600/s total steady | P4 |
| H8 | **Join snapshots.** Checked: the joiner's payload is rebuilt at join, +5 s and +10 s (`OverheadController.luau:1422,1433,1442`). The two later calls only *send* if something changed (`:1190`), so the cost is 3 rebuilds, not 3 sends. Entering a pair sends full payloads both ways (`:1700-1742`, 1–2.5 KB each), so a crowd walking onto the floor sends ≈ n² full payloads (~300 KB per client). `isNearbyForJoin` calls `getSubscribers` per existing player (`:1264-1275`). | The +5/+10 s rebuilds are replaced by a callback when the group rank resolves. Compact payload: enum ids instead of label strings, defaults omitted, target ≤ 600 B full. At most 20 pair-enter snapshots per viewer per 0.5 s, nearest first. The join check reads the precomputed subscriber set. | Pair-enter egress ≤ 20 KB/s per client in a crowd entry | P4 |
| H9 | **Chat tags go to everyone.** Upserts are sent to all (`:361`), and the joiner gets the whole roster (~30 KB at 200, `:368-377`). This is correct in principle, since chat is global. | Compact entries (≈ 40 B, enum-coded) sent in chunks of 50 per frame. Upsert only when a chat-visible field changes (fingerprint already exists). | Joiner roster ≤ 8 KB | P4 |
| H10 | **Leaderboards.** 10 boards, 15–40 KB per client per change, sent to all (`DonationController.luau:535-581,714`). | Revision broadcast (`lb_rev`, ≤ 64 B); a client fetches a board only while it is visible. | ≤ 64 B per client per change when not visible | P4 |
| H11 | **Greetings** go to all for every join (`JoinGreetingService.luau:452`). | Coalesce per 3 s; VIP and donor greetings stay individual. | ≤ 1 greeting broadcast per 3 s | P4 |

**Client (every one of 200 clients)**

| # | Finding (verified) | Decision | Metric | Phase |
|---|---|---|---|---|
| H12 | **AvatarPrewarmPool** builds a `CreateHumanoidModelFromUserId` model for *every* joiner on every client (`AvatarPrewarmPool.luau:496-505`) and reloads on every other player's respawn, pooled or not (`:466-489`). The queue is uncapped (2 concurrent, pool of 15), so ~199 builds per client while the server fills. | Prewarm only players within its own 30-stud radius and only while the pool has room. Reload on respawn only when the player is pooled. Queue capped at 10. Above 60 players, prewarm only players the user has interacted with. | ≤ 15 model builds per client per 5 min during a 200-join storm | P4 |
| H13 | **Distance culling.** "Far" means no limit (`OverheadUI.luau:854-862` returns 0), and overhead wrappers are CanvasGroups (one GPU texture each, `:198-206`). At Far, 200 textures blow the texture budget (blank overheads, ADR 0005). `CanvasGroupBudgetService` only covers workspace SurfaceGuis. The gradient loop runs at 30 Hz over every animated title with no distance cull (`:1315-1345`). | Far = 90 studs plus a hard cap of the **40 nearest** overheads enabled. The gradient loop skips culled titles (as `SharedTick.luau:66-90` already does). | ≤ 40 enabled overhead CanvasGroups; ≤ 1 ms per frame of kit client scripts in a crowd | P4 |
| H14 | **Server-built BillboardGuis** (`OverheadController.luau:519-523`): each client holds 200 × the template's instances. | Measure the template; target ≤ 40 instances each and `MaxDistance` ≤ 90. If it cannot shrink: **P4b client-side overheads** (attributes only, a pool for the 40 nearest), shipped as RBXM. | Kit instances on the client ≤ 8,000 at 200 | P4 / P4b |
| H15 | **Admin lists** rebuild in full on every join and leave, even while closed (`AdminPanelV3UI.luau:1067`, `AdminController.luau:468`). | Mark dirty; rebuild only when visible, with a 1 s debounce. | 0 rebuilds while closed | P4 |
| H16 | `SettingsController.luau:1151-1194` adds a `DescendantAdded` connection per other character (199), and a toggle walks every descendant of all 200 characters. | One `workspace.DescendantAdded` filter, plus a per-character tag cache. | Toggle ≤ 5 ms at 200 | P4 |

**Join path (not HttpService)**

| # | Finding (verified) | Decision | Metric | Phase |
|---|---|---|---|---|
| H17 | `GetGroupsAsync` is cached 300 s (`Config.luau:4096`) but payloads rebuild every 10 s, so each player refetches every 5 min (~40/min at 200). | The group rank is resolved at join and on `/re` only; rebuilds read the cached value. | ≤ 1 `GetGroupsAsync` per player per session | P4 |
| H18 | `UserOwnsGamePassAsync` runs sequentially for each shop tier on join (`ShopController.luau:236-270,955-965`), about 200/min in a storm. | Run the checks in parallel, cache for the session, update on `PromptGamePassPurchaseFinished`. | ≤ 1 call per pass per player per session | P4 |
| H19 | ProfileLoader runs fixed batches of 8 (`ProfileLoader.luau:224-257`), so one slow read holds up the whole batch. | Sliding window: a new job starts as soon as any slot frees (together with the A2 priorities). | Storm P0 load p95 ≤ 15 s | P3 |

**Memory gate.** A Studio harness runs 200 synthetic join/leave cycles. Every module table keyed by player or `userId` (H5, plus `cachedPayloads`, `activeGuis`, `dataReadyPlayers`, `chatTag*`, `pendingXp`, MovementGuard `tracked`, ProgressLeaderboard caches, EventBoard sessions, `aboutRosterEntryFingerprints`) must return to baseline ±1 %, and the connection count must not grow. The gate is listed in `tools/` and runs before every kit release.

**Acceptance** (200 players; 8 real clients + 192 synthetic)

| Metric | Target |
|---|---|
| Server heartbeat | p50 ≥ 55 Hz, p99 frame ≤ 25 ms |
| Kit server scripts | ≤ 4 ms per frame average |
| Remote sends | ≤ 600 `FireClient`/s total; egress ≤ 6 KB/s per player steady, ≤ 20 KB/s in a storm |
| Client | ≤ 8,000 kit instances; ≤ 40 enabled overhead CanvasGroups; kit `LuaHeap` + `Gui` growth ≤ 40 MB per hour |
| Server memory | growth ≤ 5 %/h after warm-up |

**Profiling method**
- Studio MCP `multiplayer_playtest` with 8 clients, plus a synthetic crowd harness in `.tmp/`: 192 NPC rigs registered with the proximity, level and overhead services under fake userIds.
- `capture_micro_profiler` for frame time, `capture_script_profiler` for per-module cost, `get_memory_breakdown` at 0, 30 and 60 min.
- Turn on `NetworkPerfCounters` and `HttpApiCounter` for the run (both are off by default: `Config.luau:4082,4153`), and compare with the client Developer Console network stats.
- Finally, one live peak on THE BASIC, read through F.

**Surface:** engine (H1–H13, H15–H19); RBXM only for P4b.
**Keys:** none.
**Registers:** `OnlineXpTicker` goes in `ServerModuleBag`; client changes stay inside their controllers. `Main.client` stays at 138.

## 3. Rollout

Every kit phase goes to **THE BASIC TEST** first, soaks 48 h, then goes to all buyers by source sync. VPS phases deploy behind additive migrations.

| Phase | Content | Channel | Gate to the next phase | Rollback |
|---|---|---|---|---|
| **P0 VPS safety** | E backups and verify, prune job; D logs redaction, body/idle limits, awaits, host bind, systemd, SESSION_SECRET check, timing-safe compares, webhook idempotency and fallback id, beacon throttle, v1 licence gate | VPS only | Restore drill passed; API suite green; 48 h without a 5xx increase | `git revert` + restart; migrations are additive; Litestream is independent |
| **P1 Kit correctness + budget telemetry** | GiftPending tombstone; leave/invalidate dirty fixes; venue progress flushed in BindToClose phase 1; ProfileLoader requeue-all; scheduler mutex order; **NetworkManager delta merge (H6)**; **non-donor cash cache (C)**; **leak fixes + memory gate (H5)**; F `budget` telemetry | Kit release (engine) + template key | 48 h on TEST: 0 data-loss repro, baseline budgets visible | Update Engine to the previous tag; `Config.Persistence` switches |
| **P2 VPS routes for the kit** | `players/lookup`, `has_commands`, `donor_name`, `donor_totals`/`total_after`, query caches, rate limits (log-only for 7 days, then enforce), event-board caps | VPS | Old kits unaffected (compat tests); p95 latency ≤ baseline | revert; the new routes are unused by old kits |
| **P3 Kit write + HTTP discipline** | A (PlayerDocWriter, XP 90 s, CrossServerCache, verify caches, MemoryStore v2, community aggregation), B, C (BackendClient, header secrets, batching, piggyback, batcher) | Kit release | TEST at peak: every budget ≤ 50 %, 0 lost XP in kill-tests, 0 HTTP 429 | `WRITE_POLICY = "legacy"`, `BACKEND_CLIENT = false`; previous tag |
| **P4 Performance at 200** | H1–H4, H7–H18 (H1 and H19 may ride P3). Order: H1 → H6/H7 → H2/H3 → H12/H13 → the rest | Kit release (+ RBXM only for P4b) | H acceptance on the 200-player synthetic run, then one live peak | previous tag; every H item has a `Config.NetworkPerf`/`Config.Overhead` switch |
| **P5 Cut-overs** | Query-string secrets rejected; v1 sunset; secret rotation | VPS | ≥ 95 % of active games on ≥ P3 kit | re-enable the query flag |
| **Cleanup G** | Safe renames ride with the phase that touches each file; G7/G8 moves ship in their own release after P3 | Kit | Compile check (`.tmp/compile-dir.luau`) + boot on TEST | previous tag |

A new versioned DataStore key appears only if music sharding (B) is triggered. It would be documented in `docs/releases/<ver>/UPGRADE.md` as additive.

## 4. Owner decisions (taken 2026-09-24)

| # | Decision | Owner's answer |
|---|---|---|
| 1 | XP crash window | **90 s** |
| 2 | Secrets in Caddy logs | **Purge the logs now; rotate every game secret after P5** |
| 3 | Off-site backup target | **One target: Google Drive** (rclone, hourly; the owner runs `rclone config` once) |
| 4 | Community leaderboard delay | **Accept up to 30 s** |
| 5 | Webhooks without signatures | **Path token + rate limit + idempotency**; check each provider's docs for signatures |
| 6 | Legacy v1 route sunset | **60 days after P5** |
| 7 | Retention | **acks 30 d, deliveries 90 d, webhook events 30 d, beacons 180 d** |
| 8 | ReliabilityV2 after batching | **On by default from the P3 release** (explicit `false` stays) |
| 9 | MovementGuard above 60 players | **Accept 2 s detection**; ADR 0008 addendum |
| 10 | Client-side overheads (P4b) | **Decide after the P4 measurement** |
| — | Start | **P0 (VPS) first** |
| 11 | Community Robux increments (P3) | **Keep one `IncrementAsync` per donation** — exactly-once receipt flags stay intact (2026-09-24, after the P3 report) |
| 12 | ReliabilityV2 on venues still on a Cloudflare Worker | **Set `Donation.ReliabilityV2 = false` in those buyer files only**, at their next update; everyone on the VPS keeps the new default— **Fleet check 2026-09-24 (VPS `kit_version_history` + `donations`):** every venue that reported a kit version this month talks to the VPS (ataslangit/parklab/rust/thebasic/zenithaquatic 2.12.0; athena/beathub-party/notcyrus/waktuindonesiaparty/tix 2.11.0; night-zone/hierapolis 2.10.0; atlantis 2.9.0; kasta/moody/vicenorth-demo 2.8.9). Venues with donations but **no kit report** = still on a Worker or dead: **after-hours, ruang-penat, vicenorth, haven, nuwa, altantis2, lantai-satu**. Rule at update time: if `ClubKitConfig.Donation.ApiUrl` host ≠ `api.hazastudio.id`, write `ReliabilityV2 = false` into the buyer file (additive key, buyer-owned) |
| 13 | Budget telemetry (`Telemetry.Enabled`) | **On by default** — one aggregate `POST /v3/telemetry` per server per 15 min, counts only |
| 14 | Urgent (non-XP) write window | **Keep 3 s** — only XP waits up to 90 s (decision 1) |
| 15 | Proximity viewer cap (P4, H3) | **40** — matches the client's 40-enabled-overhead cull (`Config.NetworkPerf.PROXIMITY_MAX_SUBSCRIBERS`, was 30) |
| 16 | Other players' XP bars (P4, H1) | **Owner-only XP ticks accepted** — others get XP with the next full snapshot or another changed field (`PERF_XP_OWNER_ONLY = true`) |
| 17 | Per-viewer packing (P4, H7) | **On by default** (`PACK_PER_VIEWER = true`); buyer scripts listening to `OverheadUpdate` must accept `{kind="pack", items}` — noted in the release UPGRADE guide |
| 18 | P4b overhead template trim (H14) | **Design now, ship later as its own template release** (Packager step); measured 106 instances / 18 UIGradient per head |
| 19 | P4b target (H14) | **49 instances / 6 UIGradient per head, no feature loss** (V6); the plan's 8,000-instances-per-client figure is restated to ~10,500 at 200 players (−52 % vs V4) |
| 20 | P4b template shape | **One template, V6 = trimmed V5** (image-title row included, hidden by default); V4/V5 stay in the place ≥ 2 releases as the undo |
| 21 | P4b Packager behaviour | **Copy buyer customisations (badge art, fonts, colours) by name automatically and report leftovers** |

### Original questions (kept for context)

1. **XP crash window.** A crash (not a leave or shutdown) can lose up to 90 s of XP. *Recommended: 90 s.*
2. **Secret rotation.** All 30 game secrets may appear in 1,403 Caddy log lines on the VPS. *Recommended: purge the logs now, rotate every secret after P5.*
3. **Off-site target.** *Recommended: Cloudflare R2 (no egress fee) with Litestream, plus rclone to Backblaze B2 as a second copy.*
4. **Community leaderboard delay.** Aggregation adds up to 30 s. *Recommended: accept.*
5. **Webhook providers without signatures.** *Recommended: path token + rate limit + idempotency; ask BagiBagi and SociaBuzz whether they sign callbacks.*
6. **Legacy v1 route sunset date.** *Recommended: 60 days after P5.*
7. **Retention periods** (acks 30 d, deliveries 90 d, webhook events 30 d, beacons 180 d). *Recommended as listed.*
8. **ReliabilityV2 for all venues after batching.** *Recommended: on by default in the schema from the P3 release* (buyers who set `false` keep it).
9. **MovementGuard latency at more than 60 players** (0.5 s → 2 s). *Recommended: accept, and write the ADR 0008 addendum.*
10. **Client-side overheads (P4b)** if the template cannot shrink. This is a GUI/RBXM change for every buyer. *Recommended: decide after the P4 measurement.*

## 5. Effort

| Workstream | Size | Notes |
|---|---|---|
| A DataStore write discipline | L | Biggest correctness surface; kill-tests |
| B Global documents | S | One helper, two call sites |
| C HTTP discipline | M | Kit + 2 VPS routes |
| D VPS hardening | M | Many small items, mostly independent |
| E Lifecycle + backups | S–M | Ops work + restore drill |
| F Observability | M | Part of ADR 0007 Phase B |
| G Naming cleanup | S–M | Mechanical; G7 needs a sync-deletion check |
| H Performance at 200 | L (XL with P4b) | 19 items; H2 (per-field versions) and H3 (proximity) are the biggest; needs the synthetic-crowd harness first |
