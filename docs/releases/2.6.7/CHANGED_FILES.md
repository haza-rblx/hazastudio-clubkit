# Changed Files — v2.6.6 → v2.6.7

## Summary
- 16 files changed
- Breaking: no

## Core — replace via Update Engine / source sync
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/TextFilterUtil.luau` | NEW — canonical text filter module (filterForBroadcast / filterForUser / normalize / hashFallback) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ProfileCommandService.luau` | G1: statusText + bio filtered at write; reject with MSG_FILTER_FAILED on failure |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/AvatarContextService.luau` | G2: per-viewer filter now uses author userId; migrated to TextFilterUtil |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | G3: unlinked external donor display names filtered (memoized, hash fallback); G5: no raw-name fallback on Robux path; inline filter migrated |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicService.luau` | G4: manage playlist/track names + creators filtered at write |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/DonationLeaderboardRepository.luau` | G6: communityName filtered (author = CreatorId) before DataStore write |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/ShopController.luau` | Migrated inline filter to TextFilterUtil |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/CrowdController.luau` | Migrated inline filter to TextFilterUtil |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/AdminController.luau` | Migrated inline filter to TextFilterUtil |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Tools/SignServer.luau` | Migrated inline filter to TextFilterUtil (single-attempt preserved) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ProfileMenuService.luau` | Migrated inline filter to TextFilterUtil |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/GenericBroadcastService.luau` | Migrated inline filter to TextFilterUtil |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Nothing required. Optional: set `Features.VipOnCommunityJoin = true` if you want VIP-on-join (not part of this release — place-specific). |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` → 2.6.7 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → 2.6.7 |
| `CHANGELOG.md`, `VERSION`, `UPGRADE_PROGRESS.md`, `docs/adr/0004-text-filtering-policy.md`, `docs/releases/2.6.7/*` | Release bookkeeping |
