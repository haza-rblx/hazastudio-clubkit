# Changed Files — v2.4.60 → v2.4.61

## Summary
- 5 core engine files (+ 1 new) + version/docs
- Breaking: no

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/Utils/RefreshCameraPreserve.luau` | **NEW** — snapshot/restore camera across LoadCharacter |
| `src/StarterPlayerScripts/.../Client/Init/ClientModuleBag.luau` | Export RefreshCameraPreserve |
| `src/StarterPlayerScripts/.../Main.client.luau` | init RefreshCameraPreserve |
| `src/ServerScriptService/.../SessionCommandService.luau` | Set/clear `ClubKitPendingCharacterRefresh` |
| `src/ReplicatedStorage/.../Config.luau` | `PENDING_REFRESH_ATTRIBUTE` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.61 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.61 |
| `CHANGELOG.md` | [2.4.61] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.61/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION 2.4.61 |
