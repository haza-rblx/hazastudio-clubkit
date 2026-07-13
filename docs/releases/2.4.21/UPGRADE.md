# Upgrade v2.4.20 → v2.4.21

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- Fix leaderboard **UserService storm** (enrich hanya baris yang di-paint + cache/batch identity)
- Fix overhead **GroupService storm** (proximity pakai cached/S1 payload; groups self-cache)
- `HttpApi` cache on by default; real multi-id UserInfos batch
- Dance ContentProvider preload capped (`DANCE_PRELOAD_MAX_ASSETS = 32`) — turunin Animation RAM client

## Breaking / behavior changes

- Leaderboard workspace payload lists are trimmed to paint limits (20) before identity enrich (boards still show top 20)
- Dance assets beyond the preload cap load on first play (slight first-play latency for rare dances)
- None for ClubKitConfig / Secrets / remotes / DataStore keys

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.HttpApi.ENABLED` | now `true` | Buyer ClubKitConfig tidak perlu merge kecuali kamu override HttpApi |
| Engine `Config.Sync.DANCE_PRELOAD_MAX_ASSETS` | `32` | Opsional override di buyer config jika ada mirror Sync |
| Buyer `Secrets` | — | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.21** after Update Engine
- [ ] Server Network 5–10 menit: UserService / Players / GroupService jauh lebih rendah dari sebelum upgrade
- [ ] Data ping lebih stabil (bukan stuck 400–600 ms dari API storm)
- [ ] Leaderboard top 20 paint nama/thumbnail OK (termasuk DisplayName == Username)
- [ ] Overhead join + masuk View_Range tetap tampil
- [ ] Client Memory → Animation turun vs baseline full-catalog preload
- [ ] ClubKitConfig + Secrets unchanged
