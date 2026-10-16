# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `3.0.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_ — never bump `VERSION` before "okay this is update X.Y"
**Active branch:** `main`

---

## Status summary

**3.0.0 released 2026-10-09.** The full 3.0 progress log (tables, decisions, verification notes) as it stood at release is in [`docs/releases/3.0.0/PROGRESS_ARCHIVE.md`](docs/releases/3.0.0/PROGRESS_ARCHIVE.md). Buyer guide: [`docs/releases/3.0.0/UPGRADE.md`](docs/releases/3.0.0/UPGRADE.md). File list: [`docs/releases/3.0.0/CHANGED_FILES.md`](docs/releases/3.0.0/CHANGED_FILES.md).

## Unreleased — file table (music: server audio probe auto-skip, 2026-10-16)

Category: engine (source sync). Not committed. Built and playtested live in PARKLAB first, then ported from the live scripts (delta against `ServerStorage._Backup_Scripts_2026-10-16.*_preAssetProbe`). No config keys, no DataStore keys, no buyer files.

| File | Change | Buyer-owned? |
|---|---|---|
| `Server/Services/MusicAssetProbe.luau` | **New**: server-side probe (`getCached`, `probeAsync`, `getTrackStatus`, `probeTrackAsync`, `prefetchTrack`); Sound under `ServerStorage.__MusicAssetProbe`; Failure only skips, TimedOut retried then Unknown | no |
| `Server/Services/MusicSession.luau` | `advanceQueue`: cached-Failure skip, background probe of the started track → `advanceQueue("asset_failure")`, lookahead prefetch of 2; `requestTrack` prefetch | no |
| `Server/Services/MusicService.luau` | `requestPlayOnce` rejects `asset_unavailable` on probe Failure | no |
| `Client/Controllers/MusicPlayerController.luau` | `asset_unavailable` message for Request From ID | no |
| `Server/Init/RuntimeGuard.luau` | `__MusicAssetProbe` added to `KIT_ROOT_NAMES` | no |
| `CHANGELOG.md`, `CONTEXT.md` | `[Unreleased]` entry; "Server audio probe" glossary | no |

Verified in the PARKLAB playtest (Server datamodel): private-ungranted, 404, HTTP-400 and non-audio IDs → Failure in ~1 s; good and shared-foreign audio → Success; cached repeat 0 ms; 6 parts in parallel ~1.2 s; probe Sounds cleaned up; no RuntimeGuard flags. End to end: play-once of a private ID rejected with `asset_unavailable`; a queued 404 library track ("Trance") skipped at its turn with no gap; a broken track started before its probe finished ("SOEGI…", a Place ID) was auto-skipped 0.2 s later with `asset_failure`. `count-locals`: MusicSession 11, MusicService 17. **Not yet verified:** a live server, and an asset revoked mid-session. The engine caches a fetch status per id, so a revoke after the server already loaded the track is only caught by new servers.

**PARKLAB data:** library tracks "Trance" (`125021736394780`, 404) and "SOEGI BORNEAN - ASMALIBRASI AMAPIANO" (`123789`, a Place) are broken; they are now skipped, but should be fixed or removed from the library. PARKLAB place changes are unsaved: Ctrl+S, publish.

## Unreleased — file table (title layers + Lead Dance dropdown, 2026-10-15)

Category: engine (source sync), plus one additive template key. Not committed. Built and playtested live in BACKHOME first, then ported from the live scripts.

| File | Change | Buyer-owned? |
|---|---|---|
| `Shared/Domain/SettingsDomain.luau` | `TITLE_LAYER_BASE_SCHEMA`, `_titleLayerBase`, one-shot title-layer reset in `sanitizeStored`, `needsTitleLayerReset`, `SpecialTitleImage` default | no |
| `Shared/Domain/Types.luau` | `_titleLayerBase` on the stored type | no |
| `Shared/Domain/OverheadDomain.luau`, `Shared/Constants/Config.luau`, `Shared/Config/ClubKitConfigSchema.luau` | `SpecialTitleImage = true` in the layer defaults / schema | no |
| `Server/Repositories/SettingsRepository.luau` | Captures the raw-record reset flag in `loadStrict`; `consumeTitleLayerReset` | no |
| `Server/Services/SettingsService.luau` | `load` returns `titleLayerReset`; `grantOverheadLayers` | no |
| `Server/Controllers/SettingsController.luau` | `forcePublicTitleLayers` on the reset join; `syncPlayer` | no |
| `Server/Controllers/AdminController.luau`, `EventBoardController.luau`, `Server/Services/ProfileMenuService.luau` | Grants write the stored layer too (`grantStoredLayers`); image grant forces public `SpecialTitleImage` | no |
| `Server/Main.server.luau` | Late-bound `settingsSync`, passed with `settingsService` to the three grant sites | no |
| `Client/UI/OverheadUI.luau` | Image row gated on `SpecialTitleImage` | no |
| `Client/UI/MenuSettingsCore.luau` | *Title Text* / *Title Image* rows | no |
| `Client/Controllers/SettingsController.luau` | `SpecialTitleImage` label; `_titleLayerBase` carried in payload/save | no |
| `Client/Controllers/LeadDanceDropdown.luau` | **New** — the kit's Lead Dance dropdown | no |
| `Client/Controllers/SyncLeadTopbarController.luau` | Uses `LeadDanceDropdown` instead of TopbarPlus sub-icons; Sync/Unsync | no |
| `Main.client.luau` | `onRequestUnsync` + `syncStore` in the controller deps (no new locals) | no |
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template only: `SpecialTitleImage = true` in `Overhead.DefaultLayers` (existing buyers get it via fill-forward) | **yes** |
| `CHANGELOG.md`, `CONTEXT.md` | `[Unreleased]` entries; glossary for title layers and the dropdown | no |

Verified: `count-locals` OK (Main.server 126, Main.client 138, MenuSettingsCore 140, OverheadUI 113, rest < 60); selene parses every touched file; the two dropdown files are byte-identical to the live place. Live playtest: own title visible, server/client boot clean, dropdown opens under the icon. **Not yet verified:** the reset on a real affected player, and Sync/Unsync from the dropdown with a second player (Studio playtest wedged before the two-player run).

## Unreleased — file table (touch: panel swipes + large Dance panel hotbar, 2026-10-15)

Category: engine (source sync). Not committed. Verified in Studio 2026-10-15 before the port; the repo change is the same logic.

| File | Change | Buyer-owned? |
|---|---|---|
| `Client/Services/MobilePanelManager.luau` | `notifyDancePanel` hides the hotbar only on the phone layout (`PhoneLayout.isPhoneLayout()`), remembers the open decision in `danceHidHotbar` so close always balances it | no |
| `Client/Services/MobileScaleService.luau` | `applyIconGroupLayout` forces `IconGroup.DisplayOrder >= 1` (above `TouchGui` 0, so the thumbstick does not take Dance-list swipes) | no |
| `Client/UI/Music/GuiRefs.luau` | `resolve` forces `06-MusicPlayerGUI` ScreenGui `DisplayOrder >= 1` at resolve time | no |
| `CHANGELOG.md` | `[Unreleased]` "Fixed (touch…)" entry and "Docs" bullet | no |
| `CONTEXT.md` | "Touch panel layer" glossary entry | no |

Verified: `tools/count-locals.ps1` OK on the three code files (MobilePanelManager 40, MobileScaleService 28, Music/GuiRefs 10).

## Unreleased — file table (phone stale hide/show UI: ACM hotbar + panel focus, 2026-10-12)

Not committed. Repo files + the same changes ported into PARKLAB by MCP (place keeps its own ICA sticker handling, so that file was patched surgically, never replaced).

| File | Change | Buyer-owned? |
|---|---|---|
| `Client/Controllers/AvatarContextController.luau` | New deps `notifyAcmOpen` / `notifyAcmClose`; `openPanel` hides the hotbar for the entrance, `closePanel` (the one funnel for every close path) releases it | no |
| `Client/UI/AvatarContextUI.luau` | `ui:open(delaySeconds)` takes the entrance delay as an argument; `setBeforeOpenCallback` removed (and from the disabled stub) | no |
| `Client/Services/InventoryChromeAnimator.luau` | `setupAcmWatcher` rebinds on `ChildAdded`/`ChildRemoved` and re-looks-up `MainWrapper` each grace tick, so the CanvasGroup→Frame swap cannot strand a hide; `notifyHide` stamps `_acmHiddenAt` | no |
| `Client/Services/MobilePanelManager.luau` | `open()` closes the previously focused panel (restore + its close callback) before snapshotting the new one; `showOverlay`/`hideOverlay` cancel first and the dismissal only switches the GUI off on `Completed`, so a re-show after an open-over-open is not undone | no |
| `Client/Controllers/CoupleController.luau` | `requestClose` helper; the X button and the breakup/notification dismiss paths deselect the icon | no |
| `Client/UI/MenuShellUI.luau` | `hide()` fires its bound close callback after the slide-out, so a click-outside deselects the settings icon; the custom title panel opens through MPM (`"customtitle"`) and registers its close | no |
| `Client/UI/CustomTitleUI.luau` | `bindClose(onExit)` + `close(immediate, onClosed)` exit hook wired to the X / backdrop / Submit / Remove paths, so the phone focus comes back on the dismissal | no |
| `Client/Controllers/AdminController.luau` | Role-revocation while the classic panel owns the icon deselects it after `ui:hide()` | no |
| `Main.client.luau` | ACM wiring: the two notify deps are passed into the controller factory; `setBeforeOpenCallback` block removed | no |
| `CHANGELOG.md` | `[Unreleased]` "Fixed" entry for the three phone bugs | no |
| `Server/Services/LevelService.luau` | `flush` restore on failure merges (`+`) instead of assigning, so XP added during the yield survives | no |
| `Server/Services/DonationService.luau` | `handleNotifDisplay` non-batch path requires `DeliveryReportQueue.isKnown` before queueing a display | no |
| `Shared/Utils/DonationAmountFormat.luau` | `formatCompact` returns `1M` for 999,950+ (was `1000K`) | no |
| `Shared/Config/RoleCategoryBuilder.luau` | sorts `table.clone` of `RoleCategories`, not the buyer's array | no |
| `Shared/Domain/TitleAccessDomain.luau` | Admin-granted title bypass moved before `selfServiceOn` gate | no |
| `Server/Services/StreakService.luau` | Added `service:setStreak(userId, days)` for admin manual streak restore | no |
| `Server/Services/RoleToolService.luau` | Candidate folders filtered by existence in `ServerStorage.Tools` before priority selection | no |
| `Server/Main.server.luau` | Wired `/setstreak <nama> <angka>` chat command (adminPanel permission gated) | no |
| `Client/Controllers/JoinCommunityPromptController.luau` | Skip `16-JoinCommunPrompt` popup if local player is already in the group | no |
| `Shared/Config/ConfigBootstrap.luau` | Handle `MinMembership = "none"` to disable free announcement for all membership tiers | no |
| `Shared/Domain/PermissionDomain.luau` | Check `minTierRaw == "none"` before role priority fallback | no |
| `Shared/Domain/AnnouncementRateLimitDomain.luau` | Handle `minTierRaw == "none"` falling through to Player budget | no |

Verified: 7-file luau-lsp pass shows no new diagnostics vs HEAD (only the pre-existing `_hideCounts` key-inference noise, now also covering `dance`); `tools/count-locals.ps1` OK (Main 138/200).

Second pass (same day, self-service custom title panel): `CustomTitleUI` and `MenuShellUI` analyze with the same diagnostic counts as HEAD, `MobilePanelManager` unchanged at 1; all three compile. PARKLAB playtest (iPhone 13 sim): the Free Title topbar icon opens the CT modal with every other GUI off and the dim overlay up; its own X and the dim-overlay tap both restore the hotbar and every GUI (release at t+0.5 s, well inside the watchdog's 3.6 s floor, so it is the panel's own callback); `open("customtitle")` over `open("shop")` closes shop first and leaves the overlay up; the ACM cycle still releases. Submit and Remove share that exit hook but were only read, not tapped. The exit hook is generation-guarded so a reopen inside the dismissal window cannot release the fresh panel's focus — reasoned and typechecked, not live-reproduced (the window is under a second).

---

## Carried over after 3.0.0

| Item | Who | Notes |
|------|-----|-------|
| PARKLAB event absen (quest milestones) rollout | owner + agent | PARKLAB is still on 2.12.0 and has no event board. Needs: full engine sync, GUIs `18-EventQuestPopup`, `19-EventReminders` and the `EventTab` templates in `07-MenuGUI`; set `FreeTitleEvent.Trigger = "Topbar"` first (sync wipes the place-only topbar/menu); check `Group.GROUP_ID`; create the quest on the dashboard: 7 days 50 R$ ×100, 14 days 50 R$ ×150, 21 days voucher. Start 2026-10-09. |
| Music panel 3.0 GUI RBXM | owner | Save the cover stack (`BackdropNear`, `BackdropFar`, `CoverImage`) into the template, then export `06-MusicPlayerGUI` v3 with `Enabled = false`. Buyers cannot run 3.0 scripts without it. |
| Delete the duplicate `QueueListTemplate` in `06-MusicPlayerGUI` | owner | Place GUI only. |
| Live chat board bubble layout in buyer places | owner + agent | `LiveChatBoardMotion` only acts on a board with the bubble layout (`BubbleTail` under `DonationMessage`). The layout exists only in the current place's `Workspace.LiveChatDonations.LiveChatGUI` (2026-10-10: PPS 52 + `PpsScale` 2, `LightInfluence` 0, Inter, flex row, bubble). Export it before rolling out to other venues. This place's engine is older than the repo (old `AccentSurfaceTint`, `Config` > 200k chars) — the no-tint list and `LIVE_CHAT_PERSIST` default were patched in place-side. |
| Ctrl+S on THE BASIC TEST | owner | Unsaved synced files. The Experiment Area was saved 2026-10-10 after it got the whole repo working tree on 2026-10-10: the PARKLAB/RUST engine fixes, the `RetiredGuiSweep` fix and `ThemeData`, at 517/518 parity (Config differs only by the place-only `STYLE = "cinematic"`). Its old rejected place edits (presets, AFK, DemoData, Donation*Controller, AvatarGiant) are now replaced by the repo versions. |
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
| Phone: hotbar does not come back after the avatar context menu (owner report 2026-10-09) | agent | Later. Needs its own diagnosis (`MobilePanelManager.notifyAcmOpen`/`notifyAcmClose`, `InventoryChromeAnimator` "acm" reason). |
| Phone: top menu scale bigger, in proportion to the other panels (owner 2026-10-09) | agent | Later. `TopBarMenuPhone` UIScale is 0.8 (place GUI). |
| DJ Sets removed from the music Library; AFK rung re-arm fix pulled into the repo (2026-10-09) | agent | Engine: `MusicPlayerController`, `AfkGuardDomain`, `AfkGuardService`, `AfkGuardController`, `SessionCommandService`, `Config` (AfkGuard confirm keys), presets `FireStroke`/`GreenOutline`/`ShineOutline`. The Experiment Area's other place-only edits were older than the repo or only mangled comments, and were not taken. |
| BACKHOME (venue `rust`) on 3.0.0 + unreleased (2026-10-09) | owner | Engine and kit GUIs replaced wholesale; old engine in `ServerStorage/_OldEngine_2026-10-09`. Owner: Ctrl+S, enable EditableImage, share assets to the new universe, `DailyDonations*` boards, delete the archive after a good playtest. Web library deduped (476 copies) on the VPS. Place-only switches in BACKHOME's engine `Config`: `Loading.STYLE = "cinematic"`, `Onboarding.ENABLED = true`; buyer config `Music.PlayOnceRequest = "off"`. Boards Robux/Saweria/Likes and posters Top1–3 Robux/Cash replaced with the hazastudio V3 design, scaled to fit inside the old board faces (old boards in `ServerStorage/_Backup_Boards_2026-10-09`); the venue has no Community, Daily, Level, Streak or Couple board parts. |
| PARKLAB fixes 2026-10-10: glowstick panel empty, venue GUIs recoloured, Command icon right of Menu | owner | Engine: `StarterGuiTrimService` (kit GUIs only), `AccentSurfaceTint` (kit GUIs only, music player excluded), `Icon/Features/Overflow` (both copies, order restored on leaving the dropdown), `Config` (`ClientFootprint.STARTER_GUI_TRIM_EXTRA`, `Branding.ACCENT_NO_TINT_GUIS`). PARKLAB patched by hunk (its own copies differ from the repo; AccentSurfaceTint was CRLF): trim, tint and 4 Overflow copies. Playtest: glowstick panel opens with its own colours, music player and glowstick 0 tinted instances, Menu right-most (400 > 200). Owner: Ctrl+S, publish. |
| PARKLAB fixes 2026-10-10: daily Robux board shared across servers | owner | Engine: new `Server/Repositories/DailyRobuxRepository`, `DonationService`, `ShopController`, `Config` (`Leaderboards.DAILY_ROBUX_SHARED`, `DAILY_ROBUX_STORE_NAME`). Synced into PARKLAB (3 files, hash-verified; Config not touched, code defaults). Store tested on a dummy day: dedup per purchase id, sort, time kept. Owner: Ctrl+S, publish, then donate once and look at the board from a second server. |
| PARKLAB fixes 2026-10-10: title preset error, AFK rejoin lands at spawn | owner | Engine: `TitleColorPreset/init`, `SessionCommandService`, `Config` (`Session.RESTORE_CLIENT_READY_TIMEOUT`). Synced into PARKLAB with the 2026-10-09 AFK rung fix and preset `return` fix (8 files, hash-verified; PARKLAB `Config` not touched, the code defaults to 60). Owner: Ctrl+S, publish, then check one real AFK rejoin lands in place. Donation card: the client card renders fine in PARKLAB Studio with a real-shaped payload, and the server polls `/v2/notifications` without errors; still need how the missing card was seen (live or Studio, Saweria or Robux, real or dashboard test). |
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
| `Client/Controllers/FreecamController.luau` | Disables the injected `PlayerGui.Freecam.FreecamScript` (locked camera + stats overlay) | no |
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
