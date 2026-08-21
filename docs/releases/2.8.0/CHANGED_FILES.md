# Changed Files — v2.7.1 → v2.8.0

## Summary
- 7 Luau/source files changed (+ release docs + version triad)
- Breaking: no (new config flag defaults to legacy v1)

## Core — replace via Update Engine (source sync)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.7.1 → 2.8.0, `BuildId` 20260820 → 20260821 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +`Config.FeatureFlags.AvatarContextMenuV2Enabled = false`; +`Config.AvatarContext.BACKDROP_BLUR_NAME = "AvatarContextBlur"`; `Config.PanelBlur.ENABLED` false → true (global backdrop blur) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`defaults.Features.AvatarContextMenuV2 = false` + FEATURE_MANIFEST "Avatar context menu v2 (redesign)" (Interface) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Fill-forward map `AvatarContextMenuV2` → `AvatarContextMenuV2Enabled` |
| `src/StarterPlayerScripts/.../Client/UI/AvatarContextUI.luau` | v1/v2 GUI switch by flag (+ fallback + disable other variant); restored `AvatarViewport3D`/`AvatarPrewarmShared` requires + `ensureViewportFrame`; `showAvatar` → `showAvatarThumbnail` (v2) / `showAvatar3D` (v1); backdrop zoom/blur via `AnimationHelper` (v2 only); `resetVisualState` resets backdrop state; `userId == 0` guard (was `<= 0`) |
| `src/StarterPlayerScripts/.../Client/Utils/AvatarViewport3D.luau` | Double-avatar fix: `load()`/`cleanup()` destroy every `WorldModel` child via shared `_destroyAllWorldModels()` helper |

## Buyer-owned — review manually, do NOT replace
| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` (template) | +`Features.AvatarContextMenuV2 = false` (additive; fill-forwarded to live buyer configs) |

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` / `PLUGIN_VERSION` 2.7.1 → 2.8.0 |
| `VERSION` | 2.8.0 |
| `CHANGELOG.md` | v2.8.0 entry |
| `UPGRADE_PROGRESS.md` | unreleased rows documented |
| `docs/releases/2.8.0/` | this folder |

## Note — new GUI asset (not in source sync)
The v2 design ships as a **separate StarterGui ScreenGui** (`AvatarContextMenuV2`). GUIs are place assets, not covered by engine source sync (`ENGINE_SOURCE_PREFIXES` covers Luau only). Fresh installs get both `AvatarContextMenu` (v1) + `AvatarContextMenuV2` (v2) from the `HazastudioClubKit_Package` model; the toggle selects which renders. Existing places updating via Update Engine keep their current `AvatarContextMenu` and need the v2 GUI added manually (or from the rebuilt package) to use `Features.AvatarContextMenuV2 = true`.
