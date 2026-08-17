# Changed Files — v2.6.4 → v2.6.5

## Summary
- 11 files changed
- Breaking: **no** (new config key is fill-forwarded; default keeps current behavior)

## Core — replace via Update Engine (source sync)
| Path | Change |
|------|--------|
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | Webhook donation fix: `getPlayerCashStats` no longer suppresses donor-profile API for unknown donors; `_pollNotifications` falls back to donor-profile API for `totalDonationAmount` when leaderboard cache misses |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicService.luau` | Read-only `init` branch (skip `loadAll`/poll, direct catalog seed), `isManageAllowed` false in read-only, `reloadLibraryFromStore` no-op |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/MusicRepository.luau` | `_readOnly` flag + `_setAsync` no-op guard |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Init/MusicBootstrap.luau` | Pass `readOnly` into `MusicRepository.new` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Map `MusicReadOnlyLibrary` → `MusicReadOnlyLibraryEnabled` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | `Features.MusicReadOnlyLibrary = false` default + FEATURE_MANIFEST label |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `FeatureFlags.MusicReadOnlyLibraryEnabled = false`; `SKIP_API_FOR_UNKNOWN_DONORS` marked legacy no-op |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **Template only.** Adds `Features.MusicReadOnlyLibrary = false` + comment. Buyer copies are fill-forwarded (additive) — never overwritten. |

## Tools / docs only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | v2.6.5 entry |
| `UPGRADE_PROGRESS.md` | Status + file tables |
| `CONTEXT.md` | Music library modes glossary |
