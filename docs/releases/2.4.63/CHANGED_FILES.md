# Changed Files — v2.4.62 → v2.4.63

## Summary
- ~16 core engine files + schema/bootstrap + version/docs
- Breaking: no (behavior: `/re` in-place; soft dance crossfade)
- Buyer config: additive `ClubKitConfig.Sync` (fill-forward)

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ServerScriptService/.../Services/SessionCommandService.luau` | `/re` in-place ApplyDescription |
| `src/ServerScriptService/.../Services/SyncService.luau` | Crossfade + phase snap + `/re` dance restore |
| `src/ServerScriptService/.../Controllers/OverheadController.luau` | `Avatar:Refreshed` for in-place `/re` |
| `src/ServerScriptService/.../Controllers/AdminController.luau` | Giftcard outcome; title filter; auth msgs |
| `src/ServerScriptService/.../Init/ServerRestartHooks.luau` | **new** — delayed restart early flush |
| `src/ServerScriptService/.../Main.server.luau` | Wire restart hook; notif poll 5s |
| `src/ReplicatedStorage/.../ContextModule/AnimatorUtils.luau` | `prepareDanceCrossfade` |
| `src/ReplicatedStorage/.../Constants/Config.luau` | Fade defaults; `MSG_REFRESH_FAILED`; restart; notif poll |
| `src/ReplicatedStorage/.../Config/ClubKitConfigSchema.luau` | `Sync` schema defaults |
| `src/ReplicatedStorage/.../Config/ConfigBootstrap.luau` | Map `ClubKitConfig.Sync` → `Config.Sync` |
| `src/StarterPlayerScripts/.../Client/Controllers/SyncController.luau` | Clear local loading dances on sync_success |
| `src/StarterPlayerScripts/.../Client/Init/ClientModuleBag.luau` | Drop RefreshCameraPreserve |
| `src/StarterPlayerScripts/.../Main.client.luau` | Drop RefreshCameraPreserve.init |
| `src/StarterPlayerScripts/.../Client/Utils/RefreshCameraPreserve.luau` | **deleted** |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.63 |

## Buyer-owned — review manual, jangan replace utuh
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep values; **Update Engine** fill-forwards missing `Sync.*` keys. Template di repo punya section `Sync` + komentar. |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.63 |
| `CHANGELOG.md` | [2.4.63] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.63/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION 2.4.63 |
