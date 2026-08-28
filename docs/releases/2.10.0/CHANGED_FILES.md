# Club Kit 2.10.0 — Changed Files

Paths are relative to `src/`. **Replace** files are engine-owned and are overwritten wholesale by **Update Engine** — do not hand-edit them in a buyer place. **Buyer-owned** files are never overwritten (fill-forward merge, ADR 0001). **Optional** items are place-level cleanups you may choose to do.

---

## Replace (engine-owned — auto-updated)

### Rendering fixes (ADR 0005)
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/UI/GroupMotionPolicy.luau` | **New.** Pure decision table: scale vs size-stable motion for a CanvasGroup target. |
| `StarterPlayerScripts/.../Client/Utils/GroupMotion.luau` | **New.** Instance adapter over the policy. |
| `StarterPlayerScripts/.../Client/Services/CanvasGroupBudgetService.luau` | **New.** Distance-culls Workspace SurfaceGuis containing CanvasGroups to free texture budget. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | New `Config.UIMotion`, `Config.CanvasGroupBudget` (cull 250), `Config.AntiTamper` (see below). |
| `StarterPlayerScripts/.../Client/Utils/AnimationHelper.luau` | Size-stable present/dismiss variants for panels/toasts. |
| `StarterPlayerScripts/.../Main.client.luau` | Starts `CanvasGroupBudgetService`; shows `BootHaltedNotice` on the replicated `BootHalted` attribute. |
| `StarterPlayerScripts/.../Client/Controllers/GenericBroadcastController.luau` | Enter/exit scale via `GroupMotion`. |
| `StarterPlayerScripts/.../Client/Controllers/JoinGreetingController.luau` | Same. |
| `StarterPlayerScripts/.../Client/Controllers/DonationNotificationController.luau` | Panel + live-chat scale via `GroupMotion`. |
| `StarterPlayerScripts/.../Client/Controllers/StickerController.luau` | Modal scale via `GroupMotion`. |
| `StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | Nametag pop scale via `GroupMotion`. |

### License hardening (ADR 0006)
| File | Change |
|---|---|
| `ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | **HttpService boot gate** (halts boot if HTTP off) + wires IntegrityTripwire + TamperGuard. |
| `StarterPlayerScripts/.../Client/UI/BootHaltedNotice.luau` | **New.** Full-screen "enable HttpService" overlay when boot halts. |
| `ServerScriptService/.../Server/Services/LicenseService.luau` | Fail-open → **fail-closed** rework + 24h grace + leak beacon + tamper report. |
| `ServerScriptService/.../Server/Services/CommandExecutionService.luau` | Wires the `admin_commands` license gate at the command choke point. |
| `ServerScriptService/.../Server/Init/IntegrityTripwire.luau` | **New.** Independent `enforcement_disabled` beacon. |
| `ServerScriptService/.../Server/Init/TamperGuard.luau` | **New.** On exploit report → kick + beacon. |
| `StarterPlayerScripts/.../Client/Services/SaveInstanceGuardService.luau` | **New.** Behavioural `saveinstance` detector. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Notice.luau` | **New.** Proprietary + AI-reader notice. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/ConsoleBanner.luau` | Ownership + `Universe <GameId>` watermark lines. |
| `ServerScriptService/.../Server/Init/ServerModuleBag.luau` | Registers IntegrityTripwire + TamperGuard. |
| `ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | Version → 2.10.0, build 20260828, proprietary header notice. |

### Admin Hub — manual Robux persistence fix
| File | Change |
|---|---|
| `StarterPlayerScripts/.../Client/Controllers/AdminHubController.luau` | "Score edit" gains a Cash/Robux toggle; Robux routes to the persistent `setrobux` command. |

### Version anchors (not in the engine tree, bumped for release bookkeeping)
- `VERSION` → `2.10.0`
- `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` → `KIT_VERSION` / `PLUGIN_VERSION` = `2.10.0`

---

## Buyer-owned (NOT overwritten — review only)

| File | Action |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **No change required.** All new settings live in engine `Config.luau` with safe defaults. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | **Unchanged.** Per-buyer secret rotation (if your place is ever leaked) is a separate delivery step, not part of this update. |

## Required buyer action (a Game Setting, not a file)

- **⚠ Enable HttpService** — Game Settings → Security → **Allow HTTP Requests** → Save. The kit will not boot without it. See [`UPGRADE.md`](UPGRADE.md).

## Optional

- `Config.AntiTamper.BRICK_ON_DETECT` — leave **false** (default). Enable only after you've watched the exploiter detector behave in your place.
- CanvasGroup opt-outs: `Config.UIMotion.CANVAS_GROUP_SIZE_STABLE`, `Config.CanvasGroupBudget.ENABLED`, `SURFACE_CULL_DISTANCE`, and the `ClubKitKeepSurfaceGui` attribute.
- Place-level texture cleanups for heavy venues (e.g. RUST): remove duplicate poster sets, lower poster `PixelsPerStud`, delete duplicate admin/dance GUIs, hoist `ViewportFrame`s out of CanvasGroups. See `CHANGELOG.md` `[2.10.0]` for the specific list.
