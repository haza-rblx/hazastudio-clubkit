# Upgrade v2.4.70 → v2.4.71

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place (Config fill-forward menambah `Features.AdminHub` / `Features.LegacySyncBhms` jika belum ada — default **false**)
3. **Rebuild / reinstall Studio plugin** dari `tools/ClubKitPackagerPlugin` (panel Aurora Dusk + hot-reload)
4. QA checklist di bawah

`ClubKitConfig` / `Secrets` tidak di-replace utuh. Update Engine **merge additive** key Features yang hilang.

## What's new
- **Admin Hub** (`04-AdminHub`) — opt-in via `Features.AdminHub = true` (default off; classic Admin Panel tetap)
- **Daily boards ×3** — combined / Robux / cash (`DailyDonations*`); cash format `RP `
- **UI motion** — MotionPresets, PressFeedback, UISpring (TopMenu + panels)
- **Cinematic Dock** — tombol top menu disembunyikan untuk non-admin
- **Studio plugin** — panel Swiss-knife “Aurora Dusk” (Config write-back, Diagnostics, Engine, Tools, Packager, Settings) + optional hot-reload
- **Docs hub** — Home / Setup / Updates + i18n ID/EN/JA/ES

## Config changes
| Field | Default | Notes |
|-------|---------|--------|
| `Features.AdminHub` | `false` | Fill-forward. Set `true` + pastikan GUI `04-AdminHub` di StarterGui |
| `Features.LegacySyncBhms` | `false` | Place-pack SyncBhms only — jangan nyalakan kecuali place pakai pack |

## Breaking
Tidak ada. Admin Hub & LegacySyncBhms default **off**.

## QA setelah upgrade
- [ ] F9 / KitVersion **2.4.71**
- [ ] `ClubKitConfig.Features` punya `AdminHub` + `LegacySyncBhms` (atau runtime default false)
- [ ] AdminHub false → topbar Admin = classic panel
- [ ] AdminHub true → hub gallery + command sheets; Cinematic dock hanya admin
- [ ] Daily boards (jika dipasang) combined / robux / cash tampil; cash `RP `
- [ ] Plugin: panel load, Check Update / Update Engine OK
- [ ] Docs: switch ID↔EN pada Home/Setup/Updates
