# Changed Files — v2.4.70 → v2.4.71

## Summary
- Admin Hub (gated), daily boards ×3, UI motion stack, CinematicDock hide, plugin Aurora Dusk, docs hub + i18n
- Breaking: **no** (AdminHub / LegacySyncBhms default off)
- Git tag: `v2.4.71`

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.71`, BuildId `20260807` |
| `src/.../Shared/Constants/Config.luau` | `AdminHubEnabled`, `LegacySyncBhmsEnabled`, `UIMotion`, daily board flags |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | `Features.AdminHub`, `Features.LegacySyncBhms` |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Map Features → FeatureFlags |
| `src/.../Shared/Leaderboards/WorkspaceLeaderboardRenderer.luau` | Cash `RP ` format |
| `src/.../Server/.../DonationController.luau` | `dailyCombined` merge + fingerprint |
| `src/.../Server/.../DemoDataProvider.luau` | Demo combined + daily robux |
| `src/.../Server/.../EarlyRemotes.luau` / `Main.server.luau` | LegacySyncBhms / sync dance gate |
| `src/.../Client/.../AdminHubController.luau` / `AdminHubUI.luau` | **NEW** hub |
| `src/.../Client/.../AdminController.luau` | `bindTopbar=false` when hub owns icon |
| `src/.../Client/.../DonationLeaderboardController.luau` | 3 daily specs |
| `src/.../Client/.../DonationNotificationController.luau` | LiveChat Footer idle + pop |
| `src/.../Client/.../TopMenuController.luau` | Spring open; hide CinematicDock non-admin |
| `src/.../Client/.../MotionPresets.luau` / `PressFeedback.luau` / `UISpring.luau` | **NEW** motion helpers |
| `src/.../Client/.../AnimationHelper.luau` + UI panels | Wire MotionPresets / PressFeedback |
| `src/.../Client/.../ClientModuleBag.luau` / `Main.client.luau` | Boot AdminHub; SyncBhms bridge hook |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template: `AdminHub` / `LegacySyncBhms`. Place: fill-forward OK — jangan timpa custom values |
| `Secrets` | Pertahankan |
| `StarterGui/04-AdminHub` | Opsional — perlu jika `Features.AdminHub = true` (build via `tools/BuildAdminHub.editmode.luau`) |
| `Workspace` daily boards | Opsional — parts `DailyDonations` / `DailyDonationsRobux` / `DailyDonationsCash` |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` (+ plugin-build) | `KIT_VERSION` / `PLUGIN_VERSION` `2.4.71` |
| `tools/.../plugin/ClubKitPanel.luau` / `ClubKitUI.luau` / `DovetailTheme.luau` | Aurora Dusk panel |
| `tools/.../plugin/ConfigEditCore.luau` / `PluginSyncCore.luau` | Config write-back + plugin soft-update |
| `tools/.../plugin/HazastudioClubKit.plugin.luau` / `dev-serve.ps1` | Hot-reload |
| `tools/BuildAdminHub.editmode.luau` / `tools/prototypes/admin-hub-v1.html` | Hub shell + prototype |
| `extras/place-packs/SyncBhms/**` | Optional place-pack (not default engine sync) |
| `docs/index.html` / `setup.html` / `updates.html` / `i18n.js` / `locales/**` | Docs hub + i18n |
| `docs/releases/2.4.71/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.71` |
