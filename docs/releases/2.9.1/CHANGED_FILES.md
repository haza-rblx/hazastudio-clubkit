# Changed Files — v2.9.0 → v2.9.1

## Summary
- 10 files changed (8 modified, 2 new)
- Breaking: no schema/API breaks. **Visual behavior change:** the panel-open camera zoom effect (Shop/Gift/Admin/Music/Couple/Donation/Avatar profile/Top Menu/Paid Broadcast/Join Community) is now **off by default** (`Config.PanelZoom.ENABLED = false`) — it was previously always-on with no way to disable. If a buyer wants to keep the zoom, set `Config.PanelZoom.ENABLED = true` in `Shared/Constants/Config.luau` after updating (engine file — not buyer-editable via `ClubKitConfig`, same as the existing `Config.PanelBlur` knob).

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.9.1`, `BuildId` → `20260826` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | New `Config.PanelZoom = { ENABLED = false }` |
| `src/StarterPlayerScripts/.../Client/Utils/AnimationHelper.luau` | `_tweenCameraZoom` now no-ops unless `Config.PanelZoom.ENABLED == true` |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No schema change this release |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Optional add-on — SyncBhms (extras/place-packs/SyncBhms)
| Path | Change |
|------|--------|
| `bridge/SyncBhmsLeadDanceBridge.client.luau` | **New** — restores the topbar "Lead Dance" icon under `Features.LegacySyncBhms = true`. Reuses Club Kit's `SyncLeadTopbarController` module, routes through `SyncBhmsAcmBridge` instead of `SyncController`. Optional install (`StarterPlayerScripts.SyncBhmsLeadDanceBridge`). |
| `bridge/SyncBhmsLeadDanceFollowerSync.server.luau` | **New** — mirrors BHMS's own follower graph (`Character.Syncing`) onto `Character.IsLeader`/`FollowerCount`, so the bridge's Lead Dance dropdown reflects real active followers instead of just role membership. Pairs with the bridge above (`ServerScriptService.SyncBhmsLeadDanceFollowerSync`). |
| `README.md` | Documents the two new files + install steps |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.9.1` |
| `tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` | `blankTemplateConfigSource` fixed — no longer produces a double-annotated (`{} :: T :: T`) `AdminUserIds` field, which was a Luau syntax error on any fresh install from the pack |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.9.1]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.9.1` |
| `deliver/README.md` | Housekeeping catch-up for the already-shipped v2.9.0 delivery bundle (was left uncommitted from that release) — not part of 2.9.1's own delta |
| `docs/releases/2.9.1/` | This folder |
