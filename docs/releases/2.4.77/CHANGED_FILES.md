# Changed Files — v2.4.76 → v2.4.77

## Summary
- 12 files changed
- Breaking: no (new feature is opt-in, default off)

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `WUTWUT_ENABLED = false` flag + comments on `WUTWUT_*` keys (STOP_ARM reserved) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Map buyer `Sync.WutwutEnabled` (boolean) → `Config.Sync.WUTWUT_ENABLED` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | `Sync.WutwutEnabled = false` default (plugin fill-forward, never auto-enables) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.4.77, `BuildId` 20260809 |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/SyncController.luau` | Restart intent uses `WUTWUT_RESTART` rate bucket (20/2s) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SyncService.luau` | Honor `intent`; per-intent throttle; restart branch in `replicateAnimation` (Stop0/rewind/Play fade 0, BFS to followers) |
| `src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/SyncController.luau` | Chain-window detection (acked `currentAnim` only), `"restart"` intent, `restarted` ack no-op |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Plugin fill-forward adds `Sync.WutwutEnabled = false` automatically. Set `true` only if you want rapid same-emote re-click to restart dances. Existing values untouched. |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.4.77 |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.4.77]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | 2.4.77 |
