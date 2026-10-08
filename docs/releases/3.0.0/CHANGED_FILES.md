# Changed Files — v2.12.0 → v3.0.0

Diff base: `v2.12.0` (`aaca1f9`) to the release commit. Generated from `git diff --name-status v2.12.0` plus new untracked files. Status letters: **A** added, **M** modified, **D** deleted, **R** renamed.

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 332 (A 147, M 167, D 15, R 3) |
| Breaking | **yes.** Music panel GUI replaced; music is web-only; retired config keys; `Music.MaxVolume` default 4; `AvatarContext.DailyLikeReset` behaviour. See [UPGRADE.md](UPGRADE.md). |
| DataStore | Additive only. New: `CoupleLeaderboard_v1`, `LevelLeaderboard_v1`, `StreakLeaderboard_v1`, `EventBoardCache_v1`. MemoryStore map `ClubKitLeaderboardCache_v2`. Extended: `VenueQuestProgress_v1` (`claims`), `Settings_v1` (`accent`). Nothing renamed or removed. |
| Config | Schema and template gained the keys listed in UPGRADE.md. Buyer file untouched by hand; fill-forward only. |
| Plugin | `tools/ClubKitPackagerPlugin` changed; rebuild and reinstall the Studio plugin before packaging. |

## Core — replace via Update Engine

Engine folders are replaced wholesale. Deleted files go with them.

| Folder | Summary |
|--------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/`, `Icon/` | Shared domains: EventBoard (milestones, quota, claims, calendar), DailyQuest (strict streak), Accent, Music (web library policy, cover mesh, `MusicWebLibraryPolicy`), Settings. Config bootstrap and schema (new keys, `RETIRED_KEYS`). `InstanceState`, `ForeignGuiPolicy`, budget and telemetry helpers. Overhead effect presets. |
| `src/ServerScriptService/Hazastudio_ClubKit/` | `EventQuestBackend` (VPS quota, claims, check-in log), `EventBoardController` (claim flow, group gate, grants), music web library and import, `PlayerDocWriter`, `GlobalDocWriter`, `BackendClient`, `PlayerLookupBatcher`, `BudgetTelemetry`, `TamperGuard`, play-once requests, external-admin perks. `MusicCatalogSeeder` removed. |
| `src/StarterPlayerScripts/…`, `src/ReplicatedFirst/…` | `UIMotion` vocabulary, music v3 panel, event tab and popup and reminders, onboarding (flag off), cinematic loading (flag off), islands (notification, toast, queue, vote), foreign GUI guard, client footprint trims, accent picker, `PointerSpace`. Removed: `CoupleUI`, `InventoryDragController`, the v2 music panel helpers, and the duplicate `CameraShaker` modules (now shared at `EffectDonate/CameraShaker`). |

## Buyer-owned — review manually

| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template only. New keys and sections reach buyers by fill-forward (ADR 0001). Never replace a buyer's file. |

## GUI — RBXM or manual surface

Source sync does not carry these. Each one is a place-side object.

| GUI | Change | Needed for |
|-----|--------|-----------|
| `06-MusicPlayerGUI` | The v3 panel replaces v2. Carries the playlist cover stack (`BackdropNear`, `BackdropFar`, `CoverImage`). | **Required** for music 3.0. Rollback RBXM: `rollback/06-MusicPlayerGUI_v2.rbxm`. |
| `07-MenuGUI` → `EventTab` | Announcements and quests sections. | Event board. |
| `18-EventQuestPopup`, `19-EventReminders` | New quest popup and reminder surfaces. | Event board. |
| `07-MenuGUI` → each tab | `BacktoMainMenuButton` on Profile, Settings and Event. | Optional. Missing = no back button. |
| `02-ShopGUI` | `AccentToken` attributes on VVIP buy gradient, price gradients, benefit box and carousel dot. | Optional. Accent look only. |
| `09-DonationSystemGUI` | `AddEmojiButton` deleted in the template. | Optional cleanup. A buyer GUI that still has it keeps a dead button. |
| `04-AdminPanelv3` → `CustomTitleWrapper.Wrapper` | `LockedState` frame (shown over the image tab while `ImageCustomTitle` is off). | Optional. |
| `00-LoadingScreen` | Artwork for cinematic loading. | Only with `Config.Loading.STYLE = "cinematic"`. |
| `17-OnboardingGUI` | New design sketch for the onboarding modal. | Only with `Config.Onboarding.ENABLED = true`. Off. |
| Overhead nametag template | Trimmed V6 (Packager → Install V6). | Optional. |
| `CoupleUI` ModuleScript | Orphan, removed from the kit. | Cleanup. Delete it if a place still has it. |

## Tools, optional packs and docs

<details><summary>tools/ — Packager plugin, count-locals, dev-serve sync (5 files)</summary>

- `M` tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau
- `M` tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau
- `A` tools/ClubKitPackagerPlugin/plugin/OverheadV6Core.luau
- `A` tools/SyncFromDevServe.editmode.luau
- `M` tools/count-locals.ps1

</details>

<details><summary>extras/, places/ — optional packs and place notes (8 files)</summary>

- `M` extras/place-packs/CinematicLoading/README.md
- `M` extras/place-packs/CinematicLoading/bridge/CinematicLoading.client.luau
- `A` extras/place-packs/ExternalAdminBridge/kohls/ClubKitPerksAddon.luau
- `M` extras/place-packs/Hierapolis/HierapolisCustom.luau
- `A` places/atas-langit/README.md
- `A` places/atas-langit/archive/Logger-verbose.luau
- `A` places/parklab/Main-client-freetitle-topbar-and-phone-menu.luau
- `A` places/parklab/README.md

</details>

<details><summary>docs/, research/, root docs (VERSION, CHANGELOG, CONTEXT, UPGRADE_PROGRESS) (61 files)</summary>

- `M` .gitignore
- `A` .mimocode/backups/atas-langit-donation-20261016/Blossom.luau
- `A` .mimocode/backups/atas-langit-donation-20261016/GreenHammer.luau
- `A` .mimocode/plans/1790767488746-neon-eagle.md
- `A` .mimocode/plans/1790838319945-tidy-lagoon.md
- `A` .mimocode/plans/1790844099125-curious-engine.md
- `A` .mimocode/plans/1790957163749-jolly-nebula.md
- `A` .mimocode/plans/1791012194430-quick-rocket.md
- `A` .mimocode/skills/caveman/SKILL.md
- `M` CHANGELOG.md
- `M` CONTEXT.md
- `M` UPGRADE_PROGRESS.md
- `M` VERSION
- `M` docs/adr/0008-runtime-integrity-abuse-defense.md
- `A` docs/adr/0010-web-only-music-library.md
- `A` docs/adr/0011-one-ui-motion-vocabulary.md
- `A` docs/adr/0012-foreign-gui-report.md
- `A` docs/adr/0013-donation-effect-theming.md
- `A` docs/adr/0014-kit-drawn-track-covers.md
- `A` docs/adr/0015-dashboard-authored-event-board.md
- `A` docs/adr/0016-backend-client-and-write-discipline.md
- `A` docs/adr/0017-overhead-versioned-baselines-and-packing.md
- `A` docs/adr/0018-trimmed-overhead-template.md
- `A` docs/adr/0019-event-cards-countdowns-reminders.md
- `A` docs/buyers/colloseum-bunker.md
- `M` docs/buyers/hierapolis.md
- `M` docs/buyers/night-zone.md
- `M` docs/buyers/rust.md
- `M` docs/buyers/zenithaquatic.md
- `M` docs/delivery/OWNER_ONBOARDING.txt
- `A` docs/plans/acm-gaze-follow-cursor.md
- `A` docs/plans/datastore-migration-backhome-2026-10-05.md
- `A` docs/plans/datastore-migration-runbook-engine.md
- `A` docs/plans/director-mode-2026-10-07.md
- `A` docs/plans/dj-panel-2026-10-08.md
- `A` docs/plans/dj-panel-experiment/DJXExperiment.client.luau
- `A` docs/plans/event-cards-2026-10-07.md
- `A` docs/plans/fresh-install-new-place-2026-09-19.md
- `A` docs/plans/hardening-2026-09-24/HANDOFF.md
- `A` docs/plans/hardening-2026-09-24/audit-findings.md
- `A` docs/plans/hardening-2026-09-24/p0-deploy-steps.md
- `A` docs/plans/hardening-2026-09-24/p2-deploy-steps.md
- `A` docs/plans/hardening-2026-09-24/p3-kill-tests-results.md
- `A` docs/plans/hardening-2026-09-24/p4-crowd-harness-results.md
- `A` docs/plans/hardening-2026-09-24/p4b-overhead-template.md
- `A` docs/plans/hardening-2026-09-24/p4b-template-inventory.md
- `A` docs/plans/hardening-2026-09-24/perf-audit-200-players.md
- `A` docs/plans/music-player-v3.md
- `A` docs/plans/onboarding-experiment/OnboardingX.client.luau
- `A` docs/plans/production-hardening-2026-09-24.md
- `A` docs/plans/quest-milestones-2026-10-08.md
- `A` docs/plans/title-motion-2026-10-08.md
- `A` docs/plans/ui-experiments-dance-acm-2026-10-07.md
- `A` docs/releases/3.0.0/UPGRADE.md
- `A` docs/releases/3.0.0/rollback/06-MusicPlayerGUI_v2.rbxm
- `A` research/ai-dev-roblox-2026/brief.md
- `A` research/ai-dev-roblox-2026/findings/F1.md
- `A` research/ai-dev-roblox-2026/findings/F2.md
- `A` research/ai-dev-roblox-2026/findings/F3.md
- `A` research/ai-dev-roblox-2026/findings/F4.md
- `A` research/ai-dev-roblox-2026/findings/F5.md

</details>

## Full file list (core and buyer-owned)

<details><summary>src/ — engine and buyer template (257 files)</summary>

- `M` src/ReplicatedFirst/Hazastudio_ClubKit/LoadingBootstrap.client.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/Bubblegum.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/ElectricStroke.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/FireStroke.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/GalaxyStroke.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/GreenOutline.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/NeonStroke.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/RainbowOutline.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/ShineOutline.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/Presets/SunsetStroke.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/OverheadEffects/TitleColorPreset/SharedTickConnection.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/RoleCategoryBuilder.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/ContextModule/AnimatorUtils.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AccentDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AvatarLikePolicy.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CommandLibraryDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CoverMesh.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CoverTextPick.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/DailyQuestDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/DeliveryReportQueue.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/EventBoardDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/ExternalAdminPerksDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/FlushPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/ForeignGuiPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/GlobalDocPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/GreetingPacer.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/HttpBudgetPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/InvalidateBatch.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/LeaderboardCacheCodec.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/LeaderboardRevisionPolicy.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MovementPolicy.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicDurationPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicLibraryModel.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicPlayOncePolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicTransportPolicy.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicWebLibraryPolicy.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadTemplateResolver.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/PermissionDomain.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/PlayerLookupBatch.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RolesDomain.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/SettingsDomain.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/TitleEventDomain.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Leaderboards/WorkspaceLeaderboardRenderer.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/UI/CinematicLoadingView.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/UI/LoadingScreenUI.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/BoundedLru.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/BudgetGate.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/BudgetMeter.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CrossServerCache.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/DataStoreScheduler.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/DeltaCompressor.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/EventBoardRelay.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/GraphicsQuality.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/InstanceState.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/InterestManager.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/LoadingCinematicCamera.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/LoadingStoryCamera.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/NetworkCoalesce.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/NetworkManager.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/PlayerSessionStore.luau
- `M` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/SoundAssetSanitizer.luau
- `A` src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/TextMeasurementCache.luau
- `M` src/ReplicatedStorage/Icon/Features/Overflow.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/AdminController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/AvatarLikeController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/CommandLibraryController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/CoupleController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/DonationController.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/EventBoardController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/MusicController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/OverheadController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/SettingsController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/ShopController.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/ExternalAdminFacade.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Init/MovementGuard.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Init/MusicBootstrap.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Init/PersistenceFabricHooks.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Init/ServerModuleBag.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Init/TamperGuard.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Net/BackendClient.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Net/BudgetTelemetry.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Net/HttpRequest.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Net/PlayerLookupBatcher.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Persistence/GlobalDocWriter.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Persistence/PlayerDocWriter.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/AvatarLikeRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/DonationLeaderboardRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/GiftPendingRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/MusicRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/OverheadRepository.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/PerkQuotaRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/ProfileLoader.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/ProgressLeaderboardRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/SettingsRepository.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/VenueQuestProgressRepository.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/AvatarContextService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/AvatarLikeService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DemoDataProvider.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/EventBoardProvider.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/EventQuestBackend.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ExternalAdminPerkCommands.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/JoinCommunityMembersService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/JoinGreetingService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/LicenseService.luau
- `D` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicCatalogSeeder.luau
- `A` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicLibraryProvider.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicSession.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/OverheadService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ProfileSocialService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/ProximityInterestService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/RoleToolService.luau
- `M` src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SyncService.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/AdminController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/AdminTitleV3Controller.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/AutoDanceController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/AvatarContextController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/CinematicDockController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/CoupleController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/DonationLeaderboardController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/DonationNotificationController.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/EventBoardController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/GenericBroadcastController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/HotbarController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/JoinCommunityPromptController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/JoinGreetingController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/MobileFreecamController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/MusicPlayerController.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/OnboardingController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/OverheadController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/SettingsController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/StickerController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/SyncController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/SyncPanelTriggerController.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/TopMenuController.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/BlackHole/CameraShaker/CameraShakePresets.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/BlackHole/init.client.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/Blossom/CameraShaker/CameraShakeInstance.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/Blossom/CameraShaker/init.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/Blossom/init.client.luau
- `R` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/CameraShaker/CameraShakeInstance.luau
- `R` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/CameraShaker/CameraShakePresets.luau
- `R` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/CameraShaker/init.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/EffectTheme/ThemeData.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/GreenHammer/CameraShaker/CameraShakeInstance.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/GreenHammer/CameraShaker/CameraShakePresets.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/GreenHammer/CameraShaker/init.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/GreenHammer/init.client.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/LocalNuke/CameraShaker/CameraShakeInstance.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/LocalNuke/CameraShaker/CameraShakePresets.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/LocalNuke/CameraShaker/init.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/LocalNuke/init.client.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Effects/EffectDonate/SoundSanitizeBootstrap.client.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Init/ClientModuleBag.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/AccentService.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/AccentSurfaceTint.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/ChatTagStore.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/ForeignGuiGuardService.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/GeneralNotificationCenterService.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/HotbarInventoryService.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/InventoryChromeAnimator.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/MobilePanelManager.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/MobileScaleService.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Services/StarterGuiTrimService.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/State/MusicPlayerStore.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/AdminHubUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/AdminPanelUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/AdminPanelV3UI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/AvatarContextLook.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/AvatarContextUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/BackpackUIBinder.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/BoardAmbience.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/CarryUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/CommandLibraryUI.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/CoupleUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/CustomTitleUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/DancePanelGuiRefs.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/DancePanelUIBinder.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/DancePanelV3Look.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/DonationSystemGuiRefs.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/DonationSystemUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/EmoteListPanel.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/EventCardKit.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/EventQuestPopupUI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/EventReminderUI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/EventTabUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/FreeTitleEventUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/GiftUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/HotbarUIBinder.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/InventoryDragController.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/KitLook.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/LeaderboardRowTrim.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MenuGuiRefs.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MenuSettingsCore.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MenuShellUI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/CoverArt.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/CoverTile.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/DjView.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/GuiRefs.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/LibraryView.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/ListPool.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/NowPlayingView.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/PanelShell.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/QueueIsland.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/Visuals.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/VoteIslandView.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Music/VoteModalView.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MusicPlayerCoverHelpers.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MusicPlayerGuiRefs.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MusicPlayerUIBinder.luau
- `D` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MusicPlayerUIBinderPart2.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/MusicTopbarIcon.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/NotificationCenterBuilder.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/NotificationIsland.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Onboarding/OnboardingControls.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Onboarding/OnboardingKit.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Onboarding/OnboardingStage.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Onboarding/OnboardingSteps.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/Onboarding/OnboardingUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/OverheadUI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/OverlayScrollbar.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/PaidBroadcastUI.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/ProfileFieldModalLook.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/ProfileTabBinder.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/ScrollAffordance.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/SegmentedSliderBar.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/SettingsTabBinder.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/ShopUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/StreakUI.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/SyncStatusPanel.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/ToastIsland.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/UI/TopMenuGuiRefs.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/AnimationHelper.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/AvatarGiant.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/AvatarPrewarmPool.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/AvatarViewport3D.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/GroupedRowCornerUtil.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/GuiFade.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/ImageSwap.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/MotionPresets.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/NukeEffectController.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/OverheadCullBudget.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/PointerSpace.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/PressFeedback.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/SmoothScrollHelper.luau
- `A` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/UIMotion.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/UISoundHelper.luau
- `M` src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Main.client.luau

</details>

<details><summary>src/ — buyer-owned template (1 files)</summary>

- `M` src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau

</details>

