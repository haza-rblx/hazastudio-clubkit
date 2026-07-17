# Changed Files — v2.4.56 → v2.4.57

## Summary
- 9 core engine files + version/docs
- Breaking: no

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `LB_READ_RETRY_ATTEMPTS`, `RANK_RESOLVE_DELAY_SEC`, `RANK_RESOLVE_JITTER_SEC` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/DonationLeaderboardRepository.luau` | Cache/last-good before lockout; single GetSortedAsync attempt |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/AvatarLikeRepository.luau` | `LB_READ_RETRY_ATTEMPTS` for likes LB |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/OverheadService.luau` | Deferred rank resolve after LB pre-warm |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SyncService.luau` | Dance switch hard-stop; sync-join phase snap |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/CarryService.luau` | Hard-stop Action4 before carry; refuse dance while carried |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/ContextModule/AnimatorUtils.luau` | Expected anim id / weight for dance track; exclude Carry_* |
| `src/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/PaidBroadcastController.luau` | Free send UI for canAnnounce |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/PaidBroadcastController.luau` | Server free path for canAnnounce |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.57 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep — no required merge |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.57 |
| `CHANGELOG.md` | [2.4.57] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.57/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION |
