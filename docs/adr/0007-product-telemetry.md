# ADR 0007 — Product telemetry: fleet health, field diagnostics, venue insights

**Status:** Accepted — decisions resolved by the owner 2026-08-28 (see below). Phases 0 + A **built and tested** the same day (infra repo: migration `0021_telemetry_events`, `v3/telemetry` ingest, `/api/owner/fleet` + `/api/owner/telemetry`, dashboard `Fleet.tsx` master-only page; API suite 39/39, dashboard build clean). **Deployed to the VPS 2026-08-28** (restart auto-applied migration 0021; dashboard swapped atomically). Fleet was enriched the same day — still existing-data-only: per-venue donation volume, upgrade trail, leak-beacon + DLQ chips. The master account is routed to `/fleet` only (owner pages break on `game_id NULL`). Phases B–E not started.
**Date:** 2026-08-28

## Context

The kit runs in N buyer places the vendor cannot see into. Concrete questions with no data today:
- "Recv network selalu tinggi — dari mana?" (the question that started this) — no per-channel attribution anywhere.
- Did ADR 0005 actually reduce texture pressure / blank panels *in the field*, or only in QA?
- Which buyers run which kit version? (partially answered by the license heartbeat, never surfaced.)
- Which features earn their maintenance cost (Music vs Carry vs Sticker…) and which are dead?
- Do errors spike on a new version before a buyer complains?

Existing plumbing this rides on (nothing is greenfield):
- **License verify heartbeat** (~30 min) already POSTs `kit_version`, `universe_id`, `player_count` → `games` columns + `license_beacons` (ADR 0006). This is the ingest pattern to mirror.
- **VPS API** (Bun/Node + SQLite, migrations → `0020`), **dashboard** React SPA (`apps/dashboard`, owner/master roles, recharts), deploy = API service restart + separate static dashboard rebuild.
- **Kit**: `NetworkManager` is the remote choke point (per-channel attribution hook point); notification delivery ledger already tracks reliability; `LeaderboardScaleAudit` already estimates egress.

## Researched constraints (2026-08-28, sources in CHANGELOG-adjacent chat log)

1. **HttpService budget is 500 req/min/server and SHARED** with donation polling + license verify + beacon. Body ≈ 1 MB.
   → **Binding design rule: telemetry is a periodic aggregate flush — never per-event HTTP.**
2. **Client memory is only readable on the client** (`Stats` reflects the calling peer). Client samples locally → batches to the server over one RemoteEvent → server includes it in the flush.
3. Memory API: `Stats:GetTotalMemoryUsageMb()` is the canonical number; `GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.*)` for breakdown — `GraphicsTexture` ties directly to the ADR 0005 texture-budget story. Known engine inconsistency between total and sum-of-tags → treat tags as *relative* signals, never reconcile them against the total.
4. **Native `AnalyticsService`** (≤100 custom events, custom fields for segmentation) is free and buyer-visible in *their* Creator Dashboard, but invisible to the vendor → good complement for buyer-side engagement, useless for cross-buyer telemetry. Kept out of this pipeline.

## Privacy commitments (design inputs, not afterthoughts)

- **Aggregate + anonymous only.** Counts, gauges, distributions. Player UserIds, names, chat, or any PII never enter a telemetry payload. (Systems that inherently key on users — delivery ledger, donor links — are separate, pre-existing, and unchanged.)
- **Buyer-visible and buyer-controllable.** New `ClubKitConfig.Telemetry = { Enabled = true }` key (schema + template, fill-forward per ADR 0001), documented in the upgrade guide. No covert collection.
- **Scoped views.** Owners see only their venue; the cross-buyer fleet view is `master`-role only.
- **Bounded retention.** Raw events pruned (proposed: 90 days) so the SQLite file cannot grow unbounded.

## Design

### Kit (engine files only; new services registered via Init bags per ADR 0002)

- **`TelemetryService` (server)** — in-memory accumulators, zero I/O between flushes:
  - Counters: feature-panel opens (from client batches), command usage by alias, error/warn count per Logger system, donation event counts.
  - Gauges: server `GetTotalMemoryUsageMb`, heartbeat/step time, DataStore budget headroom.
  - Flush: every ~30 min, jittered, as one aggregate JSON blob.
- **`TelemetryClient` (client)** — samples every ~60 s: FPS, `GetTotalMemoryUsageMb`, key memory tags (`GraphicsTexture`, `LuaHeap`, `Instances`, `Untracked`), device tier (touch/memory class). Aggregates locally (avg/p95/max), sends **one batched RemoteEvent every ~5 min**; feature-open counters ride the same batch. No per-event remotes.
- **Network attribution module** — hooks `NetworkManager` (+ raw remotes both directions): calls/sec + estimated bytes/sec per channel; top-N per flush window. *This is what finally answers "recv tinggi dari mana" with field data.* Also usable standalone as the in-Studio diagnostic report.
- **Transport (proposed, Open Decision 1):** `POST /game/{key}/v3/telemetry` (game-secret auth, v3 pattern) — one extra request per 30 min against a 500/min budget is negligible, and keeps license and telemetry payloads decoupled.

### VPS

- **Migration `0021_telemetry_events.sql`** — append-only `telemetry_events(id, game_id, kind, payload_json, kit_version, created_at)` + index `(game_id, created_at DESC)`, modeled on `license_beacons` (0019). Prune `> retention` on ingest.
- **Ingest** — `resource == "telemetry"` branch in `handleGameV3` (`v3-routes.js`), beside `deliveries`.
- **Read** — `GET /api/owner/telemetry` (owner-scoped, like `daily-stats`); `GET /api/owner/fleet` (**master-only**; Phase 0 version reads *existing* `games` + `license_beacons` columns — no new data needed).

### Dashboard

- **Phase 0 “Fleet” page (master-only):** version adoption, last-seen liveness, player counts, license state — built entirely from data the heartbeat already writes. Zero kit changes.
- **Later pages:** memory/FPS envelope per kit version (validates ADR 0005 in the field), error rates per version, network top-10 channels, feature usage; owner-facing “Venue Insights” variant.
- Deploy note: API + migration ship together (service restart auto-migrates); dashboard pages need a static rebuild/redeploy.

## Phases (smallest-durable-first; each independently shippable)

| Phase | Scope | Risk |
|---|---|---|
| **0** | Fleet view from existing data: `GET /api/owner/fleet` (master) + `Fleet.tsx` page | Backend/dashboard only — zero kit risk |
| **A** | VPS ingest: migration 0021 + v3 telemetry endpoint + retention prune | Backend only |
| **B** | Kit `TelemetryService` (server counters/gauges + 30-min flush) + `ClubKitConfig.Telemetry` key (schema + template) | Engine files; ships with next kit release |
| **C** | `TelemetryClient` sampler (FPS/memory/device + feature opens, 5-min batches) | Engine files |
| **D** | Network attribution module (top-N channels per flush; doubles as the Studio diagnostic) | Engine files |
| **E** | Dashboard telemetry pages (master health charts + owner Venue Insights) | Dashboard rebuild |
| *(parallel, optional)* | Native `AnalyticsService` events for buyer-side engagement (buyer-visible, zero infra) | Trivial, independent |

## Decisions (resolved by the owner, 2026-08-28)

1. **Transport:** separate `POST /game/{key}/v3/telemetry` endpoint (game-secret auth, v3 pattern).
2. **v1 metric set:** version/liveness (Phase 0) + **memory envelope (client total + key tags, server) + FPS p50/p95 + device mix** + **network top-N channels**. Error/warn counts and feature-open counts are *deferred* to a later iteration — not in v1.
3. **Opt-out default:** `Telemetry.Enabled = true` with a documented opt-out in `ClubKitConfig`.
4. **Retention:** 90 days raw, pruned at ingest.
5. **Venue Insights (buyer-facing):** later phase — vendor fleet first.
6. **Execution order:** Phases 0 + A first (done 2026-08-28), kit phases B–D ride a future kit release.

## Non-goals

- Per-player tracking, PII, chat capture, session recording — excluded by design, not by omission.
- Covert collection — the config key and upgrade-guide documentation make the pipeline visible to buyers.
- Real-time streaming telemetry — 30-min aggregate cadence is the design point (SSE stays a donations feature).

## Consequences

- +1 HTTP request / 30 min / server; payloads O(KB) — negligible against the shared 500/min budget, but it *is* the same budget: any future per-event temptation must be rejected here.
- New `ClubKitConfig.Telemetry` key = schema + template change (fill-forward, ADR 0001) — never edit buyer files directly.
- New kit services go through Init bags (ADR 0002); `count-locals.ps1` before release.
- SQLite growth bounded by ingest-time pruning; dashboard additions require a separate static redeploy.
