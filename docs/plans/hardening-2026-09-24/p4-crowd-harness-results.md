# P4 crowd harness — Studio run 2026-09-24 11:13 UTC

THE BASIC TEST 1.3, solo playtest, P1+P3+P4 build (merge `d8c2ff9`), harness `.tmp/crowd-harness-server.luau`
(`N = 200`, `CAP = 30`, dense floor 40×40 studs) run through `eval_server_runtime`. The kit's own modules
(`DeltaCompressor`, `ProximityInterestService`, `NetworkCoalesce`, `MovementGuard.benchSample`) in the Roblox
VM, legacy vs P4 side by side, fake subjects. Caveats: Studio on the owner's machine (plugin CPU
contamination is known — read ratios, not absolutes), and the harness itself competes with the running
server for the same thread (the `likes_backfill` job was force-released at 37.7 s during the run).

Switches live in the build: `OVERHEAD_BASELINE = "versions"`, `PACK_PER_VIEWER = true`,
`PROXIMITY_MODE = "incremental"`, `PERF_SPREAD_ABOVE_PLAYERS = 60`, `PERF_MAX_ENABLED_OVERHEADS = 40`,
`PERF_FAR_MAX_DISTANCE = 90`. `errors = []`.

## Results

| Measure | Legacy | P4 | Plan target | Verdict |
|---|---|---|---|---|
| Overhead baselines heap, dense (199 viewers each) | **119.6 MB** | **3.7 MB** | ≤ 10 MB | met |
| Overhead baselines heap, cap 30 | 20.4 MB | 2.4 MB | — | met |
| Fill 200 subjects × viewers, dense | 6.6 s | 123 ms | — | met |
| One XP tick on everyone → viewer sends, dense | 39,800 | **0** | 0 (H1) | met |
| One XP tick, compute, dense | 7.8 s | 90 ms | — | met |
| `refreshAll` with a real change, dense | 9.5 s | 117 ms | — | met |
| One leave, dense / cap | 29.5 ms / 1.1 ms | 5.5 ms / 0.18 ms | O(k) | met |
| Delta bytes avg (one changed field) | 17 B | 43 B | — | packing overhead, fine |
| Proximity steady, ms per tick | 89.8 avg (p95 161, max 545) @ 0.5 s | **2.47 avg (p95 8.8, max 12.7) @ 0.25 s** | ≤ 1.5 ms avg | **missed ×1.6** |
| Proximity steady, ms per second | 180 | 9.9 | — | 18× better |
| Proximity storm (200 appear at once), tick max | **2,818 ms** | 285 ms (avg 46) | note hitch | 10× better, still a visible hitch |
| Proximity pairs / enters in first 4 s | 40,000 / 39,800 | 6,200 / 6,003 | ≤ 31 per subject | met (30) |
| Spawn recompute | 62 ms (full) | 19 ms (one row) | ≪ full tick | met |
| Wire, one dense frame | 6,000 FireClient / 408 KB | **200 FireClient** / 419 KB | 1 per viewer (H7) | met |
| MovementGuard per 0.5 s tick | 72.5 ms (all 200 in one frame) | 9.8 ms (one of 4 slices, shared params) | ≤ 0.5 ms | **missed ×20** |
| Overhead template `OverheadGUIMainTemplateV4` | 106 instances, 18 UIGradient, 13 TextLabel, 0 CanvasGroup, MaxDistance 30 | same (code cannot change it) | ≤ 40 instances (H14) | **P4b decision** (21,200 instances per client at 200) |

## Reading

- H1/H2/H7 are solved: memory and fan-out are no longer a function of n².
- **H3 (proximity):** 2.47 ms avg per 0.25 s tick = ~1 % of a 60 Hz server frame budget spread over 4 groups; the miss vs 1.5 ms is small and Studio-inflated. The storm max (285 ms) is the number to watch live: it is one frame when 200 players appear at once, which only happens on a server restart under load. Options if it shows live: cap enters per tick lower than 20 (`PROXIMITY_MAX_ENTERS_PER_VIEWER`), or spread the storm over more ticks.
- **H4 (MovementGuard):** ~0.2 ms per player per sample is raycast-bound (2–3 raycasts per player). Reaching 0.5 ms/tick would need ~80 slices (a 40 s window) or fewer raycasts per sample. 9.8 ms every 0.5 s ≈ 2 % of frame budget; acceptable for now, revisit only if live frame time says so. Owner decision K8 (2 s window) stands.
- **H14 (template):** 106 instances × 200 heads = 21,200 GUI instances per client plus 3,600 UIGradients — this is the client-side cost that code cannot fix (P4b = trimmed RBXM template, owner decision K9 said "after measuring": this is the measurement). The 40-enabled-overhead cull (H13) bounds render cost but not instance count/replication.

## Not measured here (needs multiplayer or live peak)

Client: 40 enabled overheads, ≤ 1 ms per frame in `OverheadUI`, avatar prewarm builds; join-storm memory gate (200 join/leave cycles); kill-tests for P3 (invalidate while dirty, leave flush failing twice, shutdown with 200 dirty documents).
