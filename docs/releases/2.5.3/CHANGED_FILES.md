# Changed Files — v2.5.2 → v2.5.3

## Summary
- Music zone-system cleanup (global-only)
- Breaking: yes (engine zone mode only; buyer `ClubKitConfig` unaffected)

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.5.3` |
| `src/.../Shared/Constants/Config.luau` | Removed `Music.MODE` + `ZONE_*` + `MSG_NOT_IN_ZONE` + `REMOTE_ZONE_CHANGED` |
| `src/.../Server/Services/MusicService.luau` | Single lazy global session; removed zone machinery + `MusicZoneDebug` |
| `src/.../Server/Services/MusicSession.luau` | Removed `zoneId` dep + log fields |
| `src/.../Server/Services/ZoneTrackerService.luau` | **Deleted** |
| `src/.../Server/Init/MusicBootstrap.luau` | Removed ZoneTracker wiring |
| `src/.../Server/Main.server.luau` | Removed dead `MusicZoneChanged` remote |
| `src/.../Server/Controllers/MusicController.luau` | Removed `not_in_zone` notification branch |
| `src/.../Client/Controllers/MusicPlayerController.luau` | Removed zone handlers; library load path cleanup |
| `src/.../Client/State/MusicPlayerStore.luau` | Removed `activeZoneId` / `activeZoneDisplayName` |
| `src/.../Client/UI/MusicPlayerUIBinder.luau` | Library first-open rebind / placeholder cleanup |
| `src/.../Client/UI/MusicPlayerUIBinderPart2.luau` | TrackLength / cover placeholder cleanup |
| `src/.../Client/UI/MusicTopbarIcon.luau` | Comment cleanup |
| `src/.../Main.client.luau` | Comment cleanup |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.5.3` |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.5.3]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.5.3` |
| `docs/releases/2.5.3/` | This folder |
| `docs/index.html` / `docs/updates.html` / locales | Hub version → 2.5.3 |
| `docs/delivery/TEMPLATE_PLACE.md` / `PLUGIN.md` | Delivery bundle paths for v2.5.3 |
