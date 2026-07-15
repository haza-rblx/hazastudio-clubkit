# Changed Files — v2.4.38 → v2.4.39

## Summary

- Network / FPS stabilization (DJ, overhead, donation VFX, NetworkManager coalesce)
- Freecam exit mouse unlock + attribute toggle race fix
- Cinematic deny toast; Music DJ switch ghost-click fix
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `NetworkPerf` + `Network.ENABLE_FRAME_COALESCE` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/NetworkPerfCounters.luau` | New: 1s counters (gated) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/DeltaCompressor.luau` | Deep-equal nested when `DEEP_DELTA_NESTED` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/NetworkManager.luau` | Per-frame coalesce keep-last |
| `src/ServerScriptService/.../Server/Services/MusicSession.luau` | DJ effects-only sync + throttle |
| `src/ServerScriptService/.../Server/Controllers/OverheadController.luau` | Join proximity-only; counters |
| `src/ServerScriptService/.../Server/Services/DonationEffectService.luau` | World VFX concurrent cap |
| `src/ServerScriptService/.../Server/Controllers/DonationController.luau` | `WORKSPACE_LB_PAINT_PAUSE` gate |
| `src/ServerScriptService/.../Server/Controllers/CinematicDockController.luau` | Authorize no-op for admins |
| `src/StarterPlayerScripts/.../Client/Controllers/MusicPlayerController.luau` | `djEffects` kind; skip renderQueue |
| `src/StarterPlayerScripts/.../Client/Controllers/OverheadController.luau` | Apply coalesce; skip-apply flag |
| `src/StarterPlayerScripts/.../Client/Controllers/FreecamController.luau` | Attribute sync fix; unlock mouse on Pop |
| `src/StarterPlayerScripts/.../Client/Controllers/MobileFreecamController.luau` | Unlock mouse on popState |
| `src/StarterPlayerScripts/.../Client/Controllers/CinematicDockController.luau` | Deny open → authorize |
| `src/StarterPlayerScripts/.../Client/Controllers/TopMenuController.luau` | Cinematic btn always visible |
| `src/StarterPlayerScripts/.../Client/UI/MusicPlayerUIBinder.luau` | DJ switch Activated-only |
| `src/StarterPlayerScripts/.../Client/UI/MusicPlayerUIBinderPart2.luau` | Sync DJ switch Active |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.39 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Tidak wajib diubah |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.39 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.39 |
| `docs/releases/2.4.39/*` | Upgrade guide |
