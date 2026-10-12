# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `3.0.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_ — never bump `VERSION` before "okay this is update X.Y"
**Active branch:** `main`

---

## Status summary

**3.0.0 released 2026-10-09.** The full 3.0 progress log (tables, decisions, verification notes) as it stood at release is in [`docs/releases/3.0.0/PROGRESS_ARCHIVE.md`](docs/releases/3.0.0/PROGRESS_ARCHIVE.md). Buyer guide: [`docs/releases/3.0.0/UPGRADE.md`](docs/releases/3.0.0/UPGRADE.md). File list: [`docs/releases/3.0.0/CHANGED_FILES.md`](docs/releases/3.0.0/CHANGED_FILES.md).

## Unreleased — file table (phone stale hide/show UI: ACM hotbar + panel focus, 2026-10-12)

Not committed. Repo files + the same changes ported into PARKLAB by MCP (place keeps its own ICA sticker handling, so that file was patched surgically, never replaced).

| File | Change | Buyer-owned? |
|---|---|---|
| `Client/Controllers/AvatarContextController.luau` | New deps `notifyAcmOpen` / `notifyAcmClose`; `openPanel` hides the hotbar for the entrance, `closePanel` (the one funnel for every close path) releases it | no |
| `Client/UI/AvatarContextUI.luau` | `ui:open(delaySeconds)` takes the entrance delay as an argument; `setBeforeOpenCallback` removed (and from the disabled stub) | no |
| `Client/Services/InventoryChromeAnimator.luau` | `setupAcmWatcher` rebinds on `ChildAdded`/`ChildRemoved` and re-looks-up `MainWrapper` each grace tick, so the CanvasGroup→Frame swap cannot strand a hide; `notifyHide` stamps `_acmHiddenAt` | no |
| `Client/Services/MobilePanelManager.luau` | `open()` closes the previously focused panel (restore + its close callback) before snapshotting the new one | no |
| `Client/Controllers/CoupleController.luau` | `requestClose` helper; the X button and the breakup/notification dismiss paths deselect the icon | no |
| `Client/UI/MenuShellUI.luau` | `hide()` fires its bound close callback after the slide-out, so a click-outside deselects the settings icon | no |
| `Client/Controllers/AdminController.luau` | Role-revocation while the classic panel owns the icon deselects it after `ui:hide()` | no |
| `Main.client.luau` | ACM wiring: the two notify deps are passed into the controller factory; `setBeforeOpenCallback` block removed | no |
| `CHANGELOG.md` | `[Unreleased]` "Fixed" entry for the three phone bugs | no |

Verified: 7-file luau-lsp pass shows no new diagnostics vs HEAD (only the pre-existing `_hideCounts` key-inference noise, now also covering `dance`); `tools/count-locals.ps1` OK (Main 138/200).

---

## Carried over after 3.0.0

| Item | Who | Notes |
|------|-----|-------|
| PARKLAB event absen (quest milestones) rollout | owner + agent | PARKLAB is still on 2.12.0 and has no event board. Needs: full engine sync, GUIs `18-EventQuestPopup`, `19-EventReminders` and the `EventTab` templates in `07-MenuGUI`; set `FreeTitleEvent.Trigger = "Topbar"` first (sync wipes the place-only topbar/menu); check `Group.GROUP_ID`; create the quest on the dashboard: 7 days 50 R$ ×100, 14 days 50 R$ ×150, 21 days voucher. Start 2026-10-09. |
| Music panel 3.0 GUI RBXM | owner | Save the cover stack (`BackdropNear`, `BackdropFar`, `CoverImage`) into the template, then export `06-MusicPlayerGUI` v3 with `Enabled = false`. Buyers cannot run 3.0 scripts without it. |
| Delete the duplicate `QueueListTemplate` in `06-MusicPlayerGUI` | owner | Place GUI only. |
| Ctrl+S on THE BASIC TEST | owner | Unsaved synced files. The Experiment Area was saved 2026-10-10. |
| clubkit-infra: commit and push `main`; deploy migration `0024` with `license-routes.js` and `discord.js` | owner | Foreign GUI detail. Migrations 0028 and 0029 are deployed (2026-10-09). |
| 3.0 playtests: 2-player music pass, Stage E gate, per-track cover in game, panel refresh | owner | See UPGRADE.md "Known issues". |
| UI motion: reduced-motion run, phone-emulator pass, live checks | owner | ADR 0011 gate. |
| Security hardening SH2–SH10 (H1 Studio gift bypass, H2–H4 DoS, D4 sticker writes, others) | agent | Guard modes (RemoteStorm, `MovementGuard` `ENFORCE`, SoundGuard, ScriptGuard) are owner decisions. |
| Onboarding modal and cinematic loading | owner | Built, both flags off. Needs an owner verdict. |
| ADR 0020 for the VPS-owned quota and the one-Robux rule | agent | Offered, not answered. |
| Creator live status (`🔴 LIVE`) | owner | Paused at round 3; feasibility spike first. |
| Perf & Structure Lane B (template and place data, RBXM) | owner | Not started. This lane is what justified the major version. |
| Phone checks: dance panel v3 and phone menu rows (2026-10-09) | owner | Panel geometry is verified in a playtest (iPhone 14 landscape: fits, clear of the hotbar). Open the panel and the phone menu by eye. Onboarding stays off in PARKLAB (no `17-OnboardingGUI` sketch). PARKLAB GUI and Config changes are unsaved: Ctrl+S. |
| Topbar overflow = three dots + dropdown (2026-10-09) | owner | Engine fix: `Icon/Features/Overflow` (both Icon copies), `Main` (`keepOutsideOverflow` on Menu and self custom title, row labels), `MusicTopbarIcon` ("Reload Music" row). Only the TopbarPlus copy that loads first runs (`TopbarPlusReference`): a buyer place with its own `RS.TopbarPlus` folder needs the same `Overflow` file there (PARKLAB has two such folders, patched). Verified in PARKLAB on iPhone 7 only; check a real phone tap, then list it in the next release notes. |
| Overhead cash-rank chip assigned to the wrong player (Atlantis) | agent | Backlog. Needs its own diagnosis. |
| Packager `collect()` bundles installed admin loaders | agent | Backlog. |
| RUST and NIGHT ZONE still on a 2.9.2-era build | owner | Plan the jump separately from the release. |
| `sourcemap.json` stale since 2.6.0 | agent | Regenerate with `rojo sourcemap`. |
| Experiment Area: delete the instance-diet leftovers (2026-10-10) | owner | The permission classifier blocked the agent's delete. By hand, after Ctrl+S: `StarterGui.11-StickerSystemGUI`, `StarterGui.10-HotbarGUI.StickerButtonWrapper`, the 5 sticker ModuleScripts (`Server.Services.StickerService`, `Server.Controllers.StickerController`, `Server.Repositories.StickerRepository`, `Client.Controllers.StickerController`, `Client.Utils.StickerBillboardAnimator`), and the 5 `ServerStorage` backup folders listed in the plan §2.D. None of them breaks anything if left in place. |
| `robloxstudio` MCP bridge down | owner | Its Studio plugin is v3.2.0 but the MCP server is v3.1.6 (HTTP 426 `plugin_version_mismatch`). Update the server, or `eval_client_runtime` stays unavailable. Studio's own phone emulator works with the `Roblox_Studio` bridge (used 2026-10-10). |

---

## Unreleased — file table (instance diet Phase 2: sticker removal, 2026-10-09)

Plan: [`docs/plans/instance-diet-2026-10-09.md`](docs/plans/instance-diet-2026-10-09.md) §2. Not committed.
- **Experiment Area:** synced and playtested 2026-10-10, together with Phase 1. The plan has the results under §2.D, §2.E and §Results. The owner saved it (Ctrl+S) the same day.
- **Place leftovers not yet deleted:** the sticker GUIs, 5 sticker modules and 5 backup folders. The permission classifier blocked the delete.

**Upgrade-guide note:** Sticker panel is gone; you may delete `11-StickerSystemGUI` (optional — the kit removes it at runtime).

| File | Change | Buyer-owned? |
|---|---|---|
| `Server/Services/StickerService.luau` | Deleted | no |
| `Server/Controllers/StickerController.luau` | Deleted | no |
| `Server/Repositories/StickerRepository.luau` | Deleted | no |
| `Client/Controllers/StickerController.luau` | Deleted | no |
| `Client/Utils/StickerBillboardAnimator.luau` | Deleted | no |
| `Server/Init/RetiredGuiSweep.luau` | New: boot sweep for retired GUIs (`11-StickerSystemGUI`, hotbar `StickerButtonWrapper`). It also sweeps the PlayerGui of players who spawned before it ran (boot race found 2026-10-10). | no |
| `Server/Init/ServerModuleBag.luau` | Sticker entries removed; `RetiredGuiSweep` added | no |
| `Server/Main.server.luau` | Sticker remotes, service and controller block removed; sweep call at top of boot; boot log text | no |
| `Server/Repositories/ProfileLoader.luau` | Comment only (`stickers` no longer a load kind) | no |
| `Client/Init/ClientModuleBag.luau` | `StickerController` and `StickerBillboardAnimator` entries removed | no |
| `Main.client.luau` | Sticker billboard, hotbar sticker wiring, panel registration and `reg("background", Config.Sticker)` removed; hotbar wrapper visibility lines removed | no |
| `Client/UI/HotbarUIBinder.luau` | `bindStickerRequested` and sticker button handling removed | no |
| `Client/UI/HotbarGuiRefs.luau` | Sticker lookup and fields removed; a hotbar without the sticker wrapper is no longer `ok = false` | no |
| `Client/Services/InventoryChromeAnimator.luau` | Wraps `HotbarWrapper` alone; retired sticker wrapper hidden if present | no |
| `Client/Services/MobileScaleService.luau` | Sticker wrapper and `STICKER_GUI` scale removed | no |
| `Client/Services/StarterGuiTrimService.luau` | Sticker keep removed; header comment updated | no |
| `Client/Utils/ImageSwap.luau` | Comment only (example list) | no |
| `Shared/Constants/Config.luau` | `Config.Sticker`, `Config.StickerAnim`, `FeatureFlags.StickersEnabled`, `Hotbar.STICKER_*`, `MobileScale.STICKER_GUI` removed; `RETIRED_GUI_NAMES`, `Hotbar.RETIRED_CHILD_NAMES` added | no |
| `Shared/Config/ClubKitConfigSchema.luau` | `Stickers` default and feature row removed; `Features.Stickers` added to `RETIRED_KEYS` | no (engine; drives the buyer fill-forward) |
| `Shared/Config/ConfigBootstrap.luau` | `Stickers` to `StickersEnabled` mapping removed | no (engine) |
| `Shared/Domain/TitleImageDomain.luau` | Comment only (no longer names removed services) | no |
| `Shared/Utils/CharacterReady.luau` | Comments only (no longer name removed services or consumers) | no |
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` (template) | `Stickers = true,` removed; nothing else | template (ADR 0001) |
| `CHANGELOG.md` | `[Unreleased]` "Removed" entry with the breaking note | no |
| `tools/HotbarInventoryAudit.playmode.luau` | Dev tool only: the `stickerGui` line (read `Config.Sticker.GUI_NAME`) removed | no (not shipped) |
| `Server/Services/SessionCommandService.luau` | Replace (engine): teleport arrival (AFK and `/rejoin`) restored once in `restoreArrival` after `ClientGameplayReady`; `finalizeRejoinRestore`, the CharacterAdded AFK sync branch and `pendingJoinRestore` / `pendingAfkSyncRestore` removed | no |
| `Server/Services/CommandExecutionService.luau` | Replace (engine): `/sync all <player>` (admin) → `SessionCommandService:handleSyncAll`; Config.Session `CMD_ALIAS_SYNC` + 3 messages | no |
| `Server/Services/SyncService.luau` | Replace (engine): `isDanceStateHealthy` added (real Animator track check) | no |
| `Shared/Constants/Config.luau` | Replace (engine): `AfkGuard` ladder 600/690/780/870 and `IDLE_THRESHOLD_SEC` 600, `AUTO_REJOIN_RATE_WINDOW` 540; `Session.RESTORE_CLIENT_READY_TIMEOUT` 120 (restore anyway on timeout) | no |

Not touched (leave alone per plan): `Shared/Utils/CharacterReady.luau` `findAdornee` logic, `MotionPresets`, the `StickerCollection_v1` DataStore key (data stays, no longer read), `Secrets.luau`, every other buyer config key.

---

## Unreleased — file table (instance diet Phase 1: instance probe, temporary, 2026-10-09)

Plan: [`docs/plans/instance-diet-2026-10-09.md`](docs/plans/instance-diet-2026-10-09.md) §1. Repo only: not committed, not deployed, VPS untouched. The VPS ingest check (1.D) and the solo Studio check (1.F) are owner steps. Buyer config is unchanged; buyers can still opt out with `ClubKitConfig.Telemetry.Enabled`.

| File | Change | Buyer-owned? |
|---|---|---|
| `Shared/Constants/Config.luau` | `Config.Telemetry.INSTANCES_ENABLED`, `INSTANCES_SAMPLE_SEC`, `INSTANCES_CLIENT_BATCH_SEC`, `INSTANCES_FLUSH_SEC` added next to `BUDGET_INTERVAL_SEC` | no |
| `Server/Net/InstanceTelemetry.luau` | New: server sampler, `InstanceProbeReport` receiver (shape check, 240 s per-player gap, silent drop), 15-min flush as `kind = "instances"` (32 KB cap, no ids or names) | no |
| `Server/Init/ServerModuleBag.luau` | `InstanceTelemetry` entry added after `BudgetTelemetry` | no |
| `Server/Main.server.luau` | `InstanceProbeReport` created in the remotes block; `ServerMods.InstanceTelemetry.start(...)` called there (no new top-level local) | no |
| `Client/Services/InstanceProbeClient.luau` | New: client sampler (own count, other players' Backpack and Character, own PlayerGui); one batch per `INSTANCES_CLIENT_BATCH_SEC` | no |
| `Client/Init/ClientModuleBag.luau` | `InstanceProbeClient` entry added | no |
| `Main.client.luau` | `trackPostGameplayBootTask("InstanceProbe", ...)` starts the sampler (no new top-level local) | no |
| `docs/adr/0007-product-telemetry.md` | One-line note: instances probe (temporary) rides phase B | no |
| `CHANGELOG.md` | `[Unreleased]` "Added" entry | no |

---

## On release — agent checklist

1. [ ] User confirms version number
2. [ ] Move `[Unreleased]` in `CHANGELOG.md` to new version section + date
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion` (+ `PLUGIN_VERSION`)
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset unreleased table in this file
7. [ ] Git tag: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** from `tools/ClubKitPackagerPlugin` (plugin-build sync alone is not enough if the place Tool still uses an old binary)
