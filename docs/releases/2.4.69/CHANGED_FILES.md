# Changed Files — v2.4.68 → v2.4.69

## Summary
- DonationWorldEffects feature flag, /drone + /crowd, Sociabuzz provider, ConfigPatch harden, plugin PanelMotion
- Breaking: **no**
- Git tag: `v2.4.69`

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.69`, BuildId `20260804` |
| `src/.../Shared/Constants/Config.luau` | `DonationWorldEffectsEnabled`, Drone/Crowd flags + tunables |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | `Features.DonationWorldEffects` default |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Map Features → FeatureFlags |
| `src/.../Shared/Domain/DonationProviderDomain.luau` | `PRESETS.sociabuzz` |
| `src/.../Shared/Domain/CommandLibraryDomain.luau` | drone + crowd entries |
| `src/.../Shared/Utils/DonationExperiencePrefs.luau` | Gate world effect on flag |
| `src/.../Server/Services/DonationService.luau` | Skip `payload.worldEffect` when flag off |
| `src/.../Server/Services/DroneService.luau` | **NEW** session + frame broadcast |
| `src/.../Server/Controllers/DroneController.luau` | **NEW** `/drone` |
| `src/.../Server/Controllers/CrowdController.luau` | **NEW** `/crowd` |
| `src/.../Server/Init/EarlyRemotes.luau` | Drone + Crowd remotes |
| `src/.../Server/Init/ServerModuleBag.luau` / `Main.server.luau` | Wire drone/crowd |
| `src/.../Client/.../DroneController.luau` | **NEW** pilot / spectator |
| `src/.../Client/.../CrowdController.luau` | **NEW** Chat bubbles |
| `src/.../Client/.../FreecamController.luau` / `MobileFreecamController.luau` | `DroneLock` |
| `src/.../Client/.../DonationVfxClientGate.luau` | Honor feature flag |
| `src/.../Client/.../MenuSettingsCore.luau` | Hide World Effects row when flag off |
| `src/.../Client/.../ClientModuleBag.luau` / `Main.client.luau` | Wire drone/crowd |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template repo punya `DonationWorldEffects`; place buyer: Update Engine fill-forward atau set manual. Jangan timpa Secrets/custom values |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` (+ plugin-build) | `KIT_VERSION` `2.4.69` |
| `tools/.../plugin/PanelMotion.luau` (+ plugin-build) | **NEW** motion helpers |
| `tools/.../plugin/UpdaterPanel.luau` (+ plugin-build) | Motion + CONFIG MERGE FAILED UI |
| `tools/.../plugin/ConfigPatchCore.luau` / `SourceSyncCore.luau` | Harden Features fill-forward |
| `tools/.../default.project.json` | Register PanelMotion |
| `tools/donation-api/**` | Sociabuzz webhook + admin/docs |
| `CLUB_KIT_SETUP.md` | Sociabuzz + DonationWorldEffects + merge additive note |
| `docs/releases/2.4.69/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.69` |
