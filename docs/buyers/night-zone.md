# Buyer: THE NIGHT ZONE

Status: **upgraded to kit 3.0 (2026-10-19), plus live-only passes on 2026-10-19 (polish) and 2026-10-20 (event board, streak quest, Lucky Draw; then snap dance fades, Robux world effect tiers, BRM music on, foreign ACM study).** Last touched 2026-10-20.

**2026-08-28 check (place open in Studio):** the engine build **persisted** — `GroupMotionPolicy`, `Client/Utils/GroupMotion`, `CanvasGroupBudgetService` all present, `Config.CanvasGroupBudget` = `{ENABLED = true, 180, 20, 0.5}`, `UIMotion.CANVAS_GROUP_SIZE_STABLE = true`, **0 stale Rojo `init` twins**, `KitProduct.KitVersion = 2.9.2`, `Donation.ApiUrl = https://api.hazastudio.id/game/night-zone`, `ReliabilityV2 = true`. (If this place was opened fresh from the cloud, the owner's Ctrl+S landed; if it is the same Studio session from 2026-08-27, that is still unconfirmed.)

Also ran the ADR 0005 release-gate QA pass here — **0 size violations / 91 CanvasGroups**, ~15 surfaces clean. Detail in [`UPGRADE_PROGRESS.md`](../../UPGRADE_PROGRESS.md).

**New finding:** a leftover **Kohl's Admin** loader is installed in this place. Its dashboard owns the topbar admin slot, and opening it shows a "40% OFF — unlock exclusive commands" purchase upsell to whoever is admin. This is the same leftover-admin-loader problem tracked in the Packager backlog; it also blocked QA of the kit's own admin panel.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | [UPD🌸] NIGHT ZONE |
| PlaceId | `140556013758180` |
| GroupId (Community) | `504061531` |
| `Branding.GameName` | `Night Zone` |

## Engine

- Updated **2.8.9 → 2.9.2 + unreleased CanvasGroup fixes** (ADR 0005) on 2026-08-27 via dev-serve `/repo/` bridge + plugin `SourceSyncCore` (27 files; **15 stale Rojo `init` twins removed**; config fill-forward 0 keys). Playtest clean; budget guard culled 9/10 workspace SurfaceGuis at spawn. Owner must **Ctrl+S**.

## F/G. Donation + Community backend — clubkit-infra (VPS)

Game key **`night-zone`** (`games.id = 5`), already registered with `groups_enabled = 1`, `community_enabled = 1`, license `active`. `Donation.ApiUrl` was already `https://api.hazastudio.id/game/night-zone`; both secrets already valid (poll `200`).

Music (BRM) access: `games.music_enabled = 1` set 2026-10-20 by the owner over ssh (licence `active`, universe `10208344376` bound). Backup: `/var/lib/clubkit/backup-before-nz-music-enable-20261020-113631.sqlite`. Music-enabled games now: rust, night-zone, parklab, thebasic, ruangkota.

Robux world effects (live place, 2026-10-20, owner request): `Donation.RobuxWorldEffectTiers` = 500 Nuke, 1000 Smite3 (green hammer, GreenHammer client effect), 2000 Smite4 (crown hammer), 5000 BlackHole. Cash `WorldEffectTiers` unchanged (100k Nuke / 250k Smite4 / 500k BlackHole). NZ needs `WorldEffects.Smite3` to stay in the place; ADR 0013's runtime prune would break the 1000 tier. Backup: `ServerStorage._Backup_SnapFade_2026-10-20.ClubKitConfig_preRobuxTiers`.

Done 2026-08-27:
- **`ClubKitConfig.Donation.ReliabilityV2 = true` inserted** (key was absent from the buyer file **and** from the schema at that version, so there was no default to fill forward. Corrected 2026-09-18: `ClubKitConfigSchema.fillForward` *does* recurse into nested tables and fill missing nested keys — the rule is "must exist in the schema defaults", not "must be top-level". `ReliabilityV2` is in the schema now.). Enables `/v3/deliveries|delivery-ack|delivery-display|delivery-dlq`.
- **Data migration (delta):** reconciled by `provider_tx_id` — VPS had 85 of the old worker's 86 donations, 0 mismatches. Imported the 1 missing (2026-08-22, VSTxSan_TKAM 15,307). After: **86 donations / Rp 4,791,241 / last_at 2026-08-22T13:26:28Z**, integrity `ok`. Backup: `/var/lib/clubkit/backups/db-pre-nightzone-migrate-20260827-114002.sqlite`.
- Ledger: 7 donations had no `notification_deliveries` row → backfilled as `displayed` (same shape as the 2026-08-22 backfill). Now 86/86 displayed.
- **Dashboard owner login** (`customer.hazastudio.id`, `owner_users.id = 13`): username `nightzone`, password per owner request.
- **TODO (owner-side, required):** paste `https://api.hazastudio.id/webhook/saweria/night-zone/<webhook_token>` into the Saweria dashboard for `saweria.co/lvlcomunity`. Until then new donations keep landing in the old worker's D1.
- VPS `games.provider_link` is empty while config says `https://saweria.co/lvlcomunity` — cosmetic; set via `PATCH /admin/games/night-zone`.

## Same-day note on RUST

While migrating night-zone, the old worker showed **one new rust donation (2026-08-27 10:07, Miebeeone 100,708)** — proof the RUST Saweria webhook had not been moved yet. Imported it too (rust now 435 / Rp 40,481,749) and marked displayed. Same backup covers it.

## 2026-09-18 — support pass (tools, Saweria, emote audit)

Place-only; still **unsaved**, owner owes a **Ctrl+S**. Nothing from this pass changed the repo.

**Role tools were missing for Founder / Co Owner (and more).** `ServerStorage.Tools` still carried
V1-era folder names (`DONOR`, `INFLUENCER`, `MODERATOR`, `TOP DONOR`, …) while the config asked for
the V2 ones. The engine's "folder not found" log is `debug` level, so nothing showed in the console.
Created with a clone of STAFF's 10 tools: `FOUNDER`, `CO OWNER`, `HEAD STAFF`, `GUARD`, `CREATOR`,
`TOP DONATE`, `SPENDER`. Plus `PRIME` ← clone of VVIP and `PRESTIGE` ← clone of SUPREME, because
**`RoleToolService` picks the highest-priority folder *name* before checking the folder exists**, so
the missing `PRIME`/`PRESTIGE` (derived from this buyer's `Membership.Label`) shadowed the working
`VVIP`/`SUPREME` and every Prime/Prestige member had been getting **zero** tools. All 18 role and
membership paths now resolve to an existing folder. **The engine ordering flaw itself is unfixed** —
it bites any buyer who renames their membership tiers. Owner deferred it.

**Saweria notifications: the kit is healthy, nothing is arriving.** `/v2/notifications` returns
HTTP 200, secret and licence fine, `donation_poll` runs every ~6 s. Newest donation on record is
**id 3058, 2026-08-22 13:26 UTC** — 27 days of silence at the time of checking. Owner-side: compare
the webhook URL on `saweria.co/lvlcomunity` with `saweria_webhook` for night-zone in the admin
dashboard, then check `webhook_events` on the VPS for rows after 2026-08-22. Follow `next_cursor`
to the end when reading the API — the list is ascending, so page 1's newest row is not the newest
donation. Side finding: **all 79 donations have `roblox_username = ""`**, so donor→player mapping
has never worked here.

**Emote audit** (owner suspected marketplace revocation): 187 animations, only `Bounce Dance`
(`131474230732063`) fails to fetch. But **zero** of the 187 are owned by the experience owner
Group 504061531 — 122 belong to user `hazatargz`, 61 to unrelated creators, 4 to Roblox. The fetch
test ran in Studio **as the asset owner**, so "Success" there does not prove a live player can play
them; experience-level asset access cannot be queried from Studio. Full TSV was handed to the owner.
Four animation names carry stray spaces (`" Banana Shake"`, `" Belly Twist R"`, `"Cower "`,
`"Atmosfer "`) so they mis-sort and the panel's search cannot find them.

**Buyer config oddity, left alone:** `Group.OwnerUserId = 9867421889, 9094351307,` — valid Lua, but
the second id lands as `Group[1]` and `ConfigBootstrap` only reads a single number, so the second
owner has never been active.

### Still open from this pass

- [ ] Ctrl+S in Studio — the nine tool folders exist only in the edit session.
- [ ] Saweria webhook (owner-side, outside Studio).
- [ ] Prove the dance question with an **alt account in the live game**; if it is asset access,
      the 122 hazatargz-owned animations need re-uploading to the group and the 61 third-party
      ones replaced.
- [ ] Decide whether to fix the `RoleToolService` name-before-existence flaw in the engine.

## 2026-10-19 — kit 3.0 upgrade + polish pass

Place-only, edited live over Studio MCP. **Nothing here is in the repo yet.** Every patched
script has a copy in `ServerStorage._Backup_Polish_2026-10-19` (prefixes `motion__`, `title__`,
`links__`, `mobile__`, `scale__`, `prox__`, plus the earlier polish backups). Owner owes a **Ctrl+S**.

**Upgrade and setup**
- Engine 2.10 → **3.0** copied from hazastudio (SerializationService + local POST). Features enabled,
  demo data and the external dance pack removed, Lucky Draw integrated.
- brm-api `resolveClubKitPlaybackSpeed` fix deployed. 87 web-library tracks backfilled with their
  real speed; they had been playing slowed at 0.625. Backups are on the VPS. See memory `brm-speed-1-dropped`.

**Errors and warnings**
- Leaderboard renderer skips boards the place never built (Level / Streak / Couple). This ended the
  "paint incomplete" warn loop.
- `DonationLeaderboardController`: no warn when the daily part is absent.
- CoOwner and VIP role colours written into the config, which ended the remap warns.
- `LuckyDrawGui` and `VJPanel` waits use `math.huge`.
- `ProximityInterestService.queryNear` nil-position guard, from the crash at line 479. A listener
  yields inside `addMember`, the next tick re-snapshots positions without a respawning player, and
  the old code read a nil position. **The same bug is in the repo (line 478): kit-wide.**
- Not fixable from the place: assets `107725598324481` and `88093974881670` (star / Robux logo in the
  WorldEffects billboards) must be shared with universe 10208344376.

**Motion**
- Centre panels and popups zoom like the ACM: `AnimationHelper` `zoomStable/zoomIn/zoomOut`.
  Donation, Gift, Couple, Admin Spotlight and Lucky Draw (rest scale 0.88) now all open the same way.
- `Config.UIMotion.MOTION_SCALE` 1 → **0.7**, so all UI is about 30% faster. Centre open now takes
  0.84 s and close 0.53 s.

**Boards:** the four main boards use a canvas height of about 1100 px; the six Top posters use pps 40.

**Donations:** Robux donations now trigger world effects. The tiers are in
`ClubKitConfig.Donation.RobuxWorldEffectTiers`: 1000 Nuke, 2500 Smite4, 5000 BlackHole. They feed
`ROBUX_NUKE_TIERS` and `DonationEffectTierResolver.resolveWorldByRobux`. `DonationService` and the
`ShopController` receipt both add `worldEffect`. Porting this needs a schema and template entry.

**Custom title:** `ClubKitConfig.CustomTitle = { MinLevel = 1, MaxChangesPerWindow = 3,
WindowDays = 36500, UnlimitedDonationRobux = 500 }`.
- Everyone gets **3 free changes, for life**.
- A lifetime Robux donation of 500 or more lifts the quota.
- New engine key `UNLIMITED_DONATION_ROBUX`. `ProfileMenuService.quotaConfigFor` turns the quota off
  for donors. The payload carries `customTitleUnlimitedDonationRobux`, and the quota line in
  `CustomTitleUI` reads it.
- Players who changed titles before this pass may have fewer than 3 changes left: the old history
  still counts.
- The server path is verified with a fake repository. The client label has not been seen on screen.

**Links:** `Branding.DiscordInvite = "discord.gg/9ZEEhf8wNF"`, and `Donation.ProviderLink =
"saweria.co/lvlcomunity"` (no `https://`). The link is display/copy only.

**Admin Spotlight on phones**
- **Kit-wide bug:** `Main` registered the old `04-AdminHub` shell with `MobilePanelManager`. On
  phones that shell opened empty and the Spotlight was hidden. The registration now points at
  `04-AdminSpotlight`.
- **Kit-wide bug:** the sheet body used `AutomaticCanvasSize` under a `UISizeConstraint`. The canvas
  was capped to the body, so a capped sheet never scrolled and the bottom of the sheet was out of
  reach on a landscape phone. The canvas is now set by hand in `resize()`.
- Touch layout (`IS_TOUCH`: touch with no keyboard, or touch with a short side under 500 px):
  - The panel and sheets hang under `GuiService.TopbarInset`.
  - The close button is 44 px. Chips, steppers and value fields are 40 px. The speed pill is 44×32.
  - The `/command` column and the `/` hint are hidden, and the placeholder is shorter.
  - Toasts wrap.
  - A focused sheet field shrinks the body above the keyboard and scrolls into view.
- Small screens draw at `PHONE_SCALE = 0.8`, with a design width of `PHONE_MAIN_WIDTH = 420`.
  The width cap is **untested**: the playtest hung.
- The hotbar hides while the Spotlight is open, through a new `"admin"` reason in
  `InventoryChromeAnimator`.
- Desktop is unchanged apart from being centred below the top bar.

### Still open from this pass

- [ ] Ctrl+S in Studio.
- [ ] Owner retest of the Spotlight in the device emulator: phone layout, width, hotbar.
- [ ] Opening the admin icon during the join greeting or loading once left the Spotlight GUI
      disabled with the blur on. Not investigated.
- [ ] One test saw `TopbarEnabled = false` with the kit icons at the bottom of the screen. Not
      caused by this pass. Suspects: `LoadingScreenUI` / `DonationNotificationController`.
- [ ] Share assets `107725598324481` and `88093974881670` with the universe.
- [ ] Test the couple and gift request popups with two players. Test the Admin Spotlight through its
      real button on a phone.
- [ ] **Port to the repo**, kit-wide bugs first: the Proximity guard, the MobilePanelManager
      registration and the sheet canvas. Then the zoom motion, renderer skip, Robux world effect,
      custom-title donor unlock and Spotlight touch layout, with schema and template entries for the
      new buyer keys.

## 2026-10-20 — event board, streak quest, Lucky Draw

Place-only, edited live over Studio MCP. **Nothing here is in the repo yet.** Backups are in
`ServerStorage._Backup_PostCarousel_2026-10-20`, with the suffixes `_preMarkup`, `_preClamp`,
`_preFitWeek`, `_preHeader`, `_preTopbarDoors`, `_preDeck`, `_preSections`, `_preStay` and
`_preShrink`. Owner owes a **Ctrl+S / publish**.

**Board content (VPS, `game_id = 5`)**
- Posts 14–18 rewritten with markup and new titles. Post 13 "tes" is soft-deleted.
- Quest 9 "Absen Harian":
  - Streak 30 days, 21 Oct – 1 Dec 2026.
  - Milestone 500 Robux, quota 5.
- DB backups: `/var/lib/clubkit/backups/pre-nz-*`.

**Event tab (`07-MenuGUI` EventTab)**
- `EventMarkup` turns post body markup into RichText. Cards clamp their body and fade it out.
- `openPost(id, all?)` opens one post from a card. On join it opens all of them.
- The header colour matches the body colour (`EventCardKit.tintHeader`). The carousel header follows
  the current post's icon and tint.
- Sections, top to bottom:
  - **Events**: countdowns, cloned from PostsSection, LayoutOrder 2.
  - **Quests**: LayoutOrder 3.
  - **Announcements**: LayoutOrder 4.
- Header icon assets: broadcast `80833761298381`, countdown `82464275685344`, quest
  `139401731343393`. Header icons are **20 px** (were 26) in the StarterGui templates of
  `07-MenuGUI`, `18-EventQuestPopup` and `19-EventReminders`. The post popup and the loading-screen
  card clone those templates, so they follow.

**Streak quest popup (`18-EventQuestPopup`, `EventQuestPopupUI`)**
- The popup is one column, 340 wide. It holds a deck carousel with three kinds of card:
  - streak dots, with a flame on each done day;
  - the daily prize, from `Config.EventBoard.QUEST_DAILY_PRIZE` (50 Robux, first 50 check-ins a day);
  - one card per milestone.
- A quest that has not started yet opens as **"Coming in hh:mm:ss"** (`openComingSoon`). The server
  sends `upcomingStreak.startsIn`.
- The popup uses the centre-panel zoom when it opens and closes.
- **Size (owner-approved in playtest):**
  - `Wrapper.Scale` rest is **0.825** (was 1.1).
  - Text grows to stay readable at that scale through `readable(size)`: +3 at 13 px or less, +2 up to
    16 px, +1 above. This applies to the template labels and to `EventQuestPopupUI:_text`.

**Check-in stay lock**
- **`Config.EventBoard.CHECKIN_STAY_MINUTES = 30`** (owner, 2026-10-20). Set it to 0 to turn the lock off.
- The time is saved per player as `ProgressDoc.stay = { day, seconds }` (WIB day). It is an additive
  field, handled by `sanitizeProgress`, `mergeProgress` and `pruneProgress`, plus the new
  `stayToday` / `addStay`.
- The server adds `PLAYTIME_TICK_SECONDS` per tick, only while a streak quest is active, and stops
  adding once the lock opens. Because the count is saved, a rejoin or server hop does not reset it.
- `onCheckIn` refuses a check-in that comes too early. Quest rows carry `stayLeft` and `stayMinutes`,
  and the popup button shows a locked countdown.
- The domain tests pass in playtest. **End-to-end is unverified:** quest 9 starts 21 Oct.

**Topbar (Main, left)**
- The flame toggles the streak popup, or shows "Coming soon" when the quest is still upcoming
  (`EventBoardController.onStreakChanged` / `toggleStreak`).
- A title button sits next to it and shows the player's own custom title.
- The "flame only after refresh" report was **not reproducible** in fresh playtests: the first
  relayed state already carries `upcomingStreak`. It was most likely caused by hot-editing
  `buildState` while the server was running.

**Other**
- Lucky Draw: the Studio friend padding is removed (server and client). The client attaches
  `AccentSurfaceTint` to `LuckyDrawGui`.
- `WavyProgress` is removed from `NowPlayingView`, because it froze the music panel on close.
- The dashboard "show on join" flag lives in clubkit-infra `apps/api` (`event-routes.js`,
  `lib/event-board.js`, `venue_posts.show_on_join`). The React source of the dashboard is on the VPS,
  not in the local checkout.

### Still open from this pass

- [ ] Ctrl+S / publish in Studio.
- [ ] 21 Oct, in the live game:
  - the check-in lock (button locked, then open after 30 minutes);
  - the deck cards at the new text sizes;
  - the popup in the phone emulator;
  - the Lucky Draw tint.
- [ ] `daily.remaining` (daily prize slots left) needs a per-day check-in count from the VPS. That
      is an API change plus a deploy, so ask before doing it.
- [ ] Event Level: a fair EXP-gained leaderboard and a 30-minute/day overlay chip. Designed, not built.
- [ ] Gacha: 15-minute eligibility and an auto spin at 20:00. Not built.
- [ ] Port to the repo + `CHANGELOG`. `CHECKIN_STAY_MINUTES` and `QUEST_DAILY_PRIZE` are place
      config and need a decision on whether they go into the buyer schema.

## 2026-10-20 (later) — dance feel, donation tiers, foreign stack study

Place-only, edited live over Studio MCP. **Nothing here is in the repo.** Owner owes a **Ctrl+S / publish**.

**Snappier dance fades (owner request; the client plays breakbeat and the dances change moves fast)**
- `ClubKitConfig.Sync` in the place: `FadeIn`/`FadeOut` **0.25** (were 0.45), `SwitchFadeIn`/`SwitchFadeOut`
  **0.2** (0.45), `SyncJoinFade` **0.25** (0.4), `SwitchInputCooldown` **0.2** (0.45). The values were
  checked at runtime as `Config.Sync.*`. Engine defaults are unchanged.
- Backup: `ServerStorage._Backup_SnapFade_2026-10-20.ClubKitConfig`.
- If it still feels soft, the next step is 0.12–0.15. If the client approves, consider a documented
  "snappy" preset in the template rather than new engine defaults.
- The dance preload is not the cause: NZ already has `DANCE_PRELOAD_FULL_CATALOG = true` (150 anims).
  `PreloadAsync` only caches; tracks come from `LoadAnimation`.
- Feel study vs `Workspace.SyncBhms`: [`docs/plans/foreign-acm-study/syncbhms-dance.md`](../plans/foreign-acm-study/syncbhms-dance.md).
  The open candidate is priority: the kit forces `Action4`, while SyncBhms keeps each asset's own priority.

**Robux world effects:** the tiers are now 500 Nuke, 1000 Smite3, 2000 Smite4, 5000 BlackHole (see
section F/G). This replaces the 1000/2500/5000 tiers from 2026-10-19.

**Foreign avatar menu, carry and dance (another dev's, obfuscated)**
- Still live and **not removed**: the owner wants it studied for the kit first, then deleted in full.
  The notes are in [`docs/plans/foreign-acm-study/README.md`](../plans/foreign-acm-study/README.md).
- The parts are `StarterGui.AvatarMenu`, `SSS.AvatarMenu`, `SSS.CharacterMenu`, `RS.ProfileFetcher`,
  `StarterGui.Carry`, `RS.CarryReplic` and `SSS.CarryMenu`. Kit `Features.AvatarContextMenu` and
  `Features.Carry` are both `false`.
- Its feel comes from responsiveness, not animation: it opens on mouse **down**, shows instantly, and
  fades a white outline Highlight on the target.
- A foreign dance backend is still alive. At runtime, `RS.Events` gains 7 remotes (UpdateSyncStatus,
  UpdateSpeed, DanceShutdown, ResetCamera, TransferLead, CheckWhitelist, SyncDanceClient), created by
  `SSS.AvatarMenu` or `SSS.CarryMenu`. It is not yet known which one.
- Leftover dead remotes: RequestSync, UpdateAnimation, ToggleFavorite, RequestFavorites, AdjustSpeed.

**`Workspace.SyncBhms` (added by the owner for study):** its server Scripts (`Main1`,
`WarningSystems`, `PersistentAnimations`) run in Workspace and infinite-yield. Move the folder to
ServerStorage, or delete it, **before publishing**.

**Playtests:** multi-client playtests are too heavy on the owner's machine. Use solo playtests, and
ask before starting a multi-client one.

### Still open from this pass

- [ ] Ctrl+S / publish (after moving `Workspace.SyncBhms` out).
- [ ] Client feedback on the snap fades: keep them, go lower, or try asset priority instead of `Action4`.
- [ ] Decide whether the cash `WorldEffectTiers` should follow the new Robux order (Nuke → Smite3 →
      Smite4 → BlackHole).
- [ ] Find which obfuscated script creates the foreign dance remotes: disable one at a time in a test copy.
- [ ] At the end, delete the foreign AvatarMenu, Carry and dance stack, with its `RS.Events` remotes,
      and turn on the kit ACM and Carry if wanted.
- [ ] Port the kit-side ideas (ACM opening on press, outline Highlight, snappy preset) through the
      grill-with-docs process first.

## Open items

- [x] Owner: Ctrl+S / publish — engine files present in the place as opened on 2026-08-28 (see status note)
- [ ] Remove the leftover Kohl's Admin loader (or confirm the owner wants it), then QA the kit admin panel
- [ ] Owner: paste Saweria webhook URL (see above)
- [ ] Align VPS `provider_link`
