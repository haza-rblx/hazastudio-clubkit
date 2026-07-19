# Changed Files — v2.4.58 → v2.4.59

## Summary
- 1 new module + ~10 core engine files + version/docs
- Breaking: no

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CharacterReady.luau` | **NEW** — parts/adorn/anim; AppearanceLoaded Head; stream pivotTo |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SessionCommandService.luau` | `/re` LoadCharacter + stream; bring/to pivotTo; lock timeout |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SyncService.luau` | restorePreparedRefresh waits/retries Animator |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ProximityInterestService.luau` | recomputeNow + PartsReady CharacterAdded |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/OverheadController.luau` | CharacterReady adorn; recomputeNow; remove Avatar:Refreshed |
| `src/StarterPlayerScripts/.../Client/Controllers/OverheadController.luau` | Head rebind via CharacterReady |
| `src/StarterPlayerScripts/.../Client/Utils/StickerBillboardAnimator.luau` | DEFAULT_ADORNEE_PRIORITY watch |
| `src/ReplicatedStorage/.../Shared/UI/LoadingScreenUI.luau` | Head suppress rebind; DescendantAdded hide |
| `src/ReplicatedStorage/.../Shared/ContextModule/AnimatorUtils.luau` | isCharacterReady → anim tier |
| `src/ReplicatedStorage/.../Shared/Constants/Config.luau` | REFRESH_LOCK / MSG_REFRESH_BUSY; HEAD_STABLE comments |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.59 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep — no required merge |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.59 |
| `CHANGELOG.md` | [2.4.59] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.59/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION 2.4.59 |
