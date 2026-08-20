# Changed Files — v2.7.0 → v2.7.1

## Summary
- 11 Luau/source files changed (+ release docs)
- Breaking: no

## Core — replace via Update Engine (source sync)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.7.0 → 2.7.1, BuildId bump |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +`Config.Couple.SHOW_CHAT_TAG = true` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Overlay `Features.ShowCoupleChatTag` → `Config.Couple.SHOW_CHAT_TAG` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`defaults.Features.ShowCoupleChatTag` + FEATURE_MANIFEST entry |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/TextFilterUtil.luau` | +`resolveFilterAuthorUserId()` (group-owner resolve) + `GroupService` import |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/DonationLeaderboardRepository.luau` | Community-name filter author uses resolver |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | Provider-donor name filter fallback author uses resolver |
| `src/StarterPlayerScripts/.../Client/Controllers/ChatTagsController.luau` | Gate coupleTag render on `SHOW_CHAT_TAG ~= false` |

## Buyer-owned — review manually, do NOT replace
| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` (template) | +`Features.ShowCoupleChatTag = true` (additive; fill-forwarded to live buyer configs) |

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` / `PLUGIN_VERSION` 2.7.0 → 2.7.1 |
| `VERSION` | 2.7.1 |
| `CHANGELOG.md` | v2.7.1 entry |
| `UPGRADE_PROGRESS.md` | unreleased rows documented |
| `AGENTS.md` | project-skills list (+`mcp-studio`) |
| `docs/releases/2.7.1/` | this folder |
