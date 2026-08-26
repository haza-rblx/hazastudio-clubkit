# Changed Files — v2.9.1 → v2.9.2

## Summary
- 10 files changed (9 modified, 1 new) — includes commit `5ec8233` (donation reliability v4), authored outside the release pass but shipping in this version
- Breaking: no. No `ClubKitConfig` schema change; no DataStore key change.
- **Behavioural note:** a new **Auto** pill appears on the left topbar for every player. Set `Config.AutoDance.ENABLED = false` to suppress it.

## Core — donation reliability v4 (commit `5ec8233`)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | `DonationNotifPayload.kind` — unique NetworkManager coalesce key |
| `src/ServerScriptService/.../Server/Services/DonationService.luau` | Forwards `skipped` to the delivery ledger; DLQ reports carry reason (`left`/`timeout`) + attempts; sets `kind = "donation:<id>"` |
| `src/StarterPlayerScripts/.../Client/Controllers/DonationNotificationController.luau` | Muted announce acks `{skipped="muted"}`; missing GUI installs a minimal listener replying `{skipped="no_gui"}` + chat fallback; ack/display remotes via `WaitForChild` |

## Core — Auto Dance + init sweep (replace via source sync / Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.9.2` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | New `Config.AutoDance` (ENABLED, MIN/MAX_INTERVAL, UNSYNC_ON_ENABLE, STOP_ON_DISABLE, TOPBAR_ORDER/LABEL/LABEL_ACTIVE/ICON) |
| `src/StarterPlayerScripts/.../Client/Controllers/AutoDanceController.luau` | **New** — shuffle loop; drives `SyncController:onEmoteSelected`; generation guard against stale `task.delay`; yields to dance sync via `SyncStore.isSyncing` subscription + in-loop guard, using `skipStop` so it never fights the sync system |
| `src/StarterPlayerScripts/.../Client/Init/ClientModuleBag.luau` | `createAutoDanceController` require |
| `src/StarterPlayerScripts/.../Main.client.luau` | Wires the Auto Dance pill on the **left** strip inside the SyncDance bootstrap. Kept inside the closure — no new top-level local (register budget unchanged at 136) |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change this release |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.9.2` |
| `tools/ClubKitPackagerPlugin/plugin/SourceSyncCore.luau` | New `engineRoots()` helper (scope derived from `Manifest.SERVICE_ROOTS`) + post-apply sweep removing stale Rojo `init` twins, so existing buyer places self-heal on Update Engine |
| `tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` | Same sweep in `unpack`, also scoped from `Manifest.SERVICE_ROOTS`, so a fresh install self-heals even from an older `.rbxm` |

## Template place (not a repo file — action already taken)
| Item | Change |
|------|--------|
| `THE BASIC TEST 1.3` (placeId 75916114543452) | **15 stale `init` twins removed** across all `Manifest.SERVICE_ROOTS` subtrees, including the vendored `ReplicatedStorage.Icon`. **Zero left anywhere in the place.** This is the export source, so every package cut from here onward is clean. Topbar verified intact afterwards (11 icons, zero Icon-related errors). |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.9.2]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.9.2` |
| `docs/releases/2.9.2/` | This folder |
