# Changed Files — v2.4.63 → v2.4.64

## Summary
- ~18 engine files + new ChatTagStore + version/docs
- Breaking: no
- Buyer config: none (engine-only)

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/.../Domain/Types.luau` | `ChatTagEntry` |
| `src/ReplicatedStorage/.../Constants/Config.luau` | `REMOTE_CHAT_TAG_SYNC`; join timeout 10s; inflight 8; ProfileLoader 8 |
| `src/ReplicatedStorage/.../Utils/DataStoreScheduler.luau` | `inflight_saturated` vs `budget_low` |
| `src/ReplicatedStorage/.../Utils/BudgetGate.luau` | refuse with `budget_low` |
| `src/ServerScriptService/.../Init/EarlyRemotes.luau` | ensure `ChatTagSync` |
| `src/ServerScriptService/.../Controllers/OverheadController.luau` | ChatTag publish/batch/remove; authoritative gate |
| `src/ServerScriptService/.../Services/OverheadService.luau` | `rankLookupOk`; rank cache `{rank,ok}`; LKG |
| `src/ServerScriptService/.../Repositories/OverheadRepository.luau` | negative-cache only budget |
| `src/ServerScriptService/.../Repositories/ProfileRepository.luau` | same |
| `src/ServerScriptService/.../Repositories/SettingsRepository.luau` | same |
| `src/ServerScriptService/.../Repositories/AvatarLikeRepository.luau` | same |
| `src/ServerScriptService/.../Repositories/StickerRepository.luau` | same |
| `src/ServerScriptService/.../Repositories/ProfileLoader.luau` | transient + no early-break on inflight |
| `src/ServerScriptService/.../Repositories/DonationLeaderboardRepository.luau` | retry new error strings |
| `src/StarterPlayerScripts/.../Client/Services/ChatTagStore.luau` | **new** — global roster + catch-up |
| `src/StarterPlayerScripts/.../Client/Controllers/ChatTagsController.luau` | ChatTagStore first; no Guest invent |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.64 |

## Buyer-owned — review manual, jangan replace utuh
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep (no new keys) |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.64 |
| `CHANGELOG.md` | [2.4.64] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.64/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.64 |
