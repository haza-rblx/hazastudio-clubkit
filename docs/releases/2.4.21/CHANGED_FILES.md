# Changed Files — v2.4.20 → v2.4.21

## Summary
- 9 core engine files + version/docs
- Breaking: no (behavior: paint-limit enrich, dance preload cap, HttpApi on)

## Core — replace via Update Engine / source sync

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/LeaderboardIdentity.luau` | TTL + negative cache, batch enrich, isStale noop, rbxthumb |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/HttpApi.luau` | Real multi-id UserInfos batch |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | HttpApi.ENABLED=true; DANCE_PRELOAD_MAX_ASSETS; prewarm MAX 8 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.21 |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/DonationController.luau` | Slice enrich to paint limits |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/OverheadController.luau` | Snapshot-on-enter cached/S1 |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/OverheadService.luau` | getGroups self-Cache.set |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/DonationLeaderboardRepository.luau` | Drop display==username resolve; rbxthumb |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/AvatarLikeRepository.luau` | Identity only if metadata missing; rbxthumb |
| `src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/DanceWarmupService.luau` | Cap preload tier1/tier2/full |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep — no required merge |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.21 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.21 |
| `CHANGELOG.md` | [2.4.21] section |
| `docs/releases/2.4.21/UPGRADE.md` | Buyer upgrade guide |
| `docs/releases/2.4.21/CHANGED_FILES.md` | This file |
| `UPGRADE_PROGRESS.md` | Reset after release |
