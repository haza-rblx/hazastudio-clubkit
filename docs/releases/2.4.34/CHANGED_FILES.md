# Changed Files — v2.4.33 → v2.4.34

## Summary

- ~15 files changed (+ 2 new util modules)
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.34 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.Persistence`; ProfileLoader concurrency 4 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | Optional `flushSession` on IOverheadRepository |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/BudgetGate.luau` | Adapter → DataStoreScheduler |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CrossServerCache.luau` | InvalidateBus coalesce / skip-origin / rate limit |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/DataStoreScheduler.luau` | **New** — global DS admission |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/PlayerSessionStore.luau` | **New** — write-behind sessions |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | Session flush + fabric metrics job |
| `src/ServerScriptService/.../AvatarLikeRepository.luau` | Skip unchanged LB/metadata; gated ListKeys |
| `src/ServerScriptService/.../FavoritesRepository.luau` | Leave dirty-only |
| `src/ServerScriptService/.../MusicFavoritesRepository.luau` | Leave dirty-only |
| `src/ServerScriptService/.../OverheadRepository.luau` | Session write-behind + key mutex |
| `src/ServerScriptService/.../SettingsRepository.luau` | Skip no-op + key mutex |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change required |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | No change required |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.34 |
| `CHANGELOG.md` | [2.4.34] |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.34 |
| `docs/PERSISTENCE_FABRIC_QA.md` | QA checklist |
| `docs/releases/2.4.34/UPGRADE.md` | Buyer upgrade guide |
| `docs/releases/2.4.34/CHANGED_FILES.md` | This file |
| `UPGRADE_PROGRESS.md` | Reset after release |
