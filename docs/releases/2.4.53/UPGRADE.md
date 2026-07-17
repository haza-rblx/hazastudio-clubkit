# Upgrade v2.4.52 → v2.4.53

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place

## What's new

### Fixed
- **Nuke world effect crash** — `LocalNuke` require path for `DonationVfxClientGate` fixed (was looking under kit root instead of `Client/Utils`).

### Changed
- **World VFX follows donation notif queue** — Nuke / Smite4 / BlackHole start when that donation's notification starts showing (client `WorldEffectDispatch`), instead of a server serial wait of 90–240s. Previous world effect aborts when the next notif begins.

## Config changes

Engine only (`Types.DonationNotifPayload.worldEffect`, legacy note on `WORLD_EFFECT_DURATIONS`). No buyer `ClubKitConfig` fields required.

## QA setelah upgrade

- [ ] `/testcash` high tier — nuke rocket plays without `Utils is not a valid member` error
- [ ] Spam several `/testcash` — world FX advances with each notif (~4–8s), not stuck waiting minutes
- [ ] Next donation notif aborts previous world FX (no stacked nukes)
- [ ] Aura / camera shake still play on cash donation
- [ ] F9 / banner shows KitVersion **2.4.53**
