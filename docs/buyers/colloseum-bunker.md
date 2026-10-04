# Buyer: Colloseum Bunker Club

Status: **migrated from bespoke non-Kit place to Club Kit + Hierapolis place pack. Engine + pack + config + StarterGui GUI layer (2026-10-04) done via MCP in Studio edit session; place published at v4565 before the GUI layer (GUI changes still unsaved). Backend registration + data migration still pending.** Last touched 2026-10-04.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | COLOSSEUM BUNKER CLUB |
| PlaceId | `88199152407881` |
| UniverseId (GameId) | `9241219188` |
| PlaceVersion (last published) | `4565` (v4558 was pre-migration; 4565 includes engine+pack+cleanup, NOT the GUI layer) |
| OwnerRobloxName | COMAxValGen |
| OwnerUserId | `9075246747` (same as Hierapolis) |
| GroupId (Community) | `1068114138` — COMA Studio group (same as Hierapolis; `CreatorType = Group`) |
| `Branding.GameName` | `COLOSSEUM BUNKER CLUB` |

**Shared ownership with Hierapolis**: same owner (COMAxValGen `9075246747`), same group (COMA Studio `1068114138`), same Saweria target (`saweria.co/COMAStudio`). The two places are sister venues under one group.

## B/C. ClubKitConfig — Branding & Group

- `Branding.GameName = "COLOSSEUM BUNKER CLUB"` (changed from Hierapolis default during import)
- `Group.GroupId = 1068114138`, `Group.OwnerUserId = 9075246747`, `Group.OwnerGroupRank = 255` (correct, same COMA group)
- `AdminUserIds` (7): XiaoBey4 `9041379923`, ByuuuByuuu `5170798570`, dboyPKL `8755283537`, Neng_Xyna `9494693960`, Khangmoose `8853397666`, COMAxValGen `9075246747` (owner), scoobidoes13 `9486519141` (inherited from Hierapolis config — superset of Bunker's 5 DPC IDs from PurchaseHandler)
- `ExternalAdmin.Provider = "Kohls"` (Kohl's Admin installed in place; bridge active)

## D. Shop

| Tier | GamePassId | Price |
|---|---|---|
| Tier1 (VIP) | `1616232474` | 100 |
| Tier2 (VVIP) | `1616624371` | 500 |
| Tier3 (Supreme/Patron) | `1616374645` | 2000 |

Source: Bunker's `PurchaseHandler` script (918 lines, "ULTIMATE DONATION SYSTEM V3"). GiftId = 0 (TBD — need gift DevProducts from Creator Dashboard if gifting is wanted).

## Robux donation products (6 DevProducts)

Migrated from Bunker's `PurchaseHandler` into `ClubKitConfig.Donation.RobuxProducts`:

| ProductId | Name | Price (Robux) | VFX tier |
|---|---|---|---|
| `3485101733` | 250 Robux | 250 | Level4 |
| `3485101732` | 500 Robux | 500 | Level5 |
| `3485101730` | 1000 Robux | 1000 | Level6 |
| `3477005806` | Nuke | 500 | Level4 (giant) |
| `3477005805` | Smite | 500 | Level5 (giant) |
| `3477005804` | BlackHole | 500 | Level6 (giant) |

Kit's `ProcessReceipt` now handles these. The giant VFX (Smite/BlackHole/Blossom models in `ReplicatedStorage.WorldEffects`) are kept in place; Kit's `WorldEffectTiers` config already maps cash donation thresholds to `BlackHole`/`Smite4`/`Nuke`. A VFX bridge script (Phase 4b, optional, not yet built) could hook Kit's donation event to `EfekRemotes` for Robux-product-triggered giant effects.

## F/G. Donation + Community backend — clubkit-infra (PENDING)

**Not yet registered.** Same VPS as Hierapolis (`103.42.244.55`, `api.hazastudio.id`, DB `/var/lib/clubkit/db.sqlite`, service `clubkit-api`).

Proposed game key: **`colloseum`**

TODO (blocked on user / VPS access):
1. `POST /admin/games` with game key `colloseum`, universe `9241219188`, place `88199152407881` — generates `social_secret` + `donation_api_secret` + `webhook_token`
2. Set in Studio (`ServerScriptService.Hazastudio_ClubKitSecrets.Secrets`):
   - `Secrets.GameDataApiSecret = "<social_secret>"` (currently empty `""`)
   - `Secrets.DonationApiSecret = "<donation_api_secret>"` (currently empty `""`)
3. `ClubKitConfig.Donation.ApiUrl = "https://api.hazastudio.id/game/colloseum"` (already set)
4. `ClubKitConfig.GameDataApi.GameKey = "colloseum"` (already set)
5. `Donation.Provider = "saweria"`, `Donation.ProviderLink = "https://saweria.co/COMAStudio"` (already set, same as Hierapolis)
6. **Saweria webhook**: paste `https://api.hazastudio.id/webhook/saweria/colloseum/<webhook_token>` into the Saweria dashboard for COMAStudio (add as new target, do NOT replace the `hierapolis` target)
7. `Donation.ReliabilityV2 = true` (already set from Hierapolis import — VPS is the clubkit-infra, not old Cloudflare worker)

Until secrets are set: donation polling throws `invalid_secret` (expected, non-fatal in Studio; live server would skip donation API).

## License

`KitProduct.LicenseEnforcementEnabled = true` (KitProduct from Hierapolis import, build 20260828). License will auto-bind on first successful live boot (place published + player joins). License universe binding will be `9241219188` (Bunker's GameId).

## Engine

- **Installed via rbxm export from Hierapolis** (not repo source sync). Exported 4 rbxm files from Hierapolis Studio instance (`instance:mpx-lwf`): RS (450KB), SSS (505KB), RF+SPS (839KB). Imported to Bunker (`instance:c6p-85j`) via `import_rbxm`.
- All 4 services have Kit folders: `ReplicatedStorage.Hazastudio_ClubKit` (4 children), `.Hazastudio_ClubKitConfig` (3 children incl. HierapolisCustom overlay), `ServerScriptService.Hazastudio_ClubKit` (1) + `.Hazastudio_ClubKitSecrets` (1), `ReplicatedFirst.Hazastudio_ClubKit` (1), `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit` (2).
- `KitProduct.luau` verified intact: 30 lines, `KitVersion = "2.10.0"`, `BuildId = "20260828"`.
- Note: SPS `Hazastudio_ClubKit` was imported into `ReplicatedFirst` (rbxm grouped RF+SPS); manually moved to `StarterPlayer.StarterPlayerScripts` via `execute_luau`.
- **Config & Secrets were from Hierapolis** (game key `hierapolis`, real Hierapolis secrets). Secrets were **cleared** (set to `""` with TODO) to avoid backend conflict. Config values tuned for Bunker (see above).

## Hierapolis place pack

Installed via `extras/place-packs/Hierapolis/install.luau` (dev-serve `http://127.0.0.1:8798/repo/`):
- `ReplicatedStorage.Hazastudio_ClubKitConfig.HierapolisCustom` — overlay module, source refreshed
- `ServerStorage.Tools/{CO-OWNER, THE EMPEROR, THE ECHOBORN, THE MINISTER, THE SENATOR}` — 5 tool folders (imported from `HierapolisToolFolders.rbxm`, moved into a `Tools` folder)
- `ReplicatedFirst.CinematicLoading` — LocalScript + `LoadingUI` ScreenGui (from `CinematicLoadingUI.rbxm`)
- `ClubKitConfig.Features.HierapolisCustom = true` (flag already on from Hierapolis import)
- `ClubKitConfig.Features.LoadingScreen = false` (CinematicLoading owns boot; set by overlay)

Role catalog: same as Hierapolis (The President/Archon/Emperor/Echoborn/Minister/Senator + DJ/Streamer/Influencer). Bunker's old teams {Big Boss, Eminence & Empress, Valorian & Valoria, Servant} are **not mapped** — players to be re-assigned via `/setrole` manually. Servant→Guest, The President→Owner, DPC→DPC roles.

## GUI layer — StarterGui + overhead + boards (2026-10-04)

The 2026-09-30 migration had imported only the 4 engine services; the entire GUI layer was missing (engine ran headless — all binders warned and skipped, music played with no panel). Imported via `export_rbxm` from Hierapolis (`instance:gup-le5`) → `import_rbxm` to Bunker (`instance:a5s-6gw`), staging at `C:\Users\haza\Desktop\bunker-gui-migration\`:

| File | Contents |
|---|---|
| `kit-guis.rbxm` (120 KB) | 25 Kit ScreenGuis → `StarterGui`: `00-LoadingScreen`, `01-CoupleSystemGUI`, `02-ShopGUI`, `03-GiftSystemGUI`, `04-AdminPanel`, `04-AdminPanelv2`, `04-AdminHub`, `05-StreakGUI`, `06-MusicPlayerGUI`, `07-MenuGUI`, `08-CarryGUI`, `09-DonationSystemGUI`, `10-HotbarGUI`, `11-StickerSystemGUI`, `12-CinematicDockGUI`, `13-PaidBroadcast`, `14-BackpackGUI`, `15-TopMenuGUI`, `16-JoinCommunPrompt`, `99-NotificationCenter`, `AvatarContextMenu`, `AvatarContextMenuV2`, `CommandLibraryGUI`, `IconGroup`, `MobileFreecam` |
| `hazastudioBoard.rbxm` (37 KB) | `Workspace.hazastudioBoard` model — 14 boards (CommunityDonation, RobuxDonation, SaweriaDonation, LikesLeaderboard, LiveChatDonations, DailyDonations×3, Top1-3 Robux/Cash) |
| `OverheadGUIMainTemplateV4.rbxm` (16 KB) | `ReplicatedStorage.OverheadGUIMainTemplateV4` — overhead billboard template (105 descendants), live OUTSIDE the kit folder so the 4-service export missed it |

Verified in solo playtest (both `run` and `play` with client):
- `OverheadController Template BillboardGui not found` error **gone**; `OverheadController initialized`, overhead billboard present on the character.
- `WorkspaceLeaderboardRenderService paint incomplete; retry budget exhausted` warning **gone** (boards found).
- Client eval: **25/25 GUIs in PlayerGui**, `GeneralNotificationCenter` built, `IconGroup` populated (5 children), `06-MusicPlayerGUI` hidden until topbar open, `ClubKitGameplayReady=true`.
- `Enabled` states of all 25 GUIs match Hierapolis exactly (MusicPlayer=true, LoadingScreen=false, AdminPanel/Panelv2=false, rest=true).
- Zero kit ERR entries in both playtests.

Known non-blocking noise (pre-existing, not from the GUI import): `RuntimeGuard Rogue sound` ×68 (old music system's transient Sounds under `ReplicatedStorage.Sound`, mode=log), sound asset load failures (archived/not-found/HTTP 502 — Roblox CDN), `Infinite yield` on `PlaytimeBoard`/`PlaytimePart`/`DonationRemotes` (kept old Bunker systems waiting for parts that don't exist).

**NOT copied (intentionally):** `CenzGLightsController` (StarterGui) + `CenzGlightsTopBar` + `FixGLightsQueue` (StarterPlayerScripts) — pirated Cenz build, forbidden; `DualGlowColorGui`, `FOV`, `SignGui` — Hierapolis place-specific, SignGui is built at runtime from a Kit template.

**Owner still owes Ctrl+S** on Bunker — the GUI layer is live in the Studio edit session only.

## Cleanup — old Bunker systems (Phase 4)

| System | Action | Reason |
|---|---|---|
| `ServerScriptService.PurchaseHandler` (918 lines) | **Disabled** (`Enabled=false`) | Kit takes over ProcessReceipt + DevProducts; data migrated to config |
| `Workspace["Donation Board // V3"].Config.Loader` | **Disabled** | Kit has donation leaderboard |
| `Workspace["Donation Board // V3"].Config.ProcessReceipt` | **Disabled** | Kit's ProcessReceipt is the single handler now |
| `StarterPlayer.StarterPlayerScripts.DonationSaweria` | **Disabled** | Kit has Saweria panel via BackendClient |
| `StarterGui.DonationSystemGUI` | **Disabled** | Kit has DonationWrapper notification center |
| `ReplicatedFirst.LoadingScreen` (custom) | **Disabled** | CinematicLoading owns boot |
| `ReplicatedStorage.Ranks` (ModuleScript) | Left (unused) | PurchaseHandler disabled, no `require`; HierapolisCustom handles roles |

### Cleanup phase 2 — Kit-duplicate GUI/server systems (2026-10-04, after the GUI layer import)

All `Enabled=false` via MCP in edit mode. **Key lesson:** disabling a `ScreenGui` in StarterGui does NOT stop its embedded LocalScripts — they still clone into PlayerGui at spawn and run (the old `SettingsClient` printed "already running" and `Loader` still built its backpack UI). The embedded scripts are disabled too.

| System | Action | Reason |
|---|---|---|
| `StarterGui.ShopGui` (+2 embedded scripts) | **Disabled** | GamePass shop — duplicate of Kit `02-ShopGUI` |
| `StarterGui.SettingsUI` (+1 embedded) | **Disabled** | duplicate of Kit `07-MenuGUI` |
| `StarterGui.AdminPanelGift` | **Disabled** (was already off) | duplicate of Kit `04-AdminHub` |
| `StarterGui.MusicSystemUI` (+5 embedded) | **Disabled** | duplicate of Kit `06-MusicPlayerGUI` |
| `StarterPlayerScripts.MusicSystemTopbar` | already off | old music topbar |
| `SSS.MusicSystemServer` (obfuscated, "dc: 333.syn") | **Disabled** | Kit MusicService takes over |
| `SSS.Setting Playback` (playlist driver, 151 asset ids) | **Disabled** | playlist migrated to Kit seed first (below) |
| `SoundService.MusicSoundGlobal` | stopped, Volume=0 | old global music output |
| `StarterPlayerScripts.Loader` (custom backpack, 72 KB) | **Disabled** | disable CoreGui Backpack — conflicts with Kit `HotbarController` |
| `SPS.p` (23 KB) | **Disabled** | 757 lines, 100% commented — dead code |
| `SPS.AdminTopbarClient` | **Disabled** | old admin topbar |
| `SSS.UltimateOverheadGui` | **Disabled** | custom overhead BillboardGui — duplicate of Kit `OverheadGUIMainTemplateV4`; its helper `DisableDefaultName.lua` actively destroyed Kit billboards |
| `SSS.DisableDefaultName.lua` | **Disabled** | see above — was killing Kit overhead GUIs |
| `ReplicatedStorage.MusicSystem` (folder: Remotes/Modules/SFX/MusicConfig 787 ids) | Left in place | inert without `MusicSystemServer`; kept for reference |

**Kept (verified against Kit overlap):** `EventGUI` (Nuke/BlackHole/Fireworks/Hammer → `EfekRemotes` = the kept VFX triggers), `StatusPickerGui`+`StatusServer` (place status system), `AnimationGui`+`SyncincWith`+`Whispering`+`WarningFolders`+`InteractiveMenu` (SyncServer family UI), NPC scripts ×13 + NPC models (6 present: PRESIDENT, ARCHON, ECHOBORN1/2, MINISTER3, SENATOR1), `GlobalChat*`, `RoleManager*`, `AvaClone*`, `COMAGroupService`, `ChatMessageListener`, `DeviceGetter`, `AzulSystem`+`azul`, `GlowstickUI`+`GlowstickColorHandler`, `DiscordGui`+`DiscordTopbar`+`PolicyServiceDiscord`, `LinktreeGui`+`LinktreeTopbar`+`PolicyServiceLinktree`, `Notes*`, `carrygui`+`carryscript`, `AmmoGui`, `VisualsLoader`, `MobileGui`, `LinktreeGui`. Note: `ActionGui` clones in PlayerGui are EasyBar's cooking action UI (kept system), not the old backpack.

### Music migration (same day)

The old system's playlist (`SSS.Setting Playback` → `slowSongs`, 151 asset ids incl. 9 multi-part mixes) was parsed into the Kit seed module `ReplicatedStorage.Hazastudio_ClubKitConfig.MusicCatalog.luau` (written via `set_script_source`, editor-safe): one playlist **"Bunker Legacy"**, 101 tracks, multi-part songs grouped into `parts`. `Features.MusicCatalogSeed = true` was already on. First boot after: `MusicCatalogSeed complete {playlistsCreated=1, added=101, errors=0}`, and the server auto-advance cycles tracks (`Auto-advance at expected end` → `Track changed`). Second boot: `nothing new, skipped=101` (DataStore persisted, seed is additive-once — working as designed).

Playtest evidence after cleanup: zero kit ERR, `Rogue sound` warnings **0** (was 68/run — the old music system was the runtime Sound spawner), `PlaytimeBoard`/`PlaytimePart`/`DonationRemotes` infinite yields gone. Remaining noise is pre-existing/third-party: Adonis remote yields, `Pyrotechnics-Pack:WaitForChild("Panel")`, 6× `Failed to load animation <missing assetid>` (empty `Animation` instances inside the owner's NPC rigs — present before cleanup, only visible now because this is the first play-mode log capturing client t0), sound asset load failures (Roblox CDN).

Kit client music duck: during `ClubKitExternalLoading` (CinematicLoading waiting for the graphics preset pick) the music SoundGroup is held at volume 0 — engine by-design; real players pick a preset and music starts.

**Kept (place-specific, not Kit-duplicate):**
- `ServerScriptService.EasyBar` — bartending system (prefab tools, liquid bottles, toppings, cooking, ragdoll, barista zone, sound replicator)
- `ServerScriptService.SyncServer` — whisper chat, persistent animations, warning systems
- `ReplicatedStorage.VFX` / `WorldEffects` — Smite3/4, BlackHole, Blossom giant donation effects + DonationLevel1-6 sounds + donationPopup template
- `ReplicatedStorage.NotesSystem` — notes/announcement board
- `ReplicatedStorage.POVRemotes`, `EfekRemotes` — POV camera, nuke/blackhole/smite effect triggers
- `ReplicatedFirst.Whitelist` — place access gate (keep, user confirmed)
- `Workspace["Kohl's Admin"]` — third-party admin (bridge via ExternalAdmin.Provider=Kohls)
- `ReplicatedStorage.ProfileService` — save library (left; may be used by remaining systems)

## Playtest verification (2026-09-30)

Solo playtest (`mode=run`), boot **CLEAN** — no fatal errors:
- ✅ `[JoinCommunityMembersService]` pool warmed, `groupId=1068114138`, `memberCount=286` (community data pulled live via roproxy fallback — secrets empty so no API call, but roproxy works)
- ✅ `[MusicRepository]` loaded: `prevPlaylists=1, tracks=0, playlists=1`
- ✅ `[MUSIC SYSTEM] Server: Playing next song` — Kit music system running
- ✅ `[DonationController] Leaderboard payload built`: `dailyCombined=0, dailyRobux=0, robux=0, likes=0, saweria=0, dailySaweria=0, community=0` (all zero — expected, no data yet, secrets empty)
- ⚠️ `[RuntimeGuard] Rogue sound` — Bunker has a `ReplicatedStorage.Sound` folder with many Sound instances (old music library). Kit's SoundGuard detects them as rogue (not in boot-snapshot allowlist). **Mode=log only** (no block). Non-fatal but spammy. Consider: move/whitelist these sounds, or disable SoundGuard if the old music library should stay.
- ⚠️ `Failed to load sound rbxassetid://...: HTTP 502` — some sound assets fail to load (Roblox CDN issue, not Kit)
- ⚠️ `[WorkspaceLeaderboardRenderService] paint incomplete; retry budget exhausted` — expected, place has no Workspace SurfaceGui leaderboard board yet. Kit retries then gives up silently.
- Playtest stop: `BindToClose` blocked teardown (known Kit behavior — Kit flushes DataStore on close). Studio returns to Edit mode eventually.

## Backup (Phase 0)

Before any changes, 4 `.rbxm` files exported to `.tmp/bunker-backup/`:
| File | Size | Contents |
|---|---|---|
| `ReplicatedFirst-children.rbxm` | 33KB | Whitelist, LoadingScreen, README |
| `ReplicatedStorage-children.rbxm` | 236KB | NotesSystem, POVRemotes, EfekRemotes, VFX, Ranks, RunConfig, ProfileService, Icon, AssetManager, PlayAnims, MainTopbarMenu, SignGamepassID, Read Me, ReceiveWhisper, Cloning, UpdateDrunkEffect, GetDevice |
| `ServerScriptService-children.rbxm` | 694KB | AvaCloneSSS, PurchaseHandler, StatusServer, SyncServer, EasyBar |
| `Workspace-donation-kohls-flux.rbxm` | 1063KB | Donation Board // V3, Kohl's Admin, flux kit |

**User should also Save As `.rbxl`** via Studio (File → Save As) for full-fidelity backup before publish.

## Data migration (Phase 5b — PENDING)

Bunker's old DataStores (only accessible on **live server**, not Studio playtest — Studio uses `*_TEST` store names):
- `DonationStats_Fixed_V3` — `{ [userId] = totalRobuxDonated }` per player
- `ManualPerks_V1` — `{ VIP=bool, VVIP=bool, Patron=bool }` per userId

Migration script (one-shot, to run on live server after publish):
1. Read `DonationStats_Fixed_V3` → write `donatedRobuxTotal` to Kit's `Overhead_v1` via `DonationRepository`
2. Read `ManualPerks_V1` → grant Kit `giftedMembership` via `OverheadDomain.addGiftedMembership` (VIP→Tier1, VVIP→Tier2, Patron→Tier3, source `"manual_migration"`)
3. **Dry-run first** (read only, print counts), user approve, then write

Script will live in `.tmp/migrate-bunker-donations.luau` (tooling, not committed). Execute via `eval_server_runtime` on a live server, or Studio with "Enable Studio Access to API Services" + place published.

## MCP session details

- npx server (`@chrrxs/robloxstudio-mcp` v3.1.6) on port `58741`, auth token at `C:\Users\haza\.robloxstudio-mcp\auth-token`
- Bunker instance: `instance:a5s-6gw` (window title "COLOSSEUM BUNKER CLUB - Roblox Studio") — old `c6p-85j` stale after Studio restart
- Hierapolis instance: `instance:gup-le5` — **disconnected 2026-10-04** (window closed during the cleanup session); reconnect by reopening the place
- Both connected simultaneously (multi-instance); pass `instance_id` to disambiguate
- dev-serve (`tools/ClubKitPackagerPlugin/dev-serve.ps1`) on port 8798 for install.luau fetch

## Open items / not done

- [ ] **Backend register**: `POST /admin/games` game key `colloseum` on VPS `api.hazastudio.id` (needs ADMIN_TOKEN)
- [ ] **Set secrets** in `ServerScriptService.Hazastudio_ClubKitSecrets.Secrets.luau` (GameDataApiSecret, DonationApiSecret — currently empty `""`)
- [ ] **Saweria webhook**: add `https://api.hazastudio.id/webhook/saweria/colloseum/<token>` to COMAStudio Saweria dashboard (new target, don't replace hierapolis)
- [ ] **Data migration**: run DonationStats_Fixed_V3 + ManualPerks_V1 → Kit Overhead (after publish, on live server)
- [ ] **Ctrl+S on Bunker** — the 2026-10-04 GUI layer (25 StarterGui ScreenGuis + `hazastudioBoard` + `OverheadGUIMainTemplateV4`) AND cleanup phase 2 (13 disabled systems + MusicCatalog seed) are live in the Studio edit session only; v4565 publish predates both.
- [x] **Rogue sound cleanup** — RESOLVED 2026-10-04: the spawner was the old `MusicSystemServer`/`Setting Playback` (disabled in cleanup phase 2); `Rogue sound` count went 68 → 0 in playtest.
- [ ] **VFX bridge** (Phase 4b, optional): hook Kit donation event → `EfekRemotes` (FireSmite/FireNuke/FireBlackHole) so Robux-product donations trigger the giant VFX. Currently the VFX models are kept but not triggered by Kit.
- [ ] **Re-assign roles** via `/setrole`: Bunker's old teams (Big Boss, Eminence & Empress, Valorian & Valoria) not mapped — players need manual `/setrole <user> <role>` to Kit roles.
- [x] **Workspace leaderboard SurfaceGui** — RESOLVED 2026-10-04: `Workspace.hazastudioBoard` imported from Hierapolis (14 boards); the `retry budget exhausted` warning is gone from playtest logs.
- [ ] **CenzServerController** (Hierapolis pirated build): NOT present in Bunker — do NOT copy from Hierapolis.
