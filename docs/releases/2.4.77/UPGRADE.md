# Upgrade v2.4.76 → v2.4.77

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only update. Config/Secrets tidak diganti. Key config baru (`Sync.WutwutEnabled`) ter-fill-forward otomatis sebagai `false` — fitur tidak aktif sampai kamu nyalakan sendiri.

## What's new
- **Wutwut rapid dance restart (opt-in, default OFF)** — klik ulang cepat emote yang sedang aktif (≤ 0.32s) me-restart dance dengan fade 0 (efek stutter). Klik ulang lambat tetap toggle-off; ganti emote lain tetap crossfade normal. Leader wutwut → follower sync ikut restart.

## Config changes
| Key | Default | Notes |
|-----|---------|-------|
| `ClubKitConfig.Sync.WutwutEnabled` | `false` | Set `true` untuk mengaktifkan wutwut restart. Server tetap memvalidasi flag ini per request. |

Tidak ada field wajib di `ClubKitConfig` template.

Engine tuning (jarang perlu disentuh, `Config.Sync`): `WUTWUT_CHAIN_WINDOW` 0.32s, `WUTWUT_RESTART_FADE` 0, `WUTWUT_MIN_REQUEST_INTERVAL` 0.05s, `WUTWUT_CLIENT_MIN_FIRE_INTERVAL` 0.04s; rate bucket `SyncRateLimit.WUTWUT_RESTART` 20/2s.

## Breaking
- Tidak ada. Default off; perilaku klik emote tidak berubah sampai flag dinyalakan.

## QA setelah upgrade
- [ ] Default (flag off): klik ulang cepat emote yang sama tetap toggle-off
- [ ] Flag on: re-click ≤ ~0.3s → dance restart stutter; re-click > 0.32s → toggle-off
- [ ] Ganti emote A→B tetap crossfade 0.55s
- [ ] 2 player sync: leader wutwut → follower ikut restart se-phase
- [ ] Spam autoclicker → tidak ada track menumpuk (rate limit 20/2s)
