# Changed Files — v2.4.59 → v2.4.60

## Summary
- 2 core engine files + version/docs
- Breaking: no

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CharacterReady.luau` | `waitForPositionRestore` (PartsReady + in-world + AppearanceLoaded) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SessionCommandService.luau` | Single-flight `/re` restore; pending until pivot; re-assert drift |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.60 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.60 |
| `CHANGELOG.md` | [2.4.60] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.60/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION 2.4.60 |
