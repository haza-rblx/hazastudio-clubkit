# Changed Files — v2.4.78 → v2.4.79

## Summary
- 8 core/client files + version/docs
- Breaking: no

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/UI/EmoteListPanel.luau` | Same-emote clicks use short wutwut fire interval when `WUTWUT_ENABLED` |
| `src/StarterPlayerScripts/.../Client/State/SyncStore.luau` | `_clear` meta-key to assign `nil` (Luau cannot clear via `= nil`) |
| `src/StarterPlayerScripts/.../Client/Controllers/SyncController.luau` | Use `_clear` for pending/leader; pending only counts in `isSameSelected` while preparing |
| `src/StarterPlayerScripts/.../Client/Services/DanceWarmupService.luau` | Don't clobber in-flight `isDancePreparing` |
| `src/ServerScriptService/.../Server/Controllers/SyncController.luau` | Comment: chain window ~0.45s |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `WUTWUT_CHAIN_WINDOW` 0.32 → 0.45 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.4.79 |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No new keys required. Keep `Features.WutwutDance` as desired. Optional: tune `Sync.SwitchFade*` / `SwitchInputCooldown` for snappier switches. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.4.79 |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.4.79]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | 2.4.79 |
| `docs/releases/2.4.79/` | This folder |
