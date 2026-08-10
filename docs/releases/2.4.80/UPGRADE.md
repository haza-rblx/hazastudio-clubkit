# Upgrade v2.4.79 → v2.4.80

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. (Optional) Review `ClubKitConfig.Sync.SwitchFade*` if you want the new 0.45 feel

Engine-only update for UI. Template `SwitchFade` defaults changed in repo; **Update Engine does not overwrite your existing ClubKitConfig values.**

## What's new
- **Wutwut soft press highlight** — with `Features.WutwutDance = true`, emote rows no longer stick solid white while playing. Press shows a soft gray tint with short fade in/out (desktop + mobile dance panel).
- **Default A→B switch fade** — template / engine default `SwitchFadeIn` / `SwitchFadeOut` / `SwitchInputCooldown` `0.55` → `0.45`.

## Config changes
| Key | New template default | Notes |
|-----|----------------------|--------|
| `ClubKitConfig.Sync.SwitchFadeIn` | `0.45` | Existing place values kept as-is |
| `ClubKitConfig.Sync.SwitchFadeOut` | `0.45` | Keep equal to SwitchFadeIn |
| `ClubKitConfig.Sync.SwitchInputCooldown` | `0.45` | Keep ≥ SwitchFade* |

If your place still has `0.55` (or playtest `0.30`) and you want the release default feel, set all three to `0.45`.

## Breaking
- Tidak ada.

## QA setelah upgrade
- [ ] Wutwut ON → press row = soft gray fade, release = dark again (no sticky white)
- [ ] Wutwut OFF → playing row still sticky white/"played"
- [ ] Mobile dance panel: same press tint behavior
- [ ] Switch A→B feels slightly smoother than 0.30 / snappier than 0.55 (if config is 0.45)
- [ ] Wutwut same-emote spam restart still works
