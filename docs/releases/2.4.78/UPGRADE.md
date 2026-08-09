# Upgrade v2.4.77 → v2.4.78

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only update. Config/Secrets tidak diganti. Key `Features.WutwutDance = false` ter-fill-forward otomatis.

## What's new
- **Wutwut gate sekarang toggle Features** — on/off wutwut pindah ke `ClubKitConfig.Features.WutwutDance` dan **muncul di panel plugin** → Config → Features → "Wutwut dance restart" (grup Music & dance). Tidak perlu edit file config manual lagi.

## Config changes
| Key | Default | Notes |
|-----|---------|-------|
| `ClubKitConfig.Features.WutwutDance` | `false` | Canonical gate. Bisa di-toggle dari panel plugin. |
| `ClubKitConfig.Sync.WutwutEnabled` | — | **Legacy alias (2.4.77)** — `true` di sini tetap menyalakan fitur. Boleh dihapus dari config; pindahkan ke `Features.WutwutDance`. |

## Breaking
- Tidak ada. Default tetap off.

## QA setelah upgrade
- [ ] Plugin → Config → Features menampilkan "Wutwut dance restart" (default off)
- [ ] Toggle on dari panel → config ter-patch → playtest: re-click cepat emote aktif = restart stutter
- [ ] Toggle off → perilaku klasik (klik emote sama = toggle off)
