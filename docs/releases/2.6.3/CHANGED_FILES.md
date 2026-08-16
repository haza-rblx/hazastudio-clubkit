# Changed Files — v2.6.2 → v2.6.3

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 6 |
| Breaking | no |

Engine-only tweaks. Ship via **Update Engine (source sync)**. No RBXM, no buyer config changes.

## Core — replace via Update Engine

| Path | Type | Summary |
|------|------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | mod | `KitVersion` → 2.6.3 |
| `src/ReplicatedStorage/.../Shared/Constants/Config.luau` | mod | `Admin.HUB_GUI_SCALE_MOBILE` 0.44→0.5; `MobileScale.ADMIN_HUB_GUI` 0.44→0.5 |
| `src/StarterPlayerScripts/.../Client/Controllers/AdminHubController.luau` | mod | Announce sheet opens empty (removed "Welcome to the club!" prefill) |

## Tools / docs only

| Path | Summary |
|------|---------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.6.3 |
| `VERSION` | 2.6.3 |
| `CHANGELOG.md` | `[Unreleased]` → `[2.6.3]` |
| `UPGRADE_PROGRESS.md` | unreleased table reset |
| `docs/releases/2.6.3/` | this release folder |

## Note — place-specific changes NOT in this release

Changes made directly to the buyer place "Atlantis 18+" (not template): GameKey fix `altantis2`→`atlantis`, Adonis bridge install (`Provider="Adonis"` + RankMap), removal of leftover Kohl's Admin, deploy of `PlaceToolsFix` + `DuelWeld`. These live in that place only and are not part of the kit template.
