# Upgrade v2.4.24 → v2.4.25

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Dance preload: per-tier budgets (tier1 12 + tier2 20, envelope 32)
- Server dance track prewarm: global admission (2 concurrent / ~24 loads-sec), cancel on leave
- Donation workspace boards: coalesce rebuild/paint ~5s; skip unchanged fingerprint paint; bound missing-board retries (3)

## Kill switches / knobs

- `Config.Sync.USE_LEGACY_FLAT_PRELOAD_BUDGET = true` — flat MAX_ASSETS preload (pre-2.4.25)
- `Config.Sync.SERVER_DANCE_TRACK_PREWARM_MAX_CONCURRENT` / `MAX_LOADS_PER_SEC`
- `Config.Leaderboards.WORKSPACE_REBUILD_COALESCE_SEC` (0 = immediate)
- `Config.Leaderboards.SKIP_PAINT_WHEN_FINGERPRINT_UNCHANGED`
- `Config.Leaderboards.PAINT_MISSING_RETRY_MAX`

## Breaking

Tidak ada untuk ClubKitConfig / Secrets / remotes.

## QA

- [ ] Kit 2.4.25
- [ ] Dance panel ready without long join hitch; rare dances may cold-load once
- [ ] Join wave ~20 players: server Animation/prewarm does not step and fail to recover
- [ ] One donation / burst: boards update once after ~5s, no rebuild storm
- [ ] `/refreshleaderboard` (admin) still immediate
