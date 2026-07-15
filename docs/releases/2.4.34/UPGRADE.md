# Upgrade v2.4.33 → v2.4.34

**Tanggal:** 2026-07-15

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save + Publish place
3. Jangan replace ClubKitConfig / Secrets
4. Rejoin live → F9 harus ASCII + KitVersion **2.4.34**

## What's new

- **Persistence Fabric** — kurangi DataStore queue warn + MessagingService `OverheadInvalidate` flood:
  - Global DataStore admission (`DataStoreScheduler`)
  - Overhead session write-behind + skip no-op writes
  - Cross-server invalidate batched (coalesce + skip origin + rate limit)
  - Likes leaderboard/metadata skip jika unchanged
  - Join ProfileLoader concurrency default 8→4

## Breaking

Tidak ada. Kill-switch tersedia di `Config.Persistence` jika perlu rollback perilaku lama.

## Config changes (engine)

Field baru di `Config.Persistence` (bukan ClubKitConfig buyer):

- `USE_LEGACY_PER_REPO_BUDGET_GATE` (default false)
- `SESSION_WRITE_BEHIND_ENABLED` / `USE_LEGACY_IMMEDIATE_OVERHEAD_WRITES`
- `USE_LEGACY_CROSS_SERVER_CACHE`
- `HEADROOM`, `MAX_INFLIGHT_PER_TYPE`, invalidate coalesce / token bucket, `METRICS_LOG_INTERVAL`

## QA

Ikuti [`docs/PERSISTENCE_FABRIC_QA.md`](../../PERSISTENCE_FABRIC_QA.md):

- [ ] Kit 2.4.34 di F9
- [ ] Studio solo idle — tanpa `DataStore request was added to queue`
- [ ] ~12 CCU — tidak spam `Too many publish requests` / OverheadInvalidate
- [ ] Private solo ping masih baseline; bandingkan Avg Data Ping vs pre-update saat ada player
