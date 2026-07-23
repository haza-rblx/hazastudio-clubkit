# Changed Files — v2.4.64 → v2.4.65

## Summary
- 2 core client files + version/docs
- Breaking: no
- Buyer config: none

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/UI/DancePanelUIBinder.luau` | Fav badge-only on Dance/Pose; Favorites tab rebuild + scroll; no cross-cat inject |
| `src/StarterPlayerScripts/.../Main.client.luau` | Favorite toggle via store subscribe only |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.65 |

## Buyer-owned — review manual, jangan replace utuh
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.65 |
| `CHANGELOG.md` | [2.4.65] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.65/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.65 |
