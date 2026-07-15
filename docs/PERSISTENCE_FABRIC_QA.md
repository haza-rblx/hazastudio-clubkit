# Persistence Fabric — QA checklist

Gunakan sebelum rilis patch yang berisi Persistence Fabric.

## Kill switches (`Config.Persistence`)

| Flag | Effect |
|------|--------|
| `USE_LEGACY_PER_REPO_BUDGET_GATE = true` | BudgetGate snapshot lama (tanpa DataStoreScheduler) |
| `USE_LEGACY_IMMEDIATE_OVERHEAD_WRITES = true` / `SESSION_WRITE_BEHIND_ENABLED = false` | Overhead UpdateAsync langsung |
| `USE_LEGACY_CROSS_SERVER_CACHE = true` | CrossServerCache debounce 1s/user saja |
| `METRICS_LOG_INTERVAL = 0` | Matikan snapshot DEBUG |

## Studio

1. [ ] 1 player idle 5 menit — **0** `DataStore request was added to queue`
2. [ ] 8–12 clients join staggered — steadystate tanpa queue warn; `budget_exhausted` dari kit boleh
3. [ ] Edit settings lalu leave — flush sekali; leave tanpa edit settings/favorites — **0** save favorit
4. [ ] F9 Server: tidak spam `Too many publish requests` / `OverheadInvalidate` (coalesce)

## Live

1. [ ] Private solo — NetworkPing ~30–50 ms (baseline kamu)
2. [ ] ~12 CCU, jauh dari crowd — MessagingService clean; bandingkan Avg Data Ping vs pre-fabric
3. [ ] ASCII / KitVersion confirm engine ter-update

## Metrics

Server log DEBUG tiap `METRICS_LOG_INTERVAL` (default 60s): `PersistenceFabric snapshot` dengan `scheduler` / `invalidateBus` / `session`.
