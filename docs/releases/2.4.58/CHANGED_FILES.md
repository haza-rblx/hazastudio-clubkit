# Changed Files — v2.4.57 → v2.4.58

## Summary
- 5 core engine files + version/docs
- Breaking: no

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SessionCommandService.luau` | `/re` in-place ApplyDescription; stream restore; no double Avatar:Refreshed on LoadCharacter |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/OverheadController.luau` | `waitForStableHead` before attach; avatar refresh waits for settle |
| `src/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/OverheadController.luau` | Rebind Head watcher when Head replaced |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/UI/LoadingScreenUI.luau` | Don't clobber project overhead Enabled on loading dismiss |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `HEAD_STABLE_DEBOUNCE`, `HEAD_STABLE_TIMEOUT` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.58 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep — no required merge |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.58 |
| `CHANGELOG.md` | [2.4.58] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.58/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION |
