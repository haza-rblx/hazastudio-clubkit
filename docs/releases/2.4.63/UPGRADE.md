# Upgrade v2.4.62 → v2.4.63

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. (Opsional) Cek `ClubKitConfig.Sync` — section baru untuk tune fade dance; place lama otomatis dapat default via fill-forward

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti utuh — key `Sync` diisi additive jika belum ada.

## What's new
- **`/re` in-place** — refresh appearance tanpa `LoadCharacter` / hop spawn / camera fight; dance lanjut di phase yang sama; anim pack website ikut apply
- **Dance crossfade salon-style** — matching Stop+Play fade; anti-stack zombie; defaults ~0.45–0.55s
- **`ClubKitConfig.Sync`** — buyer atur `FadeIn` / `SwitchFadeIn` / `SyncJoinFade` / `SwitchInputCooldown`
- Sync join phase lebih andal (sample leader + Length retry)
- Admin giftcard/title hardening + title text filter
- Donation cash notif poll lebih cepat (5s / burst 2s)
- Early flush saat delayed server restart (`ServerRestartScheduled`)

## Config changes
| Field | Notes |
|-------|--------|
| `ClubKitConfig.Sync.FadeIn` / `FadeOut` | Idle ↔ dance (default 0.45) |
| `ClubKitConfig.Sync.SwitchFadeIn` / `SwitchFadeOut` | Ganti dance A→B (default 0.55; samakan) |
| `ClubKitConfig.Sync.SyncJoinFade` | Ikut sync ke leader (default 0.4) |
| `ClubKitConfig.Sync.SwitchInputCooldown` | Jeda klik emote; set ≥ SwitchFade* (default 0.55) |

## Breaking
Tidak ada schema break. Behavior: `/re` tidak lagi respawn; dance switch pakai soft crossfade (bukan hard cut).

## QA setelah upgrade
- [ ] `/re` sambil diam — appearance refresh, kamera still, tidak hop spawn
- [ ] `/re` sambil dance — phase lanjut, anim pack website ikut
- [ ] Ganti dance — crossfade soft, tidak “lengan patah”
- [ ] Sync ke leader — dance + phase benar tanpa harus switch dulu
- [ ] (Opsional) Ubah `ClubKitConfig.Sync.SwitchFadeIn` → restart play → terasa beda
- [ ] F9 banner KitVersion **2.4.63**
