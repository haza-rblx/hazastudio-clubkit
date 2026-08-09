# Upgrade v2.4.78 → v2.4.79

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only update. Config/Secrets tidak diganti.

## What's new
- **Wutwut restart works with panel cooldown** — same-emote spam no longer blocked by `SwitchInputCooldown`.
- **Same-dance re-play after stop** — fixing stuck `pending` so stop → click same dance plays again (no need to pick another first).
- **Longer wutwut chain window** — `0.32s` → `0.45s` for more comfortable restart spam.

## Config changes
- Tidak ada key config buyer baru.
- Optional playtest feel (place-only, not forced by this release): `ClubKitConfig.Sync.SwitchFadeIn/Out` + `SwitchInputCooldown` can be lowered (e.g. `0.30`) for snappier A→B switches.

## Breaking
- Tidak ada.

## QA setelah upgrade
- [ ] `Features.WutwutDance = true` → spam emote aktif cepat = restart stutter (bukan stop)
- [ ] Play dance → stop (klik same pelan) → klik same lagi = play ulang
- [ ] Ganti dance A→B tetap crossfade normal
