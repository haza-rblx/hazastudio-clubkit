# Changed Files — v2.4.42 → v2.4.43

## Summary

- Perf Wave A/B: session flush, favorites owner remotes + debounce, donation VFX/phone GPU
- Dance: full-catalog PreloadAsync, optimistic click + predictive local, cheap row selection
- Loading: intro logo+blur; dance tier1 warm during load
- Breaking: soft only (favorites remotes, unreliable nuke, longer loading hold)

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `Shared/Utils/PlayerSessionStore.luau` | Flush generation + single-flight |
| `Shared/Constants/Config.luau` | Favorites debounce/remotes; dance full catalog; loading INTRO_*; ClientBoot warm/hold |
| `Shared/UI/LoadingScreenUI.luau` | Intro blank+logo+blur; delay cinematic |
| `Shared/OverheadEffects/TitleColorPreset/SharedTick.luau` | MaxDistance cull |
| `Server/Repositories/FavoritesRepository.luau` | Memory + owner remote + debounce |
| `Server/Repositories/MusicFavoritesRepository.luau` | Same |
| `Server/Controllers/SyncController.luau` | Owner favorites sync |
| `Server/Services/SyncService.luau` | Prewarm from repo memory; favorites dep |
| `Server/Services/DonationEffectService.luau` | DonationEffect tag; unreliable nuke remote |
| `Server/Main.server.luau` | Remotes; nuke UnreliableRemoteEvent |
| `Server/Init/EarlyRemotes.luau` | `REMOTE_SYNC_FAVORITES` |
| `Server/Init/MusicBootstrap.luau` | Music favorites owner sync |
| `Client/Controllers/SyncController.luau` | Favorites remote; optimistic dance + predictive local |
| `Client/Controllers/MusicPlayerController.luau` | Favorites remote |
| `Client/Controllers/SettingsController.luau` | Phone Low; HideAllParticles attr |
| `Client/Controllers/CinematicDockController.luau` | Magnifier off phone/Low |
| `Client/Controllers/DonationNotificationController.luau` | Marquee ~30 Hz |
| `Client/Controllers/AvatarContextController.luau` | Prewarm setActive |
| `Client/Services/DanceWarmupService.luau` | Full catalog PreloadAsync; warmAnimation |
| `Client/UI/DancePanelUIBinder.luau` | Dirty-row selection |
| `Client/Utils/DonationVfxClientGate.luau` | **NEW** |
| `Client/Utils/AvatarPrewarmPool.luau` | setActive |
| `Client/Utils/NukeEffectController.luau` | UnreliableRemoteEvent |
| `Client/Effects/EffectDonate/*/init.client.luau` | DonationVfxClientGate |
| `Main.client.luau` | Dance warm during loading; hold finish; favorites Attribute removed |
| `KitProduct.luau` | KitVersion 2.4.43, BuildId 20260716 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Jangan replace; logo intro = `Branding.LogoImage` |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.43 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest` | KIT_VERSION 2.4.43 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.43 |
| `docs/releases/2.4.43/*` | Upgrade guide |
