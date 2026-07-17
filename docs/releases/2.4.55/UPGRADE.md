# Upgrade v2.4.54 → v2.4.55

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place
3. Start a fresh Play session, then run `/testcash 150000`

## What's new

### Fixed
- `WorldEffectDispatch` now reuses one BindableEvent for all EffectDonate listeners and notification fires.
- Nuke, Smite4, and BlackHole can now receive the already-correct dispatch emitted by the donation notification queue.

## Config changes

No buyer `ClubKitConfig` or `Secrets` changes required.

## QA setelah upgrade

- [ ] F9 banner shows KitVersion **2.4.55**
- [ ] `/testcash 150000` logs `World effect dispatch` and visibly starts Nuke
- [ ] `/testcash 300000` visibly starts Smite4
- [ ] `/testcash 600000` visibly starts BlackHole
- [ ] Consecutive notifications replace the previous world effect instead of stacking
