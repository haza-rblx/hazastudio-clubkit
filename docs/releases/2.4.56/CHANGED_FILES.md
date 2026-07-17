# Changed Files — v2.4.55 → v2.4.56

## Summary
- 6 core engine files changed (client only)
- Breaking: no

## Core — replace via source sync / RBXM
| Path | Change |
|------|--------|
| `Client/Utils/WorldEffectFlight.luau` | Added `isAbortError()` — matches Roblox's wrapped `WorldEffectAborted` error string |
| `Client/Effects/EffectDonate/Blossom/init.client.luau` | `spawnAbortable` + marker `pcall` wrappers; quiet abort |
| `Client/Effects/EffectDonate/BlackHole/init.client.luau` | `spawnAbortable` for background threads; quiet abort |
| `Client/Effects/EffectDonate/LocalNuke/init.client.luau` | Quiet abort via `isAbortError` |
| `Client/Controllers/DonationNotificationController.luau` | World effect dispatch/skip diagnostics demoted `info` → `debug` |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | none |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | none |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.55 → 2.4.56 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` bump |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` bump |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | `KIT_VERSION` bump |
| `CHANGELOG.md`, `UPGRADE_PROGRESS.md` | release notes |
