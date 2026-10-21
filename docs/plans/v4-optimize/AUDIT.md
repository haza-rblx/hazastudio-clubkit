# v4 optimization — measured audit (2026-10-21)

Branch `perf/v4`. Every claim below is either measured in an Experiment Area playtest
(full kit + GUIs, `tools/PerfProbe.playmode.luau` and the MCP script profiler) or read from
source with a file reference. Studio playtest numbers include Studio and plugin cost, so absolute
frame times are not representative; relative comparisons and instance counts are.

## Baseline (Experiment Area, one client)

| Area | Value | Notes |
|---|---|---|
| PlayerGui | **9,065 instances** in 46 ScreenGuis | 38 % sit in disabled GUIs |
| ↳ DJGUI | 2,660 (disabled) | HZ-only experiment, not kit |
| ↳ 04-AdminHub | 625 (disabled) | dead since Admin Spotlight → **removed by StarterGuiPrune** |
| ↳ 07-MenuGUI / 06-MusicPlayerGUI | 806 / 753 | kit, in use |
| World SurfaceGuis | **14 boards, 6,002 instances** (~430 each) | biggest single UI block |
| Client total | 20,509 instances | |
| Memory (MB) | Gui 174 · GraphicsTexture 116 · Instances 130 | Studio-inflated LuaHeap/Script omitted |
| Remotes | 4 fires / 15 s, ~4 KB | network is **not** a bottleneck |

## CPU (script profiler, 10 s)

- Server: all kit code **< 0.1 %** (MovementGuard, NetworkFlushScheduler, Logger). Not a target.
- Client, unfiltered: dominated by **Elttob Reclass** (a Studio plugin, Fusion) and **DJXExperiment**
  (HZ-only). Neither ships to live servers.
- Client, kit only: `DonationLeaderboardController` podium loop **4.1 %** (fixed below),
  `NowPlayingView` progress 1.4 %, `TitleColorPreset.SharedTick` 0.7 %, `BoardAmbience` 0.6 %.
- A/B: disabling all 14 board SurfaceGuis changed frame time within noise → boards cost **memory**,
  not CPU, while idle (GUI caching works).

## Corrected findings (earlier audit claims that did not hold)

| Earlier claim | Reality |
|---|---|
| "INFO/DEBUG logs spam production" | `Shared/Utils/Logger.luau` already gates to ERROR outside Studio. |
| "Donation notifications re-fire up to 20× per player" | Re-fire happens only for clients that have not acked (still loading). A normal client receives one fire. |
| "Per-frame loops everywhere" | Persistent loops are already throttled and culled (`UPDATE_INTERVAL`, `PERF_CULL_INTERVAL`, `PERF_GRADIENT_CULL`, CanvasGroupBudgetService, NowPlaying draws only when visible). |
| "Remote traffic is heavy" | 4 fires / 15 s idle. |

## Done in this pass

1. **Podium loop gated by view** (`DonationLeaderboardController`): plays only within MaxDistance
   (150 when 0) and on screen; count-up writes at 30 Hz. Measured: 0 board text writes in 25 s with
   the camera away; 84 writes / 28 s facing a board (3 podiums × ~27).
2. **StarterGuiPrune** (`Server/Init`): removes never-bound admin templates from StarterGui at
   boot. Measured: PlayerGui 9,065 → 8,315 per player; Spotlight, AdminTitleV3 and AdminHub
   controllers boot clean.
3. **Mobile admin panel registration** points at `04-AdminSpotlight` (NZ live bug, ported).
4. Removed dead `AdminHubUI.luau`.
5. **Board rows only for ranks with data** (`WorkspaceLeaderboardRenderer`): 40 of 46 rows per list
   board were hidden clones in Experiment Area. Measured: world SurfaceGuis 6,002 → 1,727. Savings
   scale with how far a board is from its limit (full boards are unchanged).
6. **Calendar flame sways paused off screen** (`EventCardKit`). An idle property-write audit
   (20 s) found 13 looping flame tweens writing Rotation ~28×/s each, 3 of them inside the closed
   Event tab. A shared 1 Hz visibility check pauses them. Measured: hidden 0 writes / 3 s, visible
   324 writes / 3 s (3 flames, unchanged).

Idle writes still present, by design: `BoardAmbience` (30 Hz, boards within 140 studs and in
front of the camera; Experiment Area spawns next to all five) and the topbar `RunningText` marquee.
A MicroProfiler A/B of BoardAmbience was inconclusive (Studio frame time swung 65 → 150 ms between
captures); re-measure on a device before changing it.

## Next targets, by measured size

1. **Full boards.** A board at its limit still holds ~50 rows × ~21 instances while ~7 are visible.
   Options: lower row limits per board, or virtualize board rows (pool of visible rows, scroll by
   data). Needs an owner decision on how many rows a board should list.
2. **Disabled ScreenGuis (38 % of PlayerGui).** Candidates: templates for panels a player opens
   rarely (Couple, Shop, Event popups). A lazy-clone path (template moved to ReplicatedStorage at
   boot, cloned on first open) needs per-binder changes; do one panel at a time with a playtest.
3. **Admin-only templates for non-admins** (`04-AdminPanelv3`, 299). Admin status follows the
   role and can change mid-session, so a gate must re-clone on promotion. Behind a flag, tested
   with a non-admin and a promoted player.
4. **Venue drift.** Experiment Area's engine is behind the repo (no Giveaway) and has a local
   AdminSpotlightUI edit; NIGHT ZONE has 6+ live-only engine changes. A sync check
   (repo vs place byte diff per module) should run before every release.

## How to re-measure

Run `tools/PerfProbe.playmode.luau` in a playtest client (command bar or MCP
`eval_client_runtime`), and the MCP script profiler with `filter = "Hazastudio"` to isolate kit
code from plugins.
