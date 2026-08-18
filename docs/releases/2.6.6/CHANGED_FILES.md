# Changed Files — v2.6.5 → v2.6.6

## Summary
- 5 files changed
- Breaking: no

## Core — replace via Update Engine / source sync
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.Level.MAX_LEVEL` default `100` → `0` (unlimited); registered `DonationPushIn` in CinematicDock `MOVEMENT_OPTIONS` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CinematicCameraModes.luau` | New `Character.DonationPushIn` mode (pure dolly zoom, FOV 54→42, no orbit) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/CinematicDockController.luau` | Donation cinematic `movement` swapped `DonationOrbit` → `DonationPushIn` |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Nothing required. Optional: cap levels again by setting a `MAX_LEVEL`-style override if you had one; engine default is now unlimited. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` → 2.6.6 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → 2.6.6 |
| `CHANGELOG.md`, `VERSION`, `UPGRADE_PROGRESS.md`, `docs/releases/2.6.6/*` | Release bookkeeping |
