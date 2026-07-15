# Changed Files — v2.4.41 → v2.4.42

## Summary

- Join DataStore `budget_exhausted` storm mitigation (critical vs secondary loads)
- ClubKitConfig schema fill-forward + Update Engine additive Source patch
- ClubKitShowcase moved to `tools/dev/` (never ship with engine sync)
- Plugin Update Engine dock UI + toolbar always opens panel
- Breaking: soft only (secondary join delay ~4s; Showcase not in engine tree)

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `Shared/Constants/Config.luau` | `JOIN_READ_RETRY_ATTEMPTS`, `ProfileLoader.SECONDARY_JOIN_DELAY_SEC`, `RETRY_DELAYS` |
| `Shared/Config/ClubKitConfigSchema.luau` | **New** — fill-forward defaults |
| `Shared/Config/ConfigBootstrap.luau` | Schema merge / fill-forward |
| `Shared/Config/ClubKitShowcase.luau` | **Removed** from engine (→ `tools/dev/`) |
| `Server/Main.server.luau` | Critical/secondary join enqueue; ProfileLoader overhead requeue |
| `Server/Repositories/ProfileLoader.luau` | `enqueueKindDeferred`; retry / budget_exhausted handling |
| `Server/Repositories/OverheadRepository.luau` | Join GetAsync attempts |
| `Server/Repositories/SettingsRepository.luau` | Join GetAsync attempts |
| `Server/Repositories/ProfileRepository.luau` | Join GetAsync attempts |
| `Server/Repositories/StickerRepository.luau` | Load GetAsync attempts |
| `Server/Repositories/MusicFavoritesRepository.luau` | Join GetAsync attempts |
| `Server/Repositories/FavoritesRepository.luau` | Join GetAsync attempts |
| `Server/Repositories/AvatarLikeRepository.luau` | getSummary GetAsync attempts |
| `Server/Controllers/SettingsController.luau` | Deferred settings enqueue |
| `Server/Services/StickerService.luau` | Deferred stickers enqueue |
| `Server/Init/MusicBootstrap.luau` | Deferred music_favorites enqueue |
| `KitProduct.luau` | KitVersion 2.4.42, BuildId 20260715 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template comment updates OK; live place: fill-forward additive only |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/dev/ClubKitShowcase.luau` | Dev-only showcase |
| `tools/ClubKitPackagerPlugin/plugin/*` | ConfigPatchCore, UpdaterPanel, Manifest 2.4.42, dock open |
| `tools/ClubKitPackagerPlugin/plugin-build/*` | Synced plugin build |
| `tools/ClubKitPackagerPlugin/UpdatePluginGUI.rbxmx` | Update Engine dock design |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` / `AGENTS.md` | Rilis 2.4.42 |
| `docs/releases/2.4.42/*` | Upgrade guide |
