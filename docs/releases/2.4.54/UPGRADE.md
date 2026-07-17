# Upgrade v2.4.53 → v2.4.54

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place
3. Set Graphics to any preset, keep **Hide donation world effect** off, then run `/testcash 150000`

## What's new

### Fixed
- Nuke / Smite / BlackHole no longer get silently blocked by Graphics Low or `HideAllParticles`.
- World effects remain disabled only when the player explicitly hides donation world effects or donation VFX scale is effectively zero.
- Client and server logs now show the resolved world effect and whether it was dispatched or skipped.

## Config changes

No buyer `ClubKitConfig` or `Secrets` changes required.

## QA setelah upgrade

- [ ] `/testcash 150000` logs `worldEffect=Nuke` server-side and `World effect dispatch` client-side
- [ ] `/testcash 300000` dispatches `Smite4`
- [ ] `/testcash 600000` dispatches `BlackHole`
- [ ] Graphics Low still permits world VFX when the dedicated hide toggle is off
- [ ] Enabling **Hide donation world effect** logs `World effect skipped`
- [ ] F9 banner shows KitVersion **2.4.54**
