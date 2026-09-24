# Changelog

All notable Club Kit changes are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

Active version: see [`VERSION`](VERSION).

---

## [Unreleased]

### Added
- **Budget telemetry, minimal (production hardening P1, workstream F / ADR 0007 phase B).** New `Shared/Utils/BudgetMeter` counts DataStore requests by type (hooked in `BudgetGate`, lowest remaining budget from `DataStoreScheduler`), HTTP requests by endpoint class (new `Server/Net/HttpRequest` wrapper around every kit `RequestAsync`/`GetAsync` except `LicenseService` and `IntegrityTripwire`, behaviour unchanged), MessagingService publishes by topic and budget events (`budget_low`, `load_requeued`, `load_gave_up`, `leave_flush_retry`, …). `snapshot()` for code; the server logs one summary line every 60 s at info (`Config.BudgetMeter.LOG_ENABLED` / `LOG_INTERVAL_SEC`, engine constants). Sending it to the VPS is left for P3 (`BackendClient`).
- **Event board: announcements and quests from the customer dashboard (ADR 0015).** A new page **Event** in the customer area (tabs Pengumuman / Quest, live card previews) authors venue posts and venue quests; the game pulls them from `{ApiUrl}/v3/event-board` about every minute (ETag, back-off, last good board cached in DataStore `EventBoardCache_v1`, so an outage never empties it) and shows them in the menu's new **Event** tab (`07-MenuGUI` `EventTab`: Announcements section, Quests section) — reached from the top menu's Event row, and Quests jumps to its section. **Posts:** category, title, body, optional Roblox image asset id (pasted by the customer; nothing uploaded); the card's button opens the full post in a popup, and one post can be flagged to pop up once per player on join (after the loading screen). **Quests:** goal = reach level N, streak check-ins N days (a daily button, WIB day, the Daily Quest grace/reset rule; six day squares = today and the next five), Robux donated since the quest started, or play time since it started; reward = permanent membership tier (skipped if already held), custom title (only if the player has none, text-filtered), or XP; WIB start/due dates, hidden once past due; claim by button, checked on the server, recorded atomically first (a claim another server already paid is refused) and rolled back if the grant fails; completion is announced server-wide. **New DataStore key (additive, no migration):** `VenueQuestProgress_v1` (per player: counters, check-ins, claims, join posts seen). New: `Shared/Domain/EventBoardDomain` (lune spec 58/58), `Server/Services/EventBoardProvider`, `Server/Repositories/VenueQuestProgressRepository`, `Server/Controllers/EventBoardController`, `Client/UI/EventTabUI`, `Client/Controllers/EventBoardController`. Changed: `Config` (`Config.EventBoard`), `ServerModuleBag`, `Main.server` (+1 local), `ShopController` (`onRobuxDonated` hook), `MenuGuiRefs` + `MenuShellUI` (an optional third tab; the two tabs are no longer hard-coded), `TopMenuController` (Event/Quests rows open the tab; "coming soon" only where the menu has no EventTab), `ClientModuleBag`, `Main.client`. Infra (clubkit-infra): migration `0025_event_board`, `apps/api/src/lib/event-board.js` + `routes/event-routes.js` (owner CRUD + game pull; 12 new tests, 60 existing green), dashboard page `pages/Event.tsx` + `lib/events.ts`. The Daily Quest addon is superseded (keeps working where installed). GUI (`EventTab` two sections, the `EventTabIdle` tab button, `PopUpMenuTemplate`) ships RBXM/manual; the code does nothing in a menu without EventTab.
- **Top menu: Quests and Event rows (owner's 2026-09-24 menu design).** Two new rows in section 2 of the top menu, `QuestsButton` and `EventButton`, on desktop and phone. Neither feature exists yet, so a click closes the menu and shows a notification ("Quests are coming soon." / "Events are coming soon.", `Config.TopbarMenu.QUESTS_SOON_MESSAGE` / `EVENT_SOON_MESSAGE`). `Client/UI/TopMenuGuiRefs` + `Client/Controllers/TopMenuController`, `Shared/Constants/Config`. The rows are GUI (`15-TopMenuGUI`) → RBXM/manual; a menu without them behaves as before.
- **Kit-drawn covers speak the boards' colours (ADR 0014 addendum 2026-09-24).** Every track's artwork now takes one leaderboard board's colour family (orange, red, pink, purple, violet or blue — the kit UI's spectrum; no gold/yellow, green, teal or neon), dark, in one of three very soft Apple-style fields: mesh, light from above, folded sheets. No grain. Wide or tall slots crop the artwork instead of squashing it. The EditableImage is 48×48 (7× cheaper to draw; the artwork has no fine detail). `Shared/Domain/CoverMesh` (parity spec 267/267 against the JS reference), `Client/UI/Music/CoverArt`. Every cover changes once on update. The dashboard preview (`clubkit-infra` `lib/cover-tile.ts`) runs the same code and is already live (2026-09-24). Code-only → source sync, no RBXM.
- **Venue switches for the Auto Dance and Lead Dance topbar buttons.** `ClubKitConfig.Features.AutoDance` and `Features.LeadDanceTopbar` (both default `true`, filled forward) hide the "Auto" and "Lead Dance" topbar pills. Following a leader from the avatar menu still works with Lead Dance hidden (`ConfigBootstrap` → `Config.AutoDance.ENABLED` / `Config.Sync.LEAD_TOPBAR_ENABLED`, read in `Main.client`).
- **Couple leaderboard.** The V3 `CoupleBoard` now shows live couples, longest together first: "A & B", both faces, and "N DAYS". A new OrderedDataStore, `CoupleLeaderboard_v1`, records each pair once, when it is first seen. The kit never stored when a couple formed, so couples that already exist start counting at their first join after this update. A breakup removes the pair, and the top pairs are re-checked against both players' data when the board is rebuilt.
- **Level and streak leaderboards.** The V3 `LevelDonationBoard` and `StreakBoard` now show live data. The Level board is ranked by level, then XP within that level, and shown as "LV 168". The Streak board is ranked by current streak and shown as "10 DAYS". Two new OrderedDataStores, `LevelLeaderboard_v1` and `StreakLeaderboard_v1`, are fed from the values the overhead already holds (Overhead_v1 is unchanged). Existing players appear as they next join. A streak that is already broken (3+ days without a login) is dropped from the board when it is rebuilt. The boards refresh every 2 minutes (`Server/Repositories/ProgressLeaderboardRepository`, wired in `OverheadController` / `DonationController`, specs in `WorkspaceLeaderboardRenderer`).
- **All Tracks, New Drops and Liked Tracks show a dealt stack of track covers.** Sets without a cover of their own now cycle the listed tracks' covers through the Library header stack: every few seconds the front card flies off, the next one pops forward and a new cover joins at the back (`Client/UI/Music/LibraryView`).
- **Copy-link button guides the copy.** Roblox gives games no clipboard access, so the donation panel's copy button selects the provider link and turns into "Press Ctrl+C / Cmd+C" ("Hold the link, then tap Copy" on touch-only devices); pressing Ctrl+C or Cmd+C while the link is selected shows "Copied ✓" for 2 s, and leaving without copying restores the button's own label. Clicking the link box itself does the same. Replaces the "Link selected" toast (`Client/UI/DonationSystemUI`).
- **Leaderboard rows 5+ can use their own card.** A board whose list holds a plain row next to `BasicCardTemplate` (named `BasicCardTemplatePlain`, or `BasicCardTemplate6+` as in the V3 design) now shows rank 4 on the template and ranks 5 and below on clones of the plain row; boards without one behave as before (`Shared/Leaderboards/WorkspaceLeaderboardRenderer`, same rule in `Client/Controllers/DonationLeaderboardController` for client paint).
- **Leaderboard boards and posters have idle motion.** Each client animates what a board already has, nothing is added: the glow images `GradientLight1` / `GradientDarkCenter` / `GradientLight2` drift on long, unrelated periods (mesh-gradient feel, colours trading places), podium avatars sway in a wave (a couple's two heads bob in turn), the colour band of each podium bar's own UIGradient drifts, and the #1 figure pops now and then (`Client/UI/BoardAmbience`). Only nearby boards in view update, reduced motion keeps them still, and a board opts out with the SurfaceGui attribute `AmbientGlow = false`.
- **Track covers are drawn by the kit — nothing is uploaded (ADR 0014).** A track without its own image cover now shows a cover the client draws: a mesh-gradient artwork seeded by title + DJ (`Shared/Domain/CoverMesh`, a bit-exact port of the approved cover lab) with the cover text on top in one of eight layouts — editorial, sampul, samping, monogram, piringan, tiket, swiss, cd (`Client/UI/Music/CoverTile` + `CoverArt`). **Everything about the look is set in the customer area, nothing in Studio:** layout per playlist (Edit playlist → Gaya cover lagu), headline mode (playlist name / song title) and corner name per venue (Musik → Cover lagu di game → Atur), lines per track (Edit lagu → Teks cover). brm-api resolves them into one `track.cover` in the pull; the kit only draws it, filling in the experience's name for an empty corner mark and applying the venue-name and ticket rules (`Shared/Domain/CoverTextPick`). No `ClubKitConfig` key, no player setting, no DataStore change. Artwork is three UIGradient layers everywhere and an EditableImage (128², built off-frame, LRU 64) only where the experience owner is allowed to use one. Full tiles (library DJ-set header, Now Playing, vote card) are a CanvasGroup with a clipping frame inside, so a letter or notch never spills out of the tile even when the client runs out of CanvasGroup memory; every list in the panel — playlists, DJ sets, tracks, the queue — shows the full cover (text and layout, as on the web), filling the slot edge to edge; a DJ set's card shows its first song's cover. List cards skip the CanvasGroup where the client has per-corner radii and are built a few per frame (≤4 ms), so a full Library costs 2 CanvasGroups instead of ~30. Switching playlists pops the cover forward and fans the stack out from behind it — no fade. On short phones the music panel scales down until it fits the screen (tabs and controls were off screen on a 339 px-tall phone). Customer image covers and playlist covers are unchanged. Thumbnail upload from links is off (`LINK_COVER_UPLOAD_ENABLED`, brm-api) after a cover drew a Roblox moderation strike.
- **The ACM's 3D avatar looks at the cursor (`Config.AvatarContext.GAZE_*`).** Open a profile on a mouse and the avatar now faces you and follows the pointer with its head instead of turning on the spot: head yaw ±40° and pitch ±25° off the viewport's centre, normalised by the panel so its far corner is a full turn, and easing back to centre whenever the cursor leaves the panel. **The auto-rotate spin is off while gaze is running** (owner's call) — the body holds facing the camera, so the head never has to snap back when a spinning body turns away. Opt-in per viewport (`AvatarViewport3D:setGazeFollow`); the Avatar Context Menu's v1 3D avatar, the donation panel's donor avatar (hit area = its `MainWrapper`) and the menu's profile tab (hit area = the menu's outer wrapper) all ask for it. A gaze viewport idles while its panel is hidden (every GuiObject up to its ScreenGui visible and enabled), so the profile tab's always-loaded avatar costs nothing with the menu closed. They all keep the plain spin on touch or gamepad (no pointer to follow), under `GuiService.ReducedMotionEnabled` (ADR 0011), on a rig with no neck joint, or with `GAZE_FOLLOW_ENABLED = false`. Engine-owned constants — no new `ClubKitConfig` key. Under the hood gaze writes the neck joint's **rest offset** (`Motor6D.C0`, or `Attachment0.CFrame` on the `AnimationConstraint` rigs Roblox ships now), never its `Transform`, which the `Animator` rewrites every frame at every render priority — so the look composes on top of the idle animation instead of fighting it, and head accessories come along for the ride. **The body leans into the look too (R15):** `UpperTorso.Waist` carries 35% of the yaw and 20% of the pitch (`GAZE_WAIST_YAW_SHARE` / `GAZE_WAIST_PITCH_SHARE`), the neck the rest, so the head still reaches the full angle while the torso turns with it; R6 has no waist and keeps the neck-only look, and `GAZE_WAIST_ENABLED = false` turns the lean off. **Spin and gaze now take turns (owner's call 2026-09-21, replacing "spin off under gaze"):** once the cursor has been off the panel for `GAZE_RESUME_SPIN_DELAY` (1.5 s) the body spins again at `AUTO_ROTATE_SPEED`, easing up to speed (`GAZE_SPIN_RAMP`); when the cursor comes back the body turns to face the camera the short way and then sways ±`GAZE_SWAY_ANGLE` (12°) every `GAZE_SWAY_PERIOD` (6 s), the head subtracting the sway so its look stays on the cursor. `GAZE_SWAY_ANGLE = 0` holds the body still. Head and body ride critically-damped springs (`UISpring`; `GAZE_HEAD_SPRING_FREQ` 1.6 Hz, `GAZE_BODY_SPRING_FREQ` 0.9 Hz) updated every frame, so spin → turn-back → sway is one continuous curve with no velocity jumps.
- **Image custom titles are a paid add-on now, locked by default (`Features.ImageCustomTitle`).** The image tab of `04-AdminPanelv3` is sold apart from the standard package, so the new flag ships **false** and the whole path is shut: `AdminPanelV3UI` refuses that tab's Apply, never asks the server for the image registry, and - when the buyer's GUI carries a `LockedState` frame under `CustomTitleWrapper.Wrapper` - shows it over the image tab so the panel explains itself instead of failing silently. A GUI without that frame bounces the tab back to text rather than presenting a form the server will refuse. **The gate that actually holds is server-side:** `AdminController` drops `SetTitleImage` and answers `TitleImageList` with an empty list unless the flag is on, because those remotes stay callable by any admin whatever the panel shows. The text custom-title tab is untouched. A buyer already using image titles must set `Features.ImageCustomTitle = true`.
- **Daily Quest addon: check in, keep the streak, earn a membership (`1000-02-DQ-ADDON`).** With `Features.DailyQuest = true` **and** the `1000-02-DQ-ADDON` ScreenGui in StarterGui, the daily streak stops advancing on join; players press **Check in harian** in a draggable card instead. The card opens on its own a few seconds after the loading screen when today's check-in is still open, and from a topbar flame icon any time. A buyer quest (`ClubKitConfig.DailyQuest`: `QuestId`, `TargetDays`, `StartDate`/`DueDate` in WIB, `RewardTier`, `Title`) keeps its **own progress counter** on `Overhead_v1` (new `dailyQuest` field — no new DataStore key): +1 per check-in day, one skipped day forgiven, two or more start over at 1, a long existing streak does not count. Reaching `TargetDays` grants the reward tier **permanently** as a gifted membership (source `daily_quest`) in the **same** `UpdateAsync` as the check-in, skips the grant for players who already hold that tier or higher, and announces the finisher server-wide. One circle per target day. **The flame flies:** after the streak overlay's counter and sparks, its flame shrinks along an arc into today's circle, which only then fills (progress bar with it); reduced motion fills it without the flight. Flag off or GUI missing = byte-for-byte the old join-time streak. Pure rules in `Shared/Domain/DailyQuestDomain` (`.tmp/daily-quest-spec.luau` 68/68); service + panel verified in THE BASIC TEST playtest with an in-memory repo (no DataStore writes). Reaches buyers by **source sync + the addon GUI (RBXM/manual)**; config keys fill forward.
- **The playlist detail cover is now the top of a stack (music v3).** The two decorative frames behind it — `TrackListLeft.Wrapper.BackdropNear` and `.BackdropFar` — get their `CoverImage` painted with **two distinct image covers off the opened set's own tracks**, so the detail reads as a pile of albums instead of one floating square. The pair is chosen from a hash of the set's id, never `math.random`: the detail panel repaints on most store changes, and a re-roll on each repaint would flicker the art. A set with fewer than two image-covered tracks falls back to its own cover for the slots it cannot fill. Opening a different set collapses both frames onto the front cover's plane and fans them back out, the back layer landing last (0.34 s / 0.44 s, Quint Out); silent under `GuiService.ReducedMotionEnabled`, and skipped under a `CanvasGroup` (ADR 0005) in favour of the fade alone. **Every lookup is optional and silent** — a place whose GUI does not have these frames, or has them without the `CoverImage` child, keeps exactly the panel it has today, so this visual reaches other buyers only through the music GUI RBXM, not through a source sync. The queue row template's identical pair is deliberately left alone.
- **Foreign GUI report: exploit windows are named, not guessed (ADR 0012).** Most exploiters here run a GUI executor, so the kit now watches `PlayerGui` and reports any GUI that was not there once the place finished loading — by **name**, with the **names and classes of the scripts inside it** ("laporan di discord harus menyertakan spesifik nama gui/script nya"). The report lands in the vendor's Discord as its own kind of alert, separate from a saveinstance hit, with the evidence in a code block. **It only reports: nobody is kicked, nothing is blocked, and there is no switch to make it kick** — there is no field data yet and a wrong answer would cost a paying guest. **It can only see `PlayerGui`:** `CoreGui` is unreachable from game code, so an executor that hides its window there is invisible and a quiet feed is not an all-clear. False positives are designed out rather than tuned out: everything present after a configurable grace period (`AntiTamper.ForeignGuiGraceSeconds`, default 20 s) is legitimate forever, any name that exists in `StarterGui` is allowed (so respawn re-clones and place add-ons never fire), the kit's own runtime GUIs are known, and buyers list anything else in `AntiTamper.ForeignGuiAllowNames` (ships with Adonis / Kohl's / HD Admin). Privacy: only GUIs that appear *after* boot are ever sent — the venue's own GUI inventory never leaves the client. Everything a client says is treated as hostile: caps (5 script names, 64 chars each, 480-char detail, 3 GUIs per player, 8 per server) and the sanitiser that defuses backticks, `@everyone`/`@here`/`<@id>` and control characters are applied on the client, **re-applied on the server**, and applied a third time by the licence API. `AntiTamper.ForeignGuiDetect = false` turns the whole thing off. **Off in Studio:** `ForeignGuiGuardService.start` returns before watching anything when `RunService:IsStudio()` is true, so playtests and plugin-made GUIs never beacon. Code-only → source sync, no RBXM; the VPS side needs a deploy (migration `0024`).
- **One UI motion vocabulary; every panel is alive while it is open; reduced motion is honoured everywhere (ADR 0011, branch `ui-motion`).** `Client/Utils/UIMotion` — promoted from the v3 music panel's `MusicMotion`, which is deleted — is the module every panel uses for what happens between open and close: press squash and hover lift on buttons, icon pops, wiggles and spins, staggered row fade-ins, layout-neutral tab slides (equal-and-opposite `UIPadding`, so a laid-out page never changes size), a breathing `pulse`, and `countTo` for numbers. It decides layout safety itself — nothing inside a layout is scaled and nothing under a `CanvasGroup` is scaled (ADR 0005) — and it snaps or skips under `GuiService.ReducedMotionEnabled`, which before this only the music panel read; `AnimationHelper` (open/close, backdrop blur + zoom), `PressFeedback`, `GuiFade` and the TopMenu sidebar spring now snap to their end state under reduced motion too. Re-animated with it: Shop, Gift, Donation panel + toast, Menu/Settings/Profile, Dance, Avatar context menu, notification center + join greeting + broadcast, streak, free-title card, join-community prompt, hotbar + backpack, command library, carry, emote list, sync panel, mobile freecam, sticker, couple, top-menu sidebar, Admin v3, Admin Hub, classic admin, custom title, cinematic dock and the music panel — tab pages slide in the direction of travel, rows cascade in, icons pop on success and wiggle on refusal, numbers roll to their value, and one breathing highlight marks whatever is waiting (the recording button, a pending couple request, the donation toast). Open/close choreography is unchanged; the loading screen, the overhead nametags and the Workspace donation leaderboard are deliberately untouched. Three side effects worth knowing: the command library now opens and closes through `AnimationHelper` (its own scale tween ignored reduced motion and `MOTION_SCALE`); the self-service custom title panel wiggles the text box on an empty title instead of sending a request the server would refuse; and the panel backdrop zoom now undoes exactly the FOV delta it applied, which also fixes the avatar context menu double-counting its zoom on two close paths. Runtime-only names it creates: `UIMotionScale`, `UIMotionSlide`, `UIMotionRotation`, `UIMotionIconSlot`, and the audit attributes `UIMotionBound`, `UIMotionSlideRefused` and `UIMotionOwned`. Code-only → source sync, no RBXM.
- **Every button answers a press and a hover, through four tiers (ADR 0011 decision 2 and its 2026-09-15/16 addenda, branch `ui-motion`).** A runtime audit of THE BASIC TEST (attribute `UIMotionBound`, written by every bind) found that of 483 kit `GuiButton`s only 77 moved: 120 were bound but dead — nothing on them was safe to scale, so `bindPress`/`bindHover` returned in silence — and the rest were never bound. Every bind now paints something, chosen by what the button can move without shifting a sibling, strongest first. (1) **Button scale**, where the button is a centred element outside any layout and any `CanvasGroup`. (2) **Icon lift**: a button that paints an icon — a visible `ImageLabel`, or an *icon chip*, a styled badge whose own `Image` is empty and whose art sits in a nested `ImageLabel`, which is how every top bar row, the playlist covers and the cinematic dock rows are built — lifts that icon to 1.08× on hover and squashes it to 0.92× on press. Where the icon's parent could reflow, the icon is moved once into a `UIMotionIconSlot` that copies the icon's own `Size` (and takes its `UIAspectRatioConstraint`), so the layout footprint never changes while the icon grows inside it; a clipping ancestor refuses only when it is tight around the icon (under 1.5× its box). (3) **Text lift**: a fixed-size button whose only visible child is one label centred by the button's own layout scales that label by the same amounts; an auto-sized label is frozen at its rest size for the gesture, because a `UIScale` on an `AutomaticSize` element corrupts its own measurement. (4) **Fallback**: press insets the button's own `UIPadding` 2–6 px (one padding per instance, internal, so it is legal under a rasterized group and never moves a sibling), or, where an inset would move nothing — a both-axes-centred layout, a childless or `AutomaticSize` button — a 15% brightness dip; hover is brightness only. The old hover, `TopMenuController` tinting each row's white `BackgroundTransparency`, is gone. Every bind releases its own connections (including the global `UserInputService.InputEnded`) when the button leaves the tree, and a scale tween borrows an existing `UIScale` (`MobileScaleService`, the dock magnifier) relative to its rest value instead of adding a second one Roblox ignores. Newly bound: topbar menu rows (including the Community row with no invite configured), avatar context, Admin v3 tab/close (every `CloseModalButton` in `Header` and in the v2-era `TabSwitcher` now closes the panel — only the first one found used to be wired — and the legacy `GiveTitleTabButton` selects the text tab instead of nothing), Admin Hub sheet footer, music soundboard pads / effect toggles / Add sets / Shuffle / vote modal / row containers (the press-only music binds gained hover), the dance topbar pill and the live v2 wrapper's leftovers, cinematic dock row icons, gift player cards, all six Robux donation tiles (only their inner label was bound, and it was dead), backpack cells (a guard had it backwards), freecam touch controls, settings toggle rows and option chips, command-library row icons; `ListPool` now parents a row before `createRow` runs, so layout safety is judged on the real ancestry. `UIMotionBound` reads `true` > `"icon"` > `"text"` > `"fallback"` > `"no-target"` (an invisible hit area). Live on THE BASIC TEST after the last pass: 0 dead binds, 86 scale / 67 icon / 106 fallback, 28 slots, all 18 top bar rows (9 desktop + 9 phone) on the icon tier; 8 visible buttons stay unbound by design (six in the Admin Hub, not built when `Features.AdminHub` is off; the dance pill's outer wrapper, whose inner one squashes; `SignGui`'s one button). A real pointer on the Gift row took its icon 38 → 41 px with the row height, the row width and the sibling label all unmoved. Code-only → source sync, no RBXM.
- **Request From ID plays a song once (Music v3, branch `music-v3`).** Pasting a Roblox audio asset ID in the music panel now queues that song for one play; it is never written to the library, which is edited only in the customer area (ADR 0010). Open to every player by default through the new buyer switch `ClubKitConfig.Music.PlayOnceRequest` (`"everyone"` / `"control"` / `"off"`; schema + template, fill-forward). Players without music control may have one such song waiting and request three every ten minutes (`Config.Music.PLAY_ONCE_*`); DJs and admins are exempt. The asset must be a Roblox audio, checked with `GetProductInfoAsync`. Rules live in the pure `Shared/Domain/MusicPlayOncePolicy` (lune spec 47/47). The old path, which created a library track for managers only, is gone, and with it a wrong audio type check (`AssetTypeId` 70 instead of 3) that refused every real audio whenever the product lookup succeeded.
- **Profile likes reset every day.** A player could like someone exactly once, ever: the store held one state per (target, giver) — `1` liked, `0` unliked — so the button became an Unlike and the number never moved again. `ClubKitConfig.AvatarContext.DailyLikeReset` (default **true**) makes a like a **daily** act instead: one per person per target per **WIB day**, each one worth **+1** to that target's lifetime total, and not revocable — once spent, the button reads "Liked today" until midnight rather than offering an Unlike that would take the count back down. The day boundary is `StreakDomain.toDayNumber`, the same one the daily streak and the daily donation window already use, so a venue does not end up with two definitions of "today". **No DataStore key change and no migration:** the entry stays a single number, and the WIB day number it now stores (~20,700) can never collide with the legacy `0`/`1`, so old and new entries coexist in the same shard. A standing like from before the change is read as "liked on a day nobody recorded" — its holder may like again today, which is the kind failure; reading it as "already liked today" would have locked every existing liker out for a day that never happened. Totals are untouched by the switch in either direction, and turning the flag back off restores the old toggle *including* on entries written while it was on. One structural fix came with it: a target's total is rebuilt from its shards by `reconcileSummary`, which summed each shard's count of standing likes — correct only while one person can contribute at most 1. Shards now carry their own running `likeTotal`, and a shard written before this change falls back to the count that *was* its total, so a reconcile can never zero a venue's likes. The "X liked your profile" notification and the flying hearts now also fire on a repeat daily like (`transition = "daily_like"`), but still not on an unlike/relike — that would have made the old toggle a way to spam someone's notifications. New pure `Shared/Domain/AvatarLikePolicy` owns the whole rule (`classify` / `hasActiveLike` / `likedOnDay` / `viewerHasLiked` / `evaluate` / `resolveShardTotal`), TDD'd red-first: `.tmp/avatar-like-daily-spec.luau` is **101/101 under lune**, including full parity assertions for the flag-off path. Code-only → source sync, no RBXM.
- **Music library from the web, opt-in: `Features.MusicWebLibrary` (ADR 0010, stage B of Music Player v3).** Default **false** — nothing changes for a venue that does not switch it on. When on, the game boots from its `MusicLibrary_v1` DataStore copy (so music starts even with the VPS down), then fetches `GET {Donation.ApiUrl}/v3/music/library` with the game secret it already uses for the licence check, and polls every 60 s with `If-None-Match` so an unchanged library costs a 304. Failures back off 60 → 120 → 240 → 480 → 600 s and are logged once per reason per minute. **Only a well-formed 200 replaces the library:** a licence 403, an unconfigured route (503), a VPS outage, a malformed body, and an empty web library next to a non-empty cache all keep what is playing. An applied snapshot replaces the in-memory library outright (the web is the only writer), overwrites the DataStore cache without the usual revision merge (otherwise web deletions would live on in the cache), drops removed tracks from the queue and auto buffer, and **carries the song on air until it ends** — the session advances the moment its current track is missing from the repository, so an owner editing the dashboard mid-song would otherwise cut it. Web mode hides the Manage tab, skips the catalog seed and the DataStore poll, stops persisting the request-history playlist, and wins over `MusicReadOnlyLibrary` if both are on. New pure `Shared/Domain/MusicWebLibraryPolicy` (`interpret` / `nextPollSeconds`) validates entries with `MusicDomain` itself, TDD'd red-first: `.tmp/music-web-library-policy-spec.luau` **53/53 under lune**; new `Server/Services/MusicLibraryProvider`; `MusicRepository.applyWebSnapshot` / `writeWebCache`. Verified in Studio against a fixture (apply, same-revision, 404, nothing listening — all four behave as above) and a flag-off playtest (legacy boot unchanged, zero errors). **Known gap in web mode:** request-by-asset-ID is unavailable, because it creates a library track and the in-game manage privilege is off. Code-only → source sync, no RBXM; the VPS route it calls ships separately.
- **Long sets: a track can hold 26 parts, and the web library tells the client how long each one is (owner, 2026-09-22; ADR 0010 addendum).** Owner: *"tambahin juga biar support sampai 3 jam, 20 mins kek kependekan, sedangkan mixtape gitu2 bisa panjang apalagi konteks map dugem"*. Three hours in seven-minute parts is 26, so `Config.Music.MAX_TRACK_PARTS` and the literal in `MusicDomain.validateTrack` go from 9 to 26 (brm-api's `MAX_TRACK_PARTS` is the same number). Before this, the web pull **dropped a 10+ part track whole**, and brm-api cut every sync at 9 parts. A track now carries optional `partDurations` — raw seconds per asset, one per part, sent by brm-api from its ffprobe of each part. `MusicDomain.readPartDurations` keeps the list only when it has one positive number per part; a bad list is dropped, never a reason to refuse the track. `MusicRepository` carries it on every read path and into the `MusicLibrary_v1` cache. On the client, `_primeTrackPartDurations` uses it instead of creating one probe `Sound` per part (26 loads at once for a 3-hour set), so a late joiner lands in the right part without loading parts 1…n to measure them; a part's real `TimeLength` still replaces its entry when it loads. Prefetch is a window now, `Config.Music.PREFETCH_PARTS_AHEAD = 2` (kit-internal): the part on air plus the next two, where it used to schedule every remaining part at the top priority on each part change. Tracks of three parts or fewer schedule exactly what they did before. Found on the way: `_primeTrackPartDurations` ran before `_setBaseSpeed`, so a part length taken from the asset cache was converted with the **previous** track's speed; it now runs after. Spec `.tmp/music-long-set-spec.luau` (18/18, red first); `.tmp/music-web-library-policy-spec.luau`'s invalid-parts fixture moved from 10 to 27 parts.
- **Web music library imports the venue's in-game library first (ADR 0010 import addendum).** Found by the first live test on THE BASIC TEST: brm-api held all 11 tracks, but 7 were marked revoked and 5 still pointed at the asset they used before being re-pointed in-game, so the web view dropped tracks that still play and the kit overwrote its cache with the short list (recovered from DataStore version history; flag turned back off). Now the pull response carries `import_required` until the VPS has received the venue's DataStore library once; while it does, `MusicWebLibraryPolicy` answers `import` and nothing is applied, however complete the web side looks. The provider then POSTs `MusicRepository.exportForWebImport()` (playlists and tracks with ids, tombstones included so an in-game delete is not revived) to `{ApiUrl}/v3/music/library/import`, treats `200` and `409 already_imported` as done, clears its revision and pulls again — once, so a VPS that keeps asking cannot make it loop. **It never imports an unread cache:** if the DataStore library failed to load it retries the load and skips the import, because an empty import would mark the venue imported and let the next snapshot erase its library. Also fixed: the carried song on air was written into the cache with an empty `playlistId`; `writeWebCache(excludeTrackIds)` now leaves it out. Spec `.tmp/music-web-library-policy-spec.luau` **60/60** (7 new import cases, red first).

### Changed
- **Production hardening P3 — DataStore write + HTTP discipline at 200 players (plan `docs/plans/production-hardening-2026-09-24.md` §2 A/B/C, ADR 0016). Engine only; no new DataStore keys; one additive buyer key (`Telemetry.Enabled`). Every part has an engine switch back to the pre-P3 behaviour.**
  - **XP is written on a 90 s slot per player, never twice in 7 s (`Config.PlayerDocWriter`, rollback `WRITE_POLICY = "legacy"`).** New `Server/Persistence/PlayerDocWriter` + pure `Shared/Domain/FlushPolicy`: an XP-only change to `Overhead_v1` waits for the player's own phase (`userId % 90`) in every 90 s (owner decision K1: the crash window); any other change (level-up, title, membership, role…) goes after a 3 s debounce; no document is written twice within 7 s on any path (tick, leave, restart, shutdown, and direct writers Settings / VenueQuestProgress through `PlayerDocWriter.guard`). A 1 Hz scheduler writes at most `ceil(dirty/60)+2` per tick (≈ 2.2 writes/s at 200 players, was up to ~20). The 60 s autosave no longer writes session documents; BindToClose and the early-restart flush write every dirty document Overhead-first, ≤ 12 per second within 22 s (the old sequential `flushAll` could not finish 200 documents in 25 s). A failed write is retried by the scheduler at 7/14/28/56/60 s.
  - **Venue quest progress is written in four staggered groups and stays bounded (`PlayerDocWriter.VENUE_*`).** Instead of every player in one tick every 120 s, one `userId % 4` group per 30 s tick, spread over the tick. Documents are pruned inside the save transform: quest entries 30 days past their due day (entries now remember `dueDay`, additive) and `seenPosts` capped at 50; entries of unknown age are kept, so a server with a stale board never drops progress.
  - **Cross-server invalidation (`Config.InvalidateBus`, rollback `V2 = false`).** 5 s coalescing, messages split at ≤ 60 ids / ≤ 1 KB (`Shared/Domain/InvalidateBatch`, the legacy `userId` field kept for older servers), one requeue after a failed publish, a local 12/min per-topic budget instead of the MemoryStore lease on every publish. XP-only Overhead writes are no longer published (`SKIP_XP_ONLY_PUBLISH`).
  - **Leaderboard verify reads cached (`Config.VerifyCache`).** Streak/couple verification reads an online player's live session and an LRU (256 × 600 s) for offline documents — the old 60 s cache missed on every 120 s refresh; `ProgressLeaderboardRepository:forget` now runs on leave. Likes-board metadata reads go through an LRU (500 × 30 min).
  - **MemoryStore leaderboard cache v2 (`Config.LeaderboardCacheV2`, rollback `ENABLED = false`).** One compact item per board in the new map `ClubKitLeaderboardCache_v2` — ids and totals only, ≤ 4 KB (`Shared/Domain/LeaderboardCacheCodec`), one item serves every limit — instead of full rows with names and thumbnails per limit (60–100 KB). Names come from the server's metadata cache. The old map expires on its 60 s TTL.
  - **Global documents written once per revision (`Config.GlobalDocWriter`, rollback `ENABLED = false`).** The event-board cache and the web music cache (Playlists/Tracks) go through `Server/Persistence/GlobalDocWriter`: an `UpdateAsync` that cancels when the key's DataStore metadata already holds this revision (or one fetched later by another server), a random 0–20 s start, retries, and a 1 MB size guard (`doc_oversize`). The event-board cache now stores the sanitized board in the VPS's raw shape (`EventBoardDomain.serializeBoard`). In web mode a reported track duration stays in memory (overlay) instead of rewriting the whole `Tracks` value. The music import is refused above 900 KB (`import_oversize`); the game keeps playing from its cache.
  - **One HTTP entry for the VPS: `Server/Net/BackendClient` (`Config.BackendClient`, rollback `ENABLED = false`).** Secrets travel only in `Authorization: Bearer` — no call site puts `?secret=` in a URL any more (groups, social get/push, community were the last). One per-server token bucket (400/min, burst 40; critical may drain it, normal stops at 25 %, bulk at 50 % and waits instead of being dropped), a VPS 429 `retry_after` pauses every priority, a circuit breaker per endpoint group (5 straight failures or ≥ 50 % in 30 s; 30/60/120 s), `Timeout` always whole seconds. Every request is still counted by `BudgetMeter`. The Roblox group proxy call (`proxy:groups_json`) takes bulk tokens too.
  - **Join lookups batched (`BackendClient.LOOKUP_*`).** The background cash fetches (join-time cash, rank resolution) and the join's connections warm of everyone joining within 3 s share one `GET {ApiUrl}/v2/players/lookup` (≤ 50 ids, live since P2) through `Server/Net/PlayerLookupBatcher`; a 404/405 (older VPS) turns it off for 30 min and the per-user routes are used as before. Interactive lookups (donor panel, donation processing, a profile opened, the group rank the first overhead payload waits for) keep their direct route, so nothing a player waits on gains the 3 s window.
  - **Group rank: 3 wasted requests per join fixed (found in the 2026-09-24 playtest).** A venue whose VPS game has no group got HTTP 403 `groups endpoint not enabled for this game` three times per join (the payload builds of one join each asked). That answer (or `groups_disabled` / `group_id_required` from the lookup) is now remembered for the server for 30 min (`GROUPS_DISABLED_TTL_SEC`) and the rank comes straight from GroupService; concurrent asks for one player share one request; a failure is not repeated for 30 s.
  - **Social proof asks once.** Up to 9 GETs per join (3 attempts × 3 warm retries) → one lookup; a player with no connections count yet is not asked again for 300 s (`SOCIAL_NEGATIVE_TTL_SEC`).
  - **Commands piggyback on notifications (`BackendClient.COMMANDS_PIGGYBACK`).** When `/v2/notifications` answers `has_commands: false` the separate `/v2/commands` GET is skipped (safety poll every 60 s); an older VPS without the field is polled every cycle as before.
  - **ReliabilityV2 batched, and on by default (owner decision K7).** Client acks and on-screen displays queue (`Shared/Domain/DeliveryReportQueue`): deduped by donation + player, a display only for a donation this server fired, ≤ 4 reports per player per 10 s, one POST per kind every 3 s or 100 entries (was one POST per player per donation — ~400 per donation at 200 players). Flushed on shutdown. `Config.Donation.RELIABILITY_V2_ENABLED` and the schema default for `ClubKitConfig.Donation.ReliabilityV2` are now `true`; a buyer file that says `false` keeps it off.
  - **Budget telemetry reaches the VPS (ADR 0007 phase B).** `Server/Net/BudgetTelemetry` folds the 60 s BudgetMeter windows into a 15-minute aggregate (sums, lowest budgets, per-minute peaks, per-endpoint HTTP stats — never a player id) and posts it to the live `POST {ApiUrl}/v3/telemetry` as kind `budget`, bulk priority. New buyer key **`ClubKitConfig.Telemetry.Enabled`** (default `true`, schema + template, filled forward) turns it off.
- **Production hardening P4 — performance at 200 players in one server (plan §2 H, ADR 0017, ADR 0008 addendum; engine only, no GUI/RBXM change, no DataStore key, no buyer-config key).** Every item has a switch in the new P4 block after `Config.NetworkPerf`; setting it to the documented legacy value restores the pre-P4 behaviour.
  - **Overhead baselines are per subject, not per pair (H2).** The server kept a deep copy of the last overhead payload for every viewer–subject pair (up to ~40,000 copies, ~160 MB of Lua heap in a dense lune run) and scanned every key on each leave. `DeltaCompressor.createVersioned` keeps one baseline per subject and one version number per pair; viewers one change behind share one delta table; a leave is O(k). `Config.NetworkPerf.OVERHEAD_BASELINE = "versions"` (legacy `"legacy"`).
  - **XP ticks go to the owner only (H1, broadcast side).** `xp`, `xpProgress` and `xpNeeded` reach other viewers in full snapshots or riding along another changed field; an XP-only change no longer sends a delta to everyone nearby. `Config.Overhead.PERF_XP_OWNER_ONLY` (legacy `false`). The XP write cadence is P3's.
  - **One `FireClient` per viewer per frame (H7).** `OverheadUpdate` and `ChatTagSync` pack each viewer's messages of one frame into `{ kind = "pack", items }` (a lone message stays unwrapped; broadcasts stay ordering barriers); every kit listener unpacks. `list` messages are keyed per viewer instead of sorting and joining every recipient id. `Config.NetworkPerf.PACK_PER_VIEWER` (legacy `false`).
  - **Proximity recompute is incremental (H3).** Subjects are re-evaluated in 4 staggered groups (each once a second), on an 8-stud grid with squared distances, at most the **30 nearest** viewers per subject (a newcomer displaces the farthest only when 8 studs nearer), at most 20 new subscriptions per viewer per 0.5 s, and a spawn recomputes that player's row only. `Config.NetworkPerf.PROXIMITY_MODE = "incremental"` (legacy `"legacy"`). The `sync:` channel shares the set; `SyncService` only checks that a leader has someone in range, so dance sync is unaffected.
  - **MovementGuard samples a slice per tick above 60 players (H4, owner decision 9).** Each player every 2 s, a stable `userId` slice per 0.5 s tick, with a position-only lead sample so the noclip chord stays 0.5 s long and stamped air jumps feed the infinite-jump window; one shared `RaycastParams` replaces a new one + exclude list per sample. `Config.MovementGuard.PERF_SPREAD_ABOVE_PLAYERS = 60` (legacy `0`), `PERF_SHARED_RAYCAST_PARAMS` (legacy `false`).
  - **Join path (H8, H9).** The join check uses an O(1) membership test; the join batch skips subjects whose full payload already reached the joiner through Snapshot-on-enter; the +5 s / +10 s rebuilds run only when the join payload's rank or data was unresolved (`PERF_SETTLE_REBUILD_ONLY_UNRESOLVED`); a client roster catch-up request inside 10 s of the join roster is ignored (`PERF_ROSTER_REQUEST_DEDUPE_SEC`); the joiner's chat-tag roster goes out 50 entries per frame (`PERF_CHAT_TAG_BATCH_CHUNK`).
  - **Client: at most 40 overheads enabled, Far = 90 studs (H13).** Overhead wrappers are CanvasGroups (one texture each); the client keeps the 40 nearest other overheads enabled (4-stud swap margin, own overhead always on) and a culled one skips its layout work; "Far" is 90 studs instead of unlimited; the title gradient loop skips disabled or out-of-range titles. `Config.Overhead.PERF_MAX_ENABLED_OVERHEADS`, `PERF_FAR_MAX_DISTANCE`, `PERF_GRADIENT_CULL`.
  - **Client: avatar prewarm bounded (H12).** No model build for every joiner on every client, a respawn reloads only a pooled model, the background queue holds 10 (clicks go first and are never dropped), no proximity scan above 60 players. `Config.NetworkPerf.PREWARM_*`.
  - **Client: admin rosters and character effects (H15, H16).** A closed Admin Panel v3 no longer rebuilds its player list on every join/leave, open lists rebuild at most once a second; Settings keeps each character's particle/trail/beam list, so a graphics toggle and every settings echo walk that list instead of every descendant of every character. `ADMIN_LIST_DEBOUNCE_SEC`, `SETTINGS_EFFECT_CACHE`.
  - `InterestManager` no longer logs (and counts the channel) on every subscribe.
- **The music now plays four times louder, and 100% on the Settings slider means four times louder for everybody (owner, 2026-09-16).** Owner: *"aku mau tetap dipetakan jadi dari 0-1 jadi 0-4, soalnya emang yang sekarang terlalu kecil."* The Settings **"Music Volume" slider is untouched** — still 0–100%, still stored as 0–100, no UI change of any kind. What changed is what a percentage buys: the kit used to send `percent / 100` straight to `Sound.Volume`, so 100% was Roblox's unity gain of 1.0 and the club could never be louder than that. The percentage is now multiplied by a new buyer key, **`ClubKitConfig.Music.MaxVolume`, default `4`** — so 100% = `Sound.Volume` 4.0, 50% = 2.0, 25% = 1.0, and 0 is still silence. **This is a venue-level change, not just a wider choice:** everyone who already saved a setting comes back four times louder without touching anything, which is precisely what was asked for. Nothing in the saved record moves — `SettingsDomain` still validates `musicVolume` at 0–100, the DataStore key is unchanged, and the one-shot `_musicVolBase` migration that lifts an untouched old `50` to `100` is untouched — so a player's stored number keeps its meaning and an older client reading a newer record behaves exactly as before. The scale lives in one place, the `SettingsMusicVolume` player attribute, which now carries an already-scaled `Sound.Volume`; every `Sound.Volume` write in `MusicPlayerController` (initial play, fade-in target, fade-completion re-assert, settings sync, panel callback) clamps to `0, MaxVolume` instead of `0, 1`, and the music store's pre-settings default matches, so the first track on join does not start quiet and jump. **Roblox accepts `Sound.Volume` up to 10 and everything above 1.0 is amplification, which clips:** a loud master under a boosted DJ equalizer band will distort audibly, so `MaxVolume` is documented in the buyer config as the dial to bring down — `1` restores exactly the old loudness, and a mistyped value is clamped to 0–10 rather than throwing. Code-only → source sync, no RBXM.
- **The UI is meant to be enjoyed, not merely quick (ADR 0011 addendum, branch `ui-motion`).** Owner: *"overall animasi ui nya dibikin smooth delightfull ajaa, gausah se snappy itu gapapa, jadi animasinya dibuat untuk dinikmati."* The kit's motion vocabulary inherited its timings from the v3 music panel, where a fast panel was a responsive panel; spread across twenty-five panels they read as efficient rather than pleasant. This pass retunes **only durations and easing curves** — no new motion, no API change, nothing about which element moves or how far. Panels now arrive over 0.32 s of travel into a 0.20 s settle (was 0.18 + 0.16), dialogs over 0.24 + 0.15 (was 0.13 + 0.12), the centre panel over 0.40 s (was 0.28), the sidebar 0.38 (was 0.28) with its spring softened 4.8 → 3.8, toasts 0.30 (was 0.22), tab slides 0.38 (was 0.28), and rows cascade at 0.055 s apart with a 0.36 s fade (was 0.03 / 0.28), and `pop` runs 0.16 s Sine Out (was 0.12 Quad; peak 1.25 unchanged). Quart gave way to Quint on every travelling half, because at these lengths Quart's tail reads as drift where Quint puts the distance behind it early and spends the rest settling. **Every close was softened by its curve rather than by its length, and every open/close pair keeps open comfortably longer than close** (0.52/0.22 panel, 0.39/0.17 dialog, 0.40/0.24 centre, 0.38/0.26 sidebar, 0.30/0.22 toast) — a close that luxuriates is a door that will not shut. **The press-down is a deliberate exception and stays at 0.08 s:** the delay between a finger landing and the button reacting is read as input lag, not as elegance, and no grace afterwards buys it back. Everything after the contact is where the delight went — the release grew to 0.28 s and now springs back Back-Out (0.26 s Back-Out for `PressFeedback`), a hover lifts over 0.22 s of Sine and drops over 0.18. Overshoot lands only on releases, and only where it provably cannot spill: a press returns from a shallow squash, so Back-Out peaks near 1.002–1.010 (under a tenth of a pixel on a 16 px list icon), the fallback's springs internal `UIPadding`, and the icon slot already holds the footprint of anything a clipper could cut — hover gets no bounce at all, because a cursor rests there. A 20-row list still settles inside a second: the existing 12-row stagger cap bounds it at 0.965 s, and the eight panels that tuned their own step to their own list density keep it. **`Config.UIMotion.MOTION_SCALE` is untouched at `1`** and every new duration still flows through it, so a venue that set 0.8 gets a proportionally brisker kit and one that set 1.4 a slower one — the feel is in the tokens, not in the knob. Reduced motion was re-walked branch by branch (a longer duration makes a missed one more obviously wrong) and still snaps to the same final state everywhere. Code-only → source sync, no RBXM.
- **Per-instance UI state is strong and reclaimed on `Destroying` — one mechanism, `Shared/Utils/InstanceState` (ADR 0011 addendum 2026-09-17, kit-wide sweep; branch `ui-motion`).** Roblox drops a weak-table entry keyed by an Instance as soon as no Lua value references it, while the Instance is still alive and parented — so `__mode = "k"` was never a lifetime mechanism, and the kit had 33 such tables. Every one was classified. State that must be there while the Instance lives now goes through `InstanceState.new(init)`, a store with `get` (never creates), `of` (creates on first use and connects exactly one `Destroying:Once` per Instance) and `drop` (explicit, idempotent); only `Destroying` reclaims, never `AncestryChanged`, so detached pooled rows keep their records. Migrated to it, behaviour identical: `UIMotion` (its `MotionState` record; `markBound` is now public, so `PressFeedback` writes the `UIMotionBound` audit attribute through the same precedence — one writer), `AnimationHelper` (tweens / token / resting position / group alpha in one record — a lost entry orphaned an in-flight present/dismiss), `DonationLeaderboardController` (21 weak tables → one `Marks` record per board element: a lost "original" was re-captured mid-pulse, a lost generation let a superseded counter keep writing, a lost guard started a second podium loop), `WorkspaceLeaderboardRenderer` (loading-text generation + fade baseline; runs on the server too, which is why the store lives in `Shared/`), `OverheadUI` (role-stops / role-chip template gradients — a lost template left the previous role's colours on a reused row), `UISoundHelper` (bind-once guard + connections — a pooled row re-parented into `PlayerGui` was bound twice: two click sounds), `CoupleController` (`motionBound`), `ImageSwap` (swap generation — a superseded probe could land a stale image on a retargeted row), `Main.client` (`topbarOutlineIdByWidget`, via `ClientModuleBag.InstanceState` — nothing writes it today, so its deletion is in review; `UPGRADE_PROGRESS.md` § F). The eight `_fadeBases` maps that feed `UIMotion.captureBases`/`fadeIn`/`stagger` are now plain **strong** tables owned by their panel (`AdminHubUI`, `AdminPanelV3UI`, `CustomTitleUI`, `DonationSystemUI`, `MenuShellUI`, `ProfileTabBinder`, `StickerController`, `CoupleController`), matching `GiftUI`/`AdminPanelUI`: with weak keys a label's entry could vanish while it sat at transparency 1 waiting for its stagger delay, and the next render's `captureBases` then recorded 1 as its design — invisible text for good. Entries for destroyed clones now live until their panel is destroyed (bytes per row, bounded). Four sites stay weak on purpose, each carrying a one-line "why a lost entry is harmless" comment: `Music/Visuals.coverKeys`, `Music/LibraryView.shownBackground`, `CoupleController.cardTargetTransparency`, `AnimatorUtils` (×3). Also fixed on the way: `UIMotion.scaleTo`'s settling `Completed` handler named its parameter `state`, shadowing the module's record table, so `state[scale]` indexed the `PlaybackState` EnumItem — the release of a borrowed capture and the thaw of a frozen label on the completed path never ran in the engine (the lune Enum stub indexed to nil, which is why the harness stayed green). Harnesses: `.tmp/uimotion-scale-rest-spec.luau` 14/14 (loads the real `InstanceState` from disk now), new `.tmp/instance-state-spec.luau` 8/8. Code-only → source sync, no RBXM.
- **Live music control is its own privilege, `musicControl` (ADR 0010, stage A of Music Player v3).** `musicManage` used to gate both editing the library and running the room — DJ mode, effects, playback speed, soundboard, admin skip, the DJ-mode request/vote bypass and opening private playlists. Those now sit behind `musicControl`; `musicManage` keeps the Manage tab, track/playlist edits and request-by-asset-ID. **No buyer action and no silent loss of power:** a config that does not mention `musicControl` inherits the role's *effective* `musicManage` — resolved after role-level `privileges` overrides are merged, so a role that overrides only `musicManage = true` still runs the decks — in `RoleCategoryBuilder.build` at boot, not by patching the buyer's file (ADR 0001). An explicit `musicControl` on a category or a role wins over the inference, so a venue can now have library editors who cannot skip and DJs who cannot edit. The state sync and `get_state` carry a new `isControlAllowed`; the client's DJ tab and DJ-mode gating read it, the Manage tab still reads `isManageAllowed`. **One deliberate behaviour change:** in a read-only library (`Features.MusicReadOnlyLibrary = true`) the shared gate used to switch the DJ tab and admin skip off for everyone; live control now stays available to its holders, because those are runtime actions, not library edits. Template `ClubKitConfig` and schema defaults write the key explicitly (Leadership and Content `true`, Moderation `false`). Pure logic TDD'd red-first: `.tmp/music-control-privilege-spec.luau` **20/20 under lune**, including a frozen-buyer-table case (the builder must never write into config that `ConfigBootstrap` may have frozen). Code-only → source sync, no RBXM.

- **The web library is the only music library (Music v3, branch `music-v3`; ADR 0010 addendum 2026-09-14).** Every venue now boots from its `MusicLibrary_v1` DataStore copy and then takes the library from the customer area. There is no catalog seed, no DataStore poll, and no in-game editing. **Retired buyer keys:** `Features.MusicCatalogSeed`, `Features.MusicReadOnlyLibrary` and `Features.MusicWebLibrary`. They are no longer read, filled forward or offered in the plugin. A buyer file that still has them is left untouched (ADR 0001), and the boot log names them once ("safe to delete"). They are listed in the new `ClubKitConfigSchema.RETIRED_KEYS`, and `findRetired` reports which ones a buyer file still has (lune spec 23/23). `MusicWebLibrary` retires rather than defaulting to `true` because the 2.13 config patch writes `false` into buyer files, so a new default would never reach them. `MusicCatalogSeeder` is deleted; the buyer's `MusicCatalog.luau` is left in place but no longer read, and anything it seeded is already in the library the first-boot import sends to the web. Code-only → source sync.
- **In-game music Manage removed (Music v3, branch `music-v3`; ADR 0010).** The library is edited only in the customer area. Removed:
  - **Server:** `MusicService.managePlaylist` / `manageTrack`, with their text filter and rate limiter; the `MusicManagePlaylist` / `MusicManageTrack` remotes; the request-history playlist; `isManageAllowed` in the state sync and `get_state`.
  - **Client:** the Manage handlers, forms and store fields.
  - **Config and repository:** `Config.Music` `MANAGE_ALLOWED_*`, `SPECIAL_PLAYLIST_REQUEST_HISTORY_*` and the `manage` tab names; `MusicRepository`'s read-only write guard.

  The v2 panel binder (`MusicPlayerUIBinder`, `MusicPlayerUIBinderPart2`, `MusicPlayerGuiRefs`) is no longer referenced by any module, since the v3 `PanelShell` replaced it. The `musicManage` role privilege stays in role configs, because it still seeds `musicControl` for a config that never mentions it. Code-only → source sync.
- **The v3 music panel is `06-MusicPlayerGUI` (Music v3, branch `music-v3`).** `Config.Music.GUI_NAME` is back to `06-MusicPlayerGUI`, which is now the v3 ScreenGui; the v2 panel it replaces is kept only as a rollback RBXM in `docs/releases/3.0.0/rollback/`. The phone scale `Config.MobileScale.MUSIC_GUI` drops from 0.62 to 0.56 because the v3 panel is 1000 px wide instead of 900. The `get_state` response now carries `isPlayOnceAllowed` like the state sync does; without it, any refresh from the server hid the Request From ID box. The ScreenGui ships `Enabled = false` and the panel turns it on (with the panel closed) once it has bound, so a place whose music controller never starts shows nothing. **Buyers must install the new ScreenGui from the RBXM (GUI change, not source sync).**
- **The icon tier honours ADR 0005 under `CanvasGroup`s (branch `ui-motion`).** `UIMotion.iconTargetOf` now refuses an icon with a `CanvasGroup` ancestor, as `textTargetOf` already did — scaling a descendant re-rasterises the whole group on every hover. Those buttons fall to the padding squash / brightness fallback, which is legal under a group. **This is a coverage reduction:** the cinematic dock's favourite `Badge` (movement and camera rows), the dance panel's row favourite icons, the command library's row icons under its wrapper groups, and any buyer icon under a `CanvasGroup` no longer lift; they squash their padding or dip their brightness instead. Code-only → source sync, no RBXM.

### Fixed
- **Production hardening P1 — data correctness at 200 players (plan `docs/plans/production-hardening-2026-09-24.md`, engine only, no new DataStore keys, no buyer-config change).**
  - **Gift intents are really consumed.** `GiftPendingRepository:consume` returned `nil` from its `UpdateAsync` transform, which *cancels* the write, so the `ShopGiftPending_v1` entry was never removed and a re-delivered receipt could grant again within the persist timeout. It now writes a tombstone (`{ state = "consumed", toUserId = 0, consumedToUserId, storedAt, consumedAt }`, additive; older kits read `toUserId = 0` as "no gift") and a second consume returns nothing.
  - **Unsaved Overhead/XP is no longer dropped.** A cross-server invalidate (`OverheadInvalidate` / `SettingsInvalidate`) cleared the player's session document even when it held unsaved changes; `PlayerSessionStore` now keeps a dirty session (marked *stale*) and its next flush **replays the session's unsaved mutators onto the stored document** inside the `UpdateAsync` transform (also used when the stored `_version` is newer, instead of the old `version_conflict` drop). A leave flush that fails no longer drops the document: it is retried at 2/4/8/16/30 s (`Config.Persistence.LEAVE_FLUSH_RETRY_DELAYS`) and stays for autosave / BindToClose until a write succeeds (cap `MAX_DEPARTED_SESSIONS` = 400). `applyMutator` no longer marks a dirty session clean when a change reverts to the last written value, and `hydrate` never overwrites unsaved changes.
  - **Venue quest progress is saved in the shutdown flush phase and on leave retries.** It was flushed only in `onDestroy`, after BindToClose's 25 s wait, and a failed leave save was lost; `EventBoardController:flushAll` now runs next to the other repo flushes in BindToClose, a leaver's progress is kept and retried until written (a rejoin gets that copy back), and the progress document loads through the shared ProfileLoader (kind `venue_quest`) instead of a direct `GetAsync` per joiner.
  - **Join loads are no longer abandoned under budget pressure.** ProfileLoader requeues **every** kind refused with `budget_low` / `budget_exhausted` after 10/20/40/80 s (± 20 %, never below the negative-cache TTL), then reports `load_gave_up` (only `overhead` was requeued, by Main); it refills a slot as soon as one frees (sliding window; `Config.ProfileLoader.SLIDING_WINDOW = false` restores fixed batches) and no longer leaves a `0` per departed player in its pending table. Kill switch `REQUEUE_ALL_ON_BUDGET`.
  - **DataStoreScheduler takes the key mutex before an in-flight slot**, so writes queued on one hot key no longer block every other key (head-of-line blocking); a refusal releases the mutex.
  - **Two overhead deltas for the same viewer in one frame no longer lose the first.** NetworkManager's per-frame coalescing kept only the last entry per key while the server's per-pair baseline had already advanced, so the client could miss fields for good (e.g. a level-up followed by an XP tick). Delta kinds listed in `Config.Network.COALESCE_MERGE_FIELDS` (`overhead_delta`) are now merged field by field, later wins; everything else stays last-wins. Rules in the new `Shared/Utils/NetworkCoalesce`.
  - **Non-donors no longer cost a cash request every ~45 s.** A confirmed zero from `players/:id/cash` is cached for `Config.Donation.DONOR_ZERO_CACHE_TTL` = 300 s (was 45 s), and the overhead cash-rank chip remembers "no rank" for a confirmed non-donor as long (was 5 s); both are cleared when a donation or cash sync names the player (~260 → ~40 requests/min at 200 players).
  - **Per-player tables are cleared on leave or bounded** (perf audit §7): server `SettingsController.publicSyncTokenByUserId`, `RoleToolService` sync cooldown (and its per-player `CharacterAdded` connection), `SyncService.prewarmGeneration`, `OverheadController.aboutRosterEntryFingerprints`, `DonationService` donor cash caches (leaver dropped + expired sweep), client `AvatarContextController` request/friend caches, and `ProximityInterestService`'s per-player `CharacterAdded` connection (it lived in the module-lifetime cleaner). Tables that must outlive a visit are 1,000-entry LRUs (new `Shared/Utils/BoundedLru`): `DonationService` `knownDonors` / `sessionRobuxTotals` / `userInfoCache`, `AvatarLikeRepository` write-skip caches.
- **The donation giant wears the donor's 3D clothing instead of turning up naked.** Donors with layered clothing got a bare-skinned giant that still wore its hat and accessories — because **`Humanoid` scale values do not scale layered clothing, while `Model:ScaleTo` does**. Bisected on one avatar, front-on, identical framing: dressed at ×4, half gone at ×7 (shorts survive, jacket sinks into the body), naked at ×10 and above. Rigid accessories (Hat, Face, Neck, Waist, Back) scale normally, which is exactly the "hat and lollipop but no clothes" buyers photographed. The fix adds a **clothing shell**: the effect's own rig is left completely alone and keeps driving the animation, the hammer, the portal alignment and the emergence, and is hidden by the transparency pass it already had; a second model built from the donor's avatar (`CreateHumanoidModelFromDescriptionAsync`, forced to R15 so an R6 donor still pairs) is sized with `ScaleTo` and mirrors the rig's pose every `PreSimulation` — root CFrame plus each paired joint's and bone's `Transform`. Both `Motor6D` and `AnimationConstraint` are paired, because AvatarJointUpgrade has replaced the former on current rigs. Layered items are stripped from the description the invisible rig receives, since it can only break on them. New `Client/Utils/AvatarGiant`; shell size is `Config.Donation.GIANT_SCALE` (default 50, matching the rig's own Humanoid scale). Two defects in the same lines close with it: the HumanoidDescription came from a shared cache and was mutated by `× 53` on every use, compounding to `×2809` on a second donation inside the 600 s TTL (measured 47.7 → 2,528 → 133,989), and the stock `Animate` script tears a scaled model apart. Verified end to end by screenshot on **both** effects that use it (GreenHammer and Blossom): giant fully dressed, mid-swing, holding the hammer, rig invisible, shell torn down with the effect.
- **Wutwut restarts no longer drag the dance speed backwards for everyone watching.** With Wutwut on, moving the speed slider made followers stutter between speeds — reported as "the follows lag". `activeSpeeds[leader]` had **two writers**: `adjustSpeed` from the slider, and every Wutwut restart, which carried the client's `currentSpeed` snapshot on the animation-start remote and wrote it in `onAnimationStart` before replicating. The two fire on independent cadences, so whichever landed last won and the speed walked backwards. Compounding it, `replicateAnimation` captured `leaderSpeed` **before** `task.spawn`ing the per-player work, so a captured value could be applied after a newer one. A restart replays the dance that is already running, so the server's own speed is now authoritative: the restart seeds `activeSpeeds` only when nothing is recorded, no longer passes `speed` in its replicate options, and every per-player closure re-reads the live value at the moment it applies it. Measured on HIERAPOLIS over an identical monotonic 1.0 → 2.0 ramp with Wutwut firing throughout, counting backwards steps on the leader's server-side `AnimationTrack.Speed` (the value followers inherit): **before 3 and 2, control without Wutwut 0, after 0 and 0.**
- **Auto Dance no longer re-opens the dance panel it just shuffled from.** Picking an emote reveals the panel, because a manual pick comes *from* the panel and the player expects the preparing state to land on the row they clicked — but Auto Dance drives the same `SyncController:onEmoteSelected`, so every shuffle tick forced the panel back open, once every `MIN_INTERVAL`..`MAX_INTERVAL` seconds. Closing it was useless: it returned ~1.5 s later. Auto Dance now suppresses the reveal for as long as it runs (`SyncController:setOpenPanelOnSelect`) and hands it back when it stops or is destroyed; explicit open / close / toggle are untouched, so a deliberate gesture still always wins. Verified in a HIERAPOLIS playtest: before, closing the panel under Auto had it re-open at the next tick; after, 30 s with Auto on produced **0** self-opens while five dances shuffled normally, and a manual panel open + row click still behaves exactly as before.
- **A PlayerList team shared by several ranks stops flipping players to Neutral.** When a buyer puts more than one role on the same chat label they all collapse onto one Roblox `Team` — HIERAPOLIS has 21 role keys on `DPC` carrying four different `teamColor` values. A `Team` holds exactly one `TeamColor`, and `getOrCreateTeam` repainted it with the colour of whichever role was syncing, so two online ranks of the same team rewrote it back and forth. Roblox keys team membership by `TeamColor`, so every rewrite left those players with `Player.Team = nil` (Neutral on the leaderboard) until the next sync re-added them — an endless "You are now on the DPC team" in chat, reported by a buyer's players. The team's colour now comes from the **team label**, not the syncing role: `RolesDomain.buildTeamColorRoleByLabel` picks the highest-`ChatPrimaryTagPriority` role per label (ties broken on role key so a restart cannot change it) and publishes it as `Config.PlayerList.TEAM_COLOR_ROLE`, making the write idempotent. Colours on every existing team are unchanged, and places where one label maps to one role are unaffected. Rules covered by `.tmp/team-color-by-label-spec.luau` (34/34); the Neutral mechanism itself was measured in a HIERAPOLIS playtest (changing a live team's `TeamColor` drops its members to `Team = nil`).
- **Pooled list rows keep their press and hover after the first recycle (branch `ui-motion`).** `UIMotion`'s self-release tore a bind down whenever the button left the tree, but the dance panel and the command library pool their rows with `Parent = nil`, re-acquire the same instance and bind it only once — so after one Dance → Pose → Dance switch, or one command search, every recycled row was dead for the rest of the session while `UIMotionBound` still read bound. Binds and per-instance state now live as long as the instance: only `Destroying` ends them, and a detach just settles the target to rest and keeps its connections. Both binders also parent a row before its one-time bind (the rule `ListPool` already follows), so the tier is chosen against the tree the row is actually shown in. Harness `.tmp/uimotion-scale-rest-spec.luau` 18/18 (new: bind survives release and re-acquire; a row bound detached and parented later keeps its bind; `Destroying` ends the bind). Code-only → source sync, no RBXM.
- **A delayed row fade no longer leaves a detached element invisible (branch `ui-motion`).** `UIMotion.fadeIn` with a delay hides every element at once; an element pool-released during the delay — a dance row mid-cascade — was then skipped and came back blank. It is now written back to its designed transparency when the delay lands. Harness case added, red on the previous build. Code-only → source sync, no RBXM.
- **Icon flourishes keep working after a bind (branch `ui-motion`).** `spin`, `wiggle` and `pop` looked their icon up non-recursively *after* the button was bound, by which time the icon tier could have moved it into `UIMotionIconSlot` — the lookup returned nil and the flourish stopped silently. The icon is now resolved before the bind at the DJ reset, the music transport (rewind, seek, previous, next), the queue-row remove, the gift send and the dance reset-speed buttons; the donation panel's `iconOf` also looks inside the slot. Code-only → source sync, no RBXM.
- **Playlist covers no longer stay enlarged after a hover or shrunken after a press (ADR 0011 addenda 2026-09-16 and 2026-09-17, branch `ui-motion`).** Two defects in `UIMotion`, both reported on the music library's playlist covers. (1) A cover stuck at 0.92× after its row was clicked — measured in the running client as `slotAbs` 98.80 against `coverAbs` 90.896, exactly the icon tier's press depth, with the cover's `UIScale` reading 0.920. `bindScalePress`'s release took a branch (reduced motion, or a target whose row had been detached) that thawed a frozen label and then returned without putting the scale back; no tween lands on that path, and the teardown settle runs only when the *button* leaves the tree, which a pooled row re-shown as the same instance never does. Every release path now ends at rest: that branch calls the teardown's own `settleScale` (instant, never creates a `UIScale` that was not already there), `bindScaleHover`'s `MouseLeave` had the identical omission at the hover value and gets the same call, and `tintRelease` now writes the captured colour back even on a detached row instead of dropping the capture and leaving the press darken on — which had also taught the next gesture on that row to treat the tint as the design. Reduced motion means no tween, not no final state. The fallback's padding release was audited and left alone: its goals are absolute values rebuilt from the `UIMotionBase*` attributes and its teardown already snaps. (2) A cover stuck at 1.08× after the pointer left, growing to ~1.17× on the next hover with "home" now 1.08×. `UIMotion` kept every gesture's bookkeeping — in-flight tweens, rest captures, ownership, tint captures, frozen labels — in weak-keyed tables, and Roblox drops such an entry as soon as no Lua value references the Instance, **while the Instance stays alive and parented** (proven live: a parented `UIScale` in a weak set, ~40 frames of allocation churn, entry gone, instance still in the tree). Kit binds hold no Lua reference to the `UIScale`s they create, so mid-hover the hover-out could no longer cancel the 0.22 s hover-in, which outlived the 0.18 s hover-out and landed last. Final state: one strong per-instance record, reclaimed only when that instance fires `Destroying` (pooled rows that are merely detached keep theirs — see the `InstanceState` entry under Changed); a `UIScale` that `UIMotion` created itself always rests at 1, identified by identity and by a `UIMotionOwned = true` attribute (UIMotion's own name, so it cannot collide with a buyer's `UIMotionScale`-named instance; a clone inherits it and rests at 1); a borrowed `UIScale` (e.g. `MobileScaleService`'s) has its rest read only while no `UIMotion` tween is moving it; a finished tween that has since been replaced no longer clears the rest a newer gesture is using; and the per-tween rest is dropped by the tween's own completion or cancellation. Lune harness `.tmp/uimotion-scale-rest-spec.luau` 14/14 (7 red on the previous build, with a GC stand-in that drops only weak-keyed entries). Code-only → source sync, no RBXM.
- **Playlist covers and the Admin v3 player picture no longer shrink to a dot (ADR 0011 addendum 2026-09-16, branch `ui-motion`).** The icon tier's `UIMotionIconSlot` held the icon's layout footprint by being pinned to a measurement of its rest `AbsoluteSize` taken at bind time — but pooled rows are built and bound before or during their first layout pass (`AdminPanelV3UI` binds a player card while it is still a detached clone; `ListPool` parents its rows `Visible = false` before `createRow`), so the slot froze a pre-layout size and nothing ever re-measured: a 98.8 px playlist cover sat in an `{0, 8}, {0, 8}` slot inside a 281 × 106 row, the `PlayerProfilePicture` in a `{0, 16}, {0, 16}` slot inside a 236 × 62 row, 14 slots kit-wide under 35% of their button's height. A fixed offset was also the wrong kind of value for icons sized relative to their row (`PlaylistCover` is `{0.5, 0}, {1, 0}` under a `UIAspectRatioConstraint`, `PlayerProfilePicture` is `{1, 0}, {1, 0}`), which would have stopped tracking a resized panel or a phone scale even with a perfectly timed measurement. `UIMotion.slotIcon` now copies the icon's own `Size` onto the slot instead of measuring anything — the slot stands in the icon's place under the same parent and layout, the icon inside is `fromScale(1, 1)` and centred, and the `UIAspectRatioConstraint` still moves up onto the slot — so scale-sized and offset-sized icons alike reproduce their footprint exactly, whenever the bind happens. Slots are built at runtime on `PlayerGui`, never in the `StarterGui` template, so a fresh boot builds them correctly — no buyer repair step. Code-only → source sync, no RBXM.
- **Music player tab switching slides again, and other auto-sized pages slide too (ADR 0011 addendum 2026-09-16, branch `ui-motion`).** `PanelShell:_applyTab` still called `UIMotion.slideIn` on every real switch, but `slidePaddingOf` refused **any** page with `AutomaticSize ~= None`, and all three music tab frames are `AutomaticSize.Y`, so the slide returned without doing or saying anything. A slide moves padding along one axis — `slideIn` the left/right pair, `slideInVertical` the top/bottom pair — and a page only resizes when it measures itself along *that* axis, so the guard now takes the travel axis and refuses only on an overlap; the fallback press squash keeps its all-axis (`XY`) refusal, because it insets all four sides in one tween. The re-wrap hazard that made the blanket guard look safe cannot occur: the two offsets are equal and opposite, so the content box's width never changes — measured live on `06-MusicPlayerGUI`, `LibraryTab` and `NowPlayingTab` held 950 × 554.80 at rest, with `+28 / −28` applied, and back. **Visible change:** every other `slideIn`/`slideInVertical` target that is auto-sized on the axis it does *not* travel along was being skipped the same way and now animates. A refused slide is no longer silent: it writes the axis it wanted to a runtime-only `UIMotionSlideRefused` attribute on the page (cleared when a slide runs) — deliberately an attribute and not a warning, since a refusal repeats on every tab switch and console noise in a shipped kit is worse than silence. No config, API or DataStore change. Code-only → source sync, no RBXM.
- **Text-only buttons had no press or hover at all (ADR 0011 addendum 2026-09-16, branch `ui-motion`).** Reported on the Admin Panel v3 custom-title **Save** and **Remove** buttons, which the coverage audit called healthy (`UIMotionBound = "fallback"`) because they *were* bound — the fallback just showed nothing on their shape: an `ImageButton` with an empty `Image`, a `UIPadding`, a `UIListLayout` centring on **both** axes, and one auto-sized `TextLabel`. Insetting that padding on all four sides re-centres the content in the smaller inner rect, so a child that does not fill it moves zero pixels, and hover was the white wash the icon tier had already removed elsewhere. `UIMotion.squashPaddingOf` now refuses the padding branch when it cannot move anything (centring layout, no visible child sized in scale on either axis) and falls through to the brightness dip, and the new **text tier** (see Added) lifts the label instead; the label is never reparented, because kit code finds these labels with non-recursive `FindFirstChildWhichIsA("TextLabel")`. Code-only → source sync, no RBXM.
- **Music v3 GUI: a duplicated element no longer hides silently.** `Client/UI/Music/GuiRefs.need` resolved names with `FindFirstChild`, which returns the first of two same-named children without complaint — a pasted-twice `QueueListTemplate` in a place's GUI sat visible forever. `need` now counts same-named direct children and, when there is more than one, warns **once per (parent, name)** with the ScreenGui name, the duplicated name, the full path and the instruction to keep the first and delete the extra; it still returns the first match, so nothing else changes. The once-guard is a plain string-keyed table (parent full name + child name), not a weak Instance-keyed one (see the `InstanceState` entry). Spec `.tmp/guirefs-duplicate-spec.luau`, 12 checks. Code-only → source sync, no RBXM.
- **Music v3 Now Playing: a queue row that fails its motion bind no longer leaks.** `NowPlayingView._row` parented the cloned row, then bound press/hover motion, then registered the row in `_rows`. A throw inside the binds left a parented, unregistered clone that `renderQueue` never hid, showing the template placeholder text. The row is now registered immediately after parenting; the two `_bindMotion` calls run under `pcall`, and a failure logs `[NowPlayingView] queue row <n>: motion bind failed …` and leaves the row usable without motion. `renderQueue` untouched. Code-only → source sync, no RBXM.
- **A track's own cover never reached players (Music v3).** The client already shows a track's `coverType`/`coverValue` over its playlist's cover (`MusicPlayerCoverHelpers.resolveCoverSourceForTrack`), but `MusicRepository.cloneTrack` and `_serializeTracks` copied every track field except those two. Every read (`getTrack`, `getTracks`, the web snapshot) and the DataStore cache dropped them, so every track showed its playlist's cover. They are now carried through. This is what makes the customer area's new per-track image cover (Edit track → Cover → Gambar sendiri) visible in game. Spec `.tmp/music-repository-track-cover-spec.luau` **9/9 under lune**, red first (7 failing before the fix). Code-only → source sync, no RBXM.
- **Admin Panel v3 had no way in on a v3-only place.** With `Features.AdminPanelV3 = true` the v3 panel takes the admin topbar icon, but only the classic `AdminController` ever switched that icon on for admins. A place that has dropped `04-AdminPanelv2` makes that controller return before its role listener, and `AdminTitleV3Controller` only switched the icon off — so the icon stayed hidden for everyone, owners included. Found on THE BASIC TEST after turning the flag on: the icon was disabled for an Owner; forcing it on showed the panel itself opens and closes correctly. `AdminTitleV3Controller` now shows the icon exactly when `PermissionDomain.canUseAdminPanel` allows it, reading the local player's role from the overhead payload cache the classic panel also uses, and re-checks it when that payload changes. A role losing access hides the icon and closes the panel. Places where the Admin Hub owns the icon are unchanged. Code-only → source sync, no RBXM.
- **Any player could end the song for the whole server (DoS sweep D1).** `MusicDurationReport` is accepted from every client, and `MusicSession.onDurationUpdated` called `advanceQueue()` whenever the reported duration put the song's end within 5 s of now — so one crafted report of "this track is `elapsed` seconds long" skipped it for everyone, rate limit or not. The decision now lives in new pure `Shared/Domain/MusicDurationPolicy.evaluate`, which can lengthen or (only while the library duration is unknown) shorten the end-of-song timer, but **never ends a song**: a report inside the minimum-remaining window is ignored, a report shorter than a known library duration is ignored, and NaN / infinite / non-positive / over-four-hour values are refused. A track that really is that short still ends promptly through the existing `PlaybackFinished` quorum, where one client cannot decide alone. Spec `.tmp/music-duration-policy-spec.luau` **33/33 under lune**, red first. Code-only → source sync, no RBXM.

### Removed
- **`Client/UI/CoupleUI.luau`** — dead since the couple panel moved into `CoupleController`, which binds `01-CoupleSystemGUI` itself. Nothing in `src/`, `default.project.json`, `tools/`, `docs/`, `CONTEXT.md` or `CHANGELOG.md` required or named it; the only hits were the unrelated blur-name string `"CoupleUIBlur"` (`SettingsController`, `CoupleController`) and the tracked `sourcemap.json`, which is a month stale (last regenerated at v2.6.0, 2026-08-16) and keeps a `CoupleUI` entry until `rojo sourcemap` is next run. Buyer places drop the orphan ModuleScript on Update Engine; list it under Removed in the release's `CHANGED_FILES.md`.
- **`Client/UI/Music/MusicMotion.luau`** — promoted into `Client/Utils/UIMotion` (ADR 0011); the four music views require `UIMotion` and nothing requires the old module.

## [2.12.0] - 2026-09-12

### Added
- **A nametag layer or badge can now be switched off entirely, not just defaulted off.** `ClubKitConfig.Overhead.DefaultLayers` / `DefaultBadges` already took a boolean per key, but only as a *starting value* for a player's first stored record — Settings could switch the layer straight back on, and a changed default never reached players who already had a record. A buyer who simply does not want a layer in their venue had no way to say so. Each key now takes **three** values: `true` (shown), `false` (hidden to begin with, the player may switch it on — the original meaning, unchanged) and **`"off"`** (also `"disabled"`; case and surrounding spaces forgiven) meaning off for **everyone, always** — with the layer's row removed from the Settings menu, so nobody is left holding a switch that does nothing. Unlike the defaults, a hard-off is **enforced** rather than seeded: `OverheadDomain.buildPayload` forces those keys false on both public maps, so it reaches players whose stored record predates the change, and `OverheadUI` refuses them at render even when the viewer's own local attribute says otherwise. Nothing stored is rewritten, so deleting the `"off"` later brings every player back exactly as they had it — no migration, no DataStore key change. Hard-off also beats the four kit paths that force a layer visible: an admin granting a custom title (`SpecialTitle`) and a couple forming (`CoupleName`, in `CoupleDomain.applyCouple`, `OverheadController` and the client's relationship patch) each check `OverheadDomain.isLayerDisabled` first, so none of them resurfaces a switched-off layer or banks a dead `true`; the server's settings write filters the incoming maps through the same rule, so a crafted remote cannot store one either. A whole switched-off group takes its section heading with it, because `SettingsTabBinder` already hides a section whose rows are all invisible — and `BadgeGroup = "off"` hides every per-badge toggle for the same reason. Overloading the existing table was chosen over a second one deliberately: the kit ships `CoupleName = false`, so reading `false` as "off" would have silently killed the couple row on every place and fought three call sites that force it true. A value that is none of the three is ignored with a warning naming the key (`[ConfigBootstrap] Overhead.DefaultLayers.X is not true, false or "off"; keeping true`) rather than guessed at, and an unknown key is still ignored rather than inventing a layer. New pure `Shared/Domain/OverheadLayerPolicy` owns the rule (`classify` / `defaultVisible` / `disabledSet` / `isDisabled` / `enforce` / `invalidValueKeys`), TDD'd red-first: `.tmp/overhead-layer-lock-spec.luau` is **49/49 under lune**. Code-only → source sync, no RBXM. Verified in a PARKLAB playtest with `DefaultLayers = { BadgeGroup = "off" }` on the real buyer config: the projection lands (`DISABLED_LAYERS = [BadgeGroup]` on **both** server and client, `DEFAULT_LAYER_VISIBLE.BadgeGroup = false`), `isLayerDisabled` answers true for `BadgeGroup` and false for `Rank`, a stored record written *before* the change keeps its `BadgeGroup = true` on load but its payload comes back `false` while `Rank` and `DisplayName` stay `true` (the retroactive claim, on a synthetic record), the write guard turns a client-supplied `{BadgeGroup = true}` into `false`, and the Settings filter hides the "Badges" row plus every per-badge row while leaving the control rows visible — 6/6 cases against a payload built so the content rules would all have passed. Clean boot, zero kit errors. **Not observed:** the badge group disappearing from a live nametag *because of* this flag — the test account's stored record already had `BadgeGroup = false`, so the absent row (lazy rows are pooled, so a hidden row is simply not built) cannot be attributed to the hard-off; the payload-level proof is what covers every viewer. Also unverified live: the admin-title-grant guard, the junk-value warning text, and the *Badge Types* heading vanishing (the Settings tab builds lazily and was not opened).
- **Membership tiers are now a real on/off switch — run 3, 2, or 1 tier.** `ClubKitConfig.Membership.TierN.Enabled = false` already existed, but it only wrote `Config.Membership.PAID_TIERS`, which governs what counts as a *paid membership* (badge, chat tag, leaderstats Rank). Every shop-facing surface instead iterated `Config.Membership.SHOP_TIERS`, a hardcoded `{Tier1, Tier2, Tier3}` the flag never touched — so a "disabled" tier stayed fully purchasable, and the server's `syncOwnedGamePasses` still granted it to anyone owning the gamepass. `ConfigBootstrap` now derives `SHOP_TIERS` from the enabled set, which switches the tier off across all six consumers at once (ShopUI cards, GiftUI tabs, both ShopControllers, `ShopDomain.parseShopTier`, and the Admin Hub gift menu). The list is filtered **in place** because `ShopUI`/`GiftUI`/`ShopDomain` capture it by reference at module load. `ShopUI` additionally hides the disabled tier's card + notification, and `GiftUI` hides its tab frame plus any selector button left unbound (button resolution falls back to *position*, so a surplus button would otherwise stay on screen, correctly labelled and completely inert). The shop card row is a horizontal `UIListLayout` with `SortOrder.Name`, so the remaining cards reflow on their own — no GUI edit, so this ships by normal source sync rather than an RBXM. `OverheadDomain.getHighestStoredMembership` also drops a disabled tier for players who **already hold it** (bought the gamepass, or were gifted it before the switch) — otherwise it lived on in the leaderstats Rank column, the chat tag and the overhead badge. That filter runs at resolve time, never at storage, so re-enabling a tier brings the membership straight back instead of destroying what people paid for; gifted entries are filtered individually, so holding both Tier2 and a disabled Tier3 still resolves to Tier2. Config validation also stops warning about missing Game Pass / Product ids for a disabled tier. Verified live: with `Tier3.Enabled = false`, `SHOP_TIERS` = `{Tier1, Tier2}`, the `3-ELITE` card and the third selector button are hidden, and the layout's `AbsoluteContentSize` matches the container exactly (no gap left behind).
- **Notification center V2 — support for the redesigned `99-NotificationCenterV2` GUI.** The redesign turned the greeting and broadcast templates from CanvasGroups into Frames (so `UIShadow` renders), and both binders refused anything but a CanvasGroup: **every announcement and every join greeting was silently dropped** (`JoinGreetingController` warned once; `GenericBroadcastController` logged "BroadcastMessageTemplate not found" per broadcast). Loosening the type check alone would not have helped — `GroupTransparency` does not exist on a Frame, so the presenter would throw after parenting and strand the card on screen. All four binders (`GeneralNotificationCenterService`, `DonationNotificationController`, `JoinGreetingController`, `GenericBroadcastController`) now resolve the GUI through new `Client/Utils/NotificationCenterGui` — `99-NotificationCenterV2` first, `99-NotificationCenter` as fallback, no config flag — and animate by the card's class: CanvasGroup keeps `GroupTransparency`, a Frame fades every descendant from its own recorded transparency (background, text, image, `UIStroke`, `UIShadow`) through new `Client/Utils/GuiFade`. On **V2 only** the binders follow the designer's values instead of kit constants: the card rests at its own UIScale (the greeting no longer stacks an extra 0.9 on the wrapper's 0.8), `CountDownBar` drains from its designed width (0.8, not a forced 1.0), the donation amount keeps the designed `TextSize` as a ceiling and steps down only until no word breaks mid-digits, the general toast shows its icon (it was never made visible) and keeps the designed stroke colour, and the donation total line reads `Top #N Robux | Total : 32.000` / `Top #N <provider> | Total : Rp …` while the donor is in the top 10 (`newRank`). A V2 GUI left at `DisplayOrder` 0 is lifted to `Config.NotificationCenter.V2_DISPLAY_ORDER` (300) — it used to render under mobile panels (200/201). V1 places keep their exact previous behaviour. `MobileScaleService` and `MobilePanelManager` treat both names alike. GUI is place data: the buyer renames or installs it manually (RBXM), the code ships by source sync. Verified in a PARKLAB playtest (GUI renamed to V2): broadcast enters from transparent (background and `UIShadow` 1.00 → design 0.00 / 0.80, scale 0.88 → template 0.90), drains from bar width 0.80, fades out and cleans up; join greeting renders with avatar, role badge and gradient bar; Robux panel showed `Top #3 Robux | Total : 32.000`, amount at the designed size, message `"Mantap <b>DJ</b> & crew!"` rendered literally; cash panel `Top #1 Saweria | Total : Rp 3.200.000`, and without a rank the plain `Total : Rp 3.200.000`; toast icon visible, description full panel width; zero kit warnings. The final amount-fit headroom (0.97, measured: a 113 px word stayed whole in a 116 px column, 114 px broke) was **not** re-run — Studio closed the place first.
- **Phone scale for Admin Panel v3 and the Custom Title panel.** `04-AdminPanelv3` and `1000-01-CT-ADDON` had no phone entry in `MobileScaleService`, so they kept their desktop UIScale (0.88) on a phone. New `Config.MobileScale.ADMIN_PANEL_V3_GUI = 0.45` and `CUSTOM_TITLE_GUI = 0.55`, applied to the ScreenGui's root UIScale on phone layout only. Verified in a PARKLAB playtest on the Samsung Galaxy A16 emulator (0.45 / 0.55) and on desktop (both still 0.88), zero kit errors.
- **Phone scale for the Free Title event card.** `ADDON-FreeTitleEventTrigger` now rests at `Config.MobileScale.FREE_TITLE_EVENT_CARD` (0.7) on phone layout instead of 1. It cannot go through `MobileScaleService` like the others: `FreeTitleEventUI` tweens that same root UIScale for its entrance (0.75 → 1) and exit (→ 0.75) and resets it to 1 on hide, so a value set from outside would be overwritten on the first entrance. The binder now treats the phone value as the resting scale — entrance starts at 0.75× of it and lands on it, exit shrinks from it, hide resets to it — read at each use, so a rotated viewport picks up the right size next time. Desktop unchanged (1). Code-only → source sync.
- **Join greeting is always one line on notification center V2.** The greeting `Message` wrapped onto a second line whenever the text outran the card. `JoinGreetingController` now fits it through new `Client/Utils/TextFit.singleLine`: the designed `TextSize` is the ceiling, it steps down until the whole text fits the width, and "…" truncation only applies below size 12. Runs after the card is shown and again when the message crossfades to "has entered the space". Needs the V2 template's `Message` at a fixed width with wrap off (`TextScaled` cannot do this — the engine turns `TextWrapped` back on with it); PARKLAB's template was changed accordingly. Verified on the phone emulator: a 64-character greeting fitted at 15, "VIP Budi has entered the space!" at the designed 24, an 85-character one hit 12 and truncated — one line in every case; card lifetime unchanged (4 s + fade + 6 s hold → removed at 11.2 s).

### Changed
- **High is now a preset that pushes quality UP, not one that merely stops degrading it.** Owner: "grafik high ini harus bener-bener high tanpa kompromi." The tier was passive by construction — `partShadows = true` only restored each part's own `CastShadow`, `surfaceAppearance = true` only re-attached, `workspaceVfxMode = "Full"` is rate scale 1.0 (the original), and `postProcessing` **"Full" and "Standard" run byte-identical code** (only "Minimal" differs) — so "High" meant "the map as built" and nothing more. Two things changed in the kit, and the third — the one that would have mattered most — turned out to be impossible on the platform. **(1) Mesh detail cannot be a preset knob at all, and is now documented as place data.** A venue typically ships most meshes at `RenderFidelity.Performance` (lowest detail at every distance, whatever the preset), which is the single biggest reason High never looked like HD however many shadows it drew — PARKLAB measured **2010 of 3365 MeshParts at `Performance`**. High was built to force them to `Precise` at runtime, and that was reverted before release: **`MeshPart.RenderFidelity` cannot be changed at run-time.** The engine warns `Cannot change SolidModel RenderFidelity during Run-Time` on *every* write (measured: 40 writes → 40 warnings, and ~1352 warnings for one sweep of a streamed PARKLAB client), and although the property value *does* change — so a census of it reads like success — the renderer keeps the mesh it tessellated at load, so nothing visible happens. The sweep was therefore pure cost and pure log noise. Mesh fidelity is now authored in Studio and saved, exactly like `Lighting.Technology`; `GraphicsBundle` carries a comment where the field was so nobody re-adds it. **(2) The Shadows toggle no longer downgrades High behind the player's back:** the High bundle declared `shadowQuality = "Balanced"`, and the Settings row is a two-value toggle that stores `"Balanced"` when switched on whatever preset you are on — so a High player who toggled shadows off and on again landed on Balanced's softness (0.15 instead of 0.55) with no way back short of re-picking the preset. High now declares `"High"`, and turning shadows back on restores the **preset's own** fidelity rather than a hardcoded Balanced/High split; `isMappedToggleEnabled` gained an opt-in `onValues` list so the row does not read OFF on the preset with the best shadows (two-value toggles like `chatBubbleVisibility` are untouched). **(3) The real ceiling is the player's own Roblox slider,** which caps everything the kit can do: at `QualityLevel1` High still renders at the client's lowest quality. `UserGameSettings.SavedQualityLevel` is `ReadWrite` with no write security, but it is an **account-wide** setting that follows the player into other experiences, so the kit only **reads** it and says so once per session (`Config.Graphics.SUGGEST_QUALITY_BELOW_LEVEL`, default 8; `Automatic` never triggers it, since the engine is already choosing per device). **Deliberately not done:** High does not override artistic intent — no switching on a `Bloom` the builder disabled, no forcing `CastShadow` onto a part left non-casting, no raising `EnvironmentDiffuse/SpecularScale` above the map's own values; those change how a venue *looks*, which is not the same as rendering it at higher fidelity. The identical "Full"/"Standard" post-processing paths are therefore left as they are, on purpose. **Phones** render at `Config.Graphics.PHONE_MAX_PRESET` (Balanced) when the stored preset is High — Precise on every mesh is not carryable there — and the stored choice is never rewritten, so the same account gets High again on desktop. **Out of the kit's reach entirely:** `Lighting.Technology` is `ReadOnly`/`RobloxScriptSecurity` and documented "non-scriptable, only modifiable in Studio" — on `Voxel` there are no shadow maps and High's `ShadowSoftness = 0.55` does nothing at all, so a venue wanting the full look must switch to `Future` by hand in Studio. New `GraphicsQuality.clampPresetForDevice` / `shouldSuggestQualityBump`; spec `.tmp/graphics-tier-spec.luau` **49/49 under lune, red first**. Code-only → source sync, no RBXM. **Verified in a PARKLAB playtest 2026-09-12:** the High bundle resolves `shadowQuality = "High"` / softness 0.55, the shadows round-trip keeps 0.55 (the bug is gone on the real place), the phone clamp answers correctly in all three directions, and the Shadows row — read from the shipped `SECTION_DEFS`, not a hand-built def — reads ON for both `"High"` and `"Balanced"` and OFF for `"Off"`. **Not observed live:** the slider notice, because the test account's `SavedQualityLevel` reads `QualityLevel10` and therefore correctly stays silent; its logic is covered by the spec only. Mesh counts quoted from playtests are over a *streamed* subset (810–1352 of the true 3365) — Edit mode is the only place to census a full Workspace.
- **Graphics presets now differ where it costs frames, and "Shadows Off" means zero shadows.** Two causes made Low / Balanced / High feel alike. First, every per-instance pass was gated behind the opt-in `ScalableGeometry` / `ScalableVfx` tags (or an empty `Config.Graphics.GEOMETRY_FALLBACK_ROOT_NAMES`), so on an untagged map — every buyer place checked — no part's `CastShadow` and no light's `Shadows` was ever touched; Low only flipped `Lighting.GlobalShadows`, and PARKLAB kept 267 shadow-casting club lights on every tier. Second, Balanced and High were near-identical: `postProcessing` "Standard" and "Full" run the same code path, and "Reduced"/"Full" VFX only reach tagged instances. New `Client/Services/WorldGraphicsService` is now the single owner of shadow casting and `SurfaceAppearance` across the **whole Workspace**, untagged maps included, and keeps late arrivals in line (StreamingEnabled, avatars, GLights fixtures that build their lights on the client) through a `DescendantAdded` watcher that only exists while something is forced off. Tiers: **High** = the map as built; **Balanced** = sun shadows kept, every local light's `Shadows` off; **Low** = `GlobalShadows`, light `Shadows` and part `CastShadow` all off, with the map's textures and `SurfaceAppearance` kept as built (an earlier cut of this change also detached `SurfaceAppearance` on Low; reverted on the owner's call 2026-09-11 — Low should cut shadows, not the map's look). The `Shadows` toggle turned off gives the same zero on any preset. Turning shadows back on restores each instance's own original value — parts the builder left non-casting stay non-casting. `SurfaceAppearance` is detached rather than blanked because its maps are `PluginSecurity`; the previous `Textures` toggle wrote `ColorMap = ""` through a `pcall` that always failed, so it never removed a single PBR texture — the toggle now drives the detach in both directions. `Lighting.EnvironmentDiffuseScale` / `EnvironmentSpecularScale` are now scaled from the map's own values instead of being overwritten with absolutes (High forced both to 1.0, brighter and shinier than the builder set). New `GraphicsQuality` bundle fields `lightShadows` / `partShadows` / `surfaceAppearance`; spec `.tmp/graphics-tier-spec.luau` 21/21 under lune. Verified in a PARKLAB playtest: Low left 0 of 102 lights shadowing and 0 of 1,138 parts casting; a late-added part, spotlight and `SurfaceAppearance` were caught within half a second; switching back restored 176 lights and 1,083 parts to exactly their original values. Code-only → source sync.
- **New players now start on the Low graphics preset, and the starting preset is buyer config.** `SettingsDomain` hardcoded `graphicsPreset = "Balanced"` as the default for anyone without a saved settings record (and for Settings → Reset). The starting preset now comes from `ClubKitConfig.Graphics.DefaultPreset` (`"Low"` | `"Balanced"` | `"High"`, kit default **`"Low"`**), projected by `ConfigBootstrap` to `Config.Graphics.DEFAULT_PRESET` and read by `SettingsDomain.defaultStoredData()` at call time. The default carries the preset's own stored fields (`shadowQuality`, `hideAllParticles`, …) so the Settings toggles match what renders from the first frame. **Who it reaches:** only players with no saved settings record — the kit saves the whole panel on any change, so anyone who ever touched Settings keeps what is stored for them. A typo keeps Low and warns once (`Unknown Graphics.DefaultPreset`); case and surrounding spaces are forgiven, and legacy `"Ultra"` reads as High. The client's pre-hydration preset follows the same default, still capped at Low on phones. **Buyers who want the old behaviour** set `Graphics = { DefaultPreset = "Balanced" }` — fill-forward supplies `"Low"` when the section is absent. New `GraphicsQuality.resolvePreset`; spec `.tmp/settings-default-preset-spec.luau` 25/25 under lune, red first. Verified in PARKLAB: live `defaultStoredData()` = Low / Off / particles hidden on the real buyer config (no `Graphics` section); fresh `Config` clones project `"High"` → High, `" balanced "` → Balanced, `"Medium"` → Low with the warning; clean boot, zero kit errors.
- **The topbar menu pill reads "Close Menu" while open, instead of a bare "X".** `TopMenuController.configureMenuIcon` hardcoded `{ "IconLabel", "Text", "X", "Selected" }`; the open state now takes its text from the new `Config.TopbarMenu.LABEL_SELECTED` (default `"Close Menu"`), matching how the closed state already reads `Config.TopbarMenu.LABEL`. The `TextSize = 20` override on the selected state is gone with it — that size existed to make a single "X" glyph read at icon scale, and would have made a whole word tower over every other pill; both states now sit at the theme's 16. Width needed no change: `setWidth` sets TopbarPlus's `DesiredWidth`, a minimum, so the pill grows from 94 px to 110 px on open and the 82 px label is never truncated.

### Fixed
- **Donor messages could inject RichText markup into the donation panel.** `DonatorMessage` is a RichText label in both notification center versions and the message was only trimmed, so `<b>`, `<font>` or a bare `&` in a donation message rendered as markup (or broke the line). The message is now escaped whenever the target label has RichText on.
- **The daily streak overlay never appeared, and its sunburst never spun.** `StreakUI:play()` enabled the `05-StreakGUI` ScreenGui but never set `Overlay.Visible`, and the template ships that frame `Visible = false` — so the whole sequence (scale pop, 0→N counter, spark burst, glow pulse, auto-dismiss) played to completion on an invisible frame, once per WIB day, seen by nobody. Measured in a test-place playtest by sampling the instance every 0.2 s while firing `StreakNotif`: `Enabled = true`, `Overlay.Visible = false` for the entire ~6 s animation, counter climbing 0→7, `StreakImage.Size` pulsing 400↔430 — all of it off-screen. Two dead details came with it: `Overlay.RotatingBackground` (the sunburst behind the flame) was never rotated, even though `AnimationHelper:startRotation` exists for exactly that instance and both `GiftUI` and `DonationNotificationController` already drive it; and the "fade in overlay" tween ran `BackgroundTransparency` from 1 to 1, a no-op that left `Config.Streak.OVERLAY_TRANSPARENCY = 0.45` unused, so the dim backdrop never existed either. `play()` now shows the frame, starts the sunburst (new `Config.Streak.ROTATION_SPEED`, 5 s per turn) and fades the backdrop to `OVERLAY_TRANSPARENCY`; `dismiss()` reverses all three, guarded by a play id so a notification arriving during the 0.3 s fade-out is not hidden by the previous one's cleanup. `RotatingBackground` is resolved with `FindFirstChild`, so a place whose GUI lacks it keeps working. Code-only — ships by source sync, no RBXM, no GUI edit. Unrelated but adjacent, and **not** fixed here: the streak notification is fired 1.5 s after `CharacterAdded` (`Config.Streak.CLIENT_READY_DELAY`) while `00-LoadingScreen` still has every ScreenGui disabled, so on a slow-loading place the overlay can still play out behind the loading screen — tracked separately.
- **Image preloading scored every asset as failed, so nothing was ever warm.** `ImagePreloadService` judged each warmup probe by `ImageLabel.IsLoaded`, but that property does not flip until the engine has actually *rendered* the instance — and the probes are deliberately off-screen (`KEEP_RESIDENT = false`, the default). Every batch therefore came back `warmed = 0`, with the whole queue counted `unresolved`; the `warm` set stayed permanently empty, so `ImageSwap` never took its instant-swap path and every image in the kit went through the slow load-then-fade route instead. Readiness now comes from `ContentProvider:PreloadAsync`'s per-asset callback (`Enum.AssetFetchStatus.Success`), which reports the real fetch result regardless of rendering; `IsLoaded` remains only as a fallback for ids the callback never reports (batch abandoned on timeout, unexpected id form). Measured in the WIP place: `warmed = 0 / unresolved = 161` before, `warmed = 230 / unresolved = 6` after, same place and same boot path. This also retires the `warmed=0` line in the Perf & Structure baseline — it was an instrumentation defect, not 161 broken assets.
- **The donation panel repainted on every overhead sync, even when nothing changed.** `DonationSystemController.applyOverheadProfile` called `ui:applyDonorProfile(merged)` unconditionally. The server echoes the full overhead payload rather than deltas, so an idle player with no donations re-painted the panel **53 times in five minutes** with byte-identical numbers. It now compares the merged snapshot against what the panel was last actually painted with (display name, both totals, both ranks) and returns early when they match. The comparison keeps its own `lastAppliedDonorProfile`, separate from `lastDonorProfile`, because `fetchDonorProfile` updates the latter without painting. Same playtest: 53 applies before, 1 after.
- **The leaderboard's last-known-good fallback threw instead of serving its cache.** `DonationLeaderboardRepository` called its generic helper with explicit type arguments — `tryReturnLastGood<{ PlayerLeaderboardEntry }>(cacheKey)` — a call syntax Luau does not have. The parser reads it as two comparisons, `(tryReturnLastGood < { … }) > (cacheKey)`, so the line raised `attempt to compare function < table` (and `< nil` for the `<number>` sites) instead of calling anything. All six sites sit on error paths — DataStore throttle lockout, or a failed `GetSortedAsync` / `GetAsync` — so the happy path never reached them and the defect survived undetected. The effect was that `getRobuxLeaderboard`, `getPlayerRobuxTotal` and `getCommunityLeaderboard` each lost their fallback at exactly the moment it was meant to fire, turning a recoverable DataStore hiccup into a hard error. The type intent is kept by annotating the receiving local instead (`local lastGood: Result<{ PlayerLeaderboardEntry }>? = tryReturnLastGood(cacheKey)`), which hands Luau the same `T` by inference. Found in a TIX 2 playtest with Studio API access still disabled, which made all six paths live at once.
- **A lapsed `maintenance_until` silently killed a buyer's whole donation surface (backend).** `isLicenseBlocked()` treated a past `games.maintenance_until` the same as a revoked licence: every `/game/{key}/v2/*` route returned `403 license_expired`, so the Bagi-Bagi leaderboard, donation notifications and donor Cash all went blank with no message to the buyer and no alert to us — indistinguishable from "the data got reset". KASTA went dark 2026-08-31T11:48Z with all 79 donation rows intact; `vicenorth` and `altantis2` were in the same state, and `haven` / `tix` / `parklab` were queued to follow. `maintenance_until` is now informational only; cutting a game off requires an explicit `license_status` of `expired` or `revoked`. Regression test added in the infra suite (`a lapsed maintenance_until does not block v2 routes`). Backend-only — buyers need no kit update.

## [2.11.0] - 2026-08-30

### Added
- **Multi-color role gradients — `roleColor.stops`.** A role in `ClubKitConfig.RoleCategories` / `SystemRoles` / `SpenderRoles` may now carry `roleColor = { stops = { "daad18", "ffed2a", "fdff90", ... } }` (2..5 hex, `#` optional): the overhead special-rank text (`04-SpecialRank`) is painted with that gradient instead of the template's fixed one. `primary` / `secondary` (chat colors) default to the first / last stop when omitted. Sanitized once at boot by the new pure `Shared/Domain/RoleColorDomain` (malformed entries dropped, <2 valid stops = no gradient). Setter is keyed on the stop list so server full-state echoes are no-ops.
- **External loading-screen contract** (`Config.ClientBoot`). When `Features.LoadingScreen = false`, `Main.client` now publishes boot state on `Players.LocalPlayer` — `ClubKitBootProgress` (0..1), `ClubKitBootSettled`, `ClubKitGameplayReady` — and, if a pack sets `ClubKitExternalLoading = true`, holds `enterGameplay` (join-community prompt, join greetings) until the pack clears it or `EXTERNAL_LOADING_TIMEOUT` (300 s safety net) passes. Lets a place pack draw its own loading screen without racing the kit. First consumer: `extras/place-packs/CinematicLoading` (Hierapolis; not engine). Kit music Sounds now sit in a `SoundService.ClubKitMusic` SoundGroup, silenced while `ClubKitExternalLoading` is true so a pack's loading track is the only thing heard.

- **Runtime integrity guards (ADR 0008, phase 1).** New `Server/Init/RuntimeGuard`: **SoundGuard** (every `Sound` present at server start is the allowlist; a runtime `Sound` with an unknown id outside kit roots is logged + beaconed, and stopped/destroyed when `Config.RuntimeGuard.SOUND_ENFORCE = "block"` — default `"log"`), **ScriptGuard** (a Script/LocalScript/ModuleScript created at runtime outside the kit and outside admin-loader parents → log + beacon `runtime:script_injected`, optional destroy), **RemoteStorm** (one player firing > 40 RemoteEvents/s for 3 s → beacon + kick), **AvatarGuard** (server-owned appearance: accessories over 10 studs on an axis, characters over 14 × 10 studs, Beam/Trail/light/particle "laser" accessories → removed or capped per `Config.AvatarGuard`, one notification per session, beacon `runtime:avatar_trimmed`; no kick by default). Pure rules in `Shared/Domain/AvatarPolicy`.
- **Movement cheat guard (ADR 0008 Layer 2b).** New `Server/Init/MovementGuard` + pure `Shared/Domain/MovementPolicy`: samples every character each 0.5 s and scores physically impossible streaks — speed (3 consecutive samples over `WalkSpeed × 1.6 + 4`), client-set `WalkSpeed > 32` / `JumpPower > 75`, fly (4 hovering samples with no ground within 8 studs), high jump, noclip (path crosses `CanCollide` geometry twice in 10 s; opt-out tag `ClubKitNoclipIgnore`), teleport (> 60 studs in one sample without a server stamp), infinite jump. Kit states are exempt first: gravity float, carry, server teleports (`CharacterReady.pivotTo` now stamps `ClubKitTeleportAt`), spawn grace, seats, ping > 600 ms, roles in `EXEMPT_ROLES` (Owner, CoOwner). Strikes decay 1 per 20 s; 3 → warning toast + beacon, 5 → kick with reason + 15-minute soft ban for that server + beacon `runtime:movement_kick`. **Ships `ENFORCE = "log"`** — strikes, warnings and beacons all fire, only the kick is withheld — so the first week produces evidence against real venues (custom teleport pads, elevators, vehicles) before a false kick can cost a paying guest; set `Config.MovementGuard.ENFORCE = "kick"` to enforce. Same-day audit hardening: the noclip raycast excludes every character and requires the reverse ray to hit the same part (cut corners and doorway crowds no longer count), seated players (vehicles / lifts) are exempt from the displacement rules, `MovementGuard.stampTeleport(character)` is the hook for buyer teleport pads, RemoteStorm defaults to `log` because it counts third-party remotes too, and all guard connections/tables are bounded and released on leave.

- **Per-role privileges inside a category.** A role in `ClubKitConfig.RoleCategories` may carry its own `privileges = { ... }`; `RoleCategoryBuilder` merges it over the category's set and `PermissionDomain` consults the role-level map first (`Config.RolePrivileges.ROLE_PRIVILEGES`). Lets a buyer group differently-powered staff under one label (Hierapolis "DPC": Scripter / Operational / Admin / Lead Dancer).
- **`Features.HierapolisCustom` (place-pack flag).** New manifest flag (default `false`, fill-forwarded like every other feature). When `true`, `ConfigBootstrap` merges the buyer-owned module `ReplicatedStorage.Hazastudio_ClubKitConfig.HierapolisCustom` (shipped by `extras/place-packs/Hierapolis`, never by Update Engine) over the buyer config at boot: `RoleCategories` / `LegacyAliases` / `CommandAliases` replaced wholesale, `SystemRoles` per entry, `Features` key by key. `ClubKitConfig.luau` itself is never rewritten, so the add-on toggles with one `true`/`false` (plugin Config panel) exactly like `LegacySyncBhms`. Module missing or broken → warn and run the stock catalog. The packager strips the module from product packages and resets the flag in the blank template. `CinematicLoading` pack gates on the merged `LoadingScreen` value.
- **Role chip in the overhead.** `specialRank = { text, gradient, chip = true }` shows the role text as a pill in the donation-chip row (`00-DonationLayers`, cloned from the Robux rank pill, first in the row) painted with `roleColor.stops`, and hides that role's `#N ROBUX` / `#N cash` / SUPPORTER chips. Payload field `roleChip` (fingerprinted for delta sync). For chip roles the `04-SpecialRank` row shows the role's `chatTag` ("DPC", "OWNER") instead of repeating the chip text; an admin-set custom special rank still wins.

### Fixed
- **Client boot gave up on heavy places.** `Config.Loading.BOOTSTRAP_WAIT_TIMEOUT` was 30 s per dependency; on a large venue running at 4–5 FPS (video walls, 28k-instance maps) `Remotes` / `Icon` replicated later than that and `Main.client` bailed with "Critical client dependencies were not replicated in time" — no kit UI at all. Now 120 s (verified on Hierapolis: kit boots at ~37 s under the same load).
- **Admin Hub "Set role" only offered the stock roles.** The picker was a hardcoded list (Co-Owner / Staff / Moderator / DJ / …), so a buyer catalog with renamed or extra roles (e.g. Minister, Emperor, Echoborn) could not be applied from the hub — only via `/setrole` in chat. It is now built from `Config.Roles` at open time (setrole-only roles in catalog order, category label as subtitle); the template's pick cards are re-keyed by `LayoutOrder`, cloned when the catalog is longer than the template, and parked when shorter.

## [2.10.0] - 2026-08-28

### Fixed
- **CanvasGroup panels/toasts going blank or flickering (diagnosed on RUST, consistent across devices).** Root cause per the Roblox `CanvasGroup` reference: a group is rasterized to a texture sized by its `AbsoluteSize`, a size change **re-creates** that texture, and exceeding the client's texture budget renders the group **blank**. Nearly every animated kit surface is a CanvasGroup driven by a `UIScale` pop — `AnimationHelper:presentCenterPanel`/`dismissCenterPanel`/`scalePop`/`scaleOut`/`slideOut`/`swingIn` (Shop, Gift, Admin, Music, Couple, Donation, Menu modals, Sticker, Carry, Dance panel, Paid Broadcast, Join Community), the GenericBroadcast / JoinGreeting / DonationNotification toasts, and the overhead nametag pop — so every frame of every open/close reallocated the group's texture (a UIScale on *any ancestor* resizes the group too). New **size-stable motion** (ADR 0005): `Shared/UI/GroupMotionPolicy.luau` (pure, lune-tested) + `Client/Utils/GroupMotion.luau` decide per target whether it rasterizes through a CanvasGroup; if so, scale pops become a `GroupTransparency` fade (group targets) or the existing dialog snap/settle travel (Frames wrapping a group), and toast/overhead scale keyframes collapse to their resting scale so `AbsoluteSize` never moves. Plain Frame trees keep the pop unchanged; existing `UIScale` instances are never mutated (mobile scaling lives there). Opt-out for buyers who prefer the legacy pop: `Config.UIMotion.CANVAS_GROUP_SIZE_STABLE = false` (engine `Config.luau`); a missing value defaults to stable.
- **Texture-budget guard for workspace CanvasGroups** (`Client/Services/CanvasGroupBudgetService.luau`, `Config.CanvasGroupBudget`, started from `Main.client` after image warm-up). Reproduced live on RUST: the dance panel's CanvasGroups went **blank with every property healthy** (Visible, `GroupTransparency = 0`, correct `AbsoluteSize`, all children opaque) — toggling `Visible` or `GroupTransparency` did *not* recover it, but disabling the 20 poster/board `SurfaceGui`s in Workspace (~48 MB of CanvasGroup textures allocated at spawn, 190–370 studs away) and re-toggling the panel rendered it instantly; re-enabling the posters afterwards kept everything rendering, i.e. a group that fails to allocate stays blank until big textures are released. The service disables any Workspace `SurfaceGui` that contains a CanvasGroup while its part is farther than `SURFACE_CULL_DISTANCE` (**250** studs, edge distance) from the camera and re-enables it within `DISTANCE - HYSTERESIS`; measured on RUST at the original 180 it released 17 of 20 at spawn and restored all six posters when the camera walked up to them. The default was raised 180 → 250 after the NIGHT ZONE QA pass, where the four leaderboard boards sit 194–219 studs from spawn and so read as blank to a player standing there — a board meant to be read is a different case from a decorative poster, and the far poster ring (246–318 studs) still gets released. It only ever culls GUIs it observed enabled, only restores GUIs it culled, and skips any SurfaceGui with attribute `ClubKitKeepSurfaceGui = true`. No kit code wrote `SurfaceGui.Enabled` before this, so nothing fights it. Disable with `Config.CanvasGroupBudget.ENABLED = false`.
- Place-level findings from the same diagnosis, not fixable in engine code (see `docs/releases/<next>/UPGRADE.md` when cut): RUST carries two identical poster sets (`Workspace.Top{1,2,3}{Cash,Robux}` + `hazastudioBoard.*`, ~48 MB of always-visible group textures at `PixelsPerStud = 63`), duplicate GUIs (`04-AdminPanel` + `04-AdminPanelv2`, three `DancePanelGUIWrapper*`), `ViewportFrame`s inside CanvasGroups (`AvatarContextMenu.MainWrapper`, `AdminPanel.AvatarPreview.IllustrationSection`), ~20 small CanvasGroups inside the DJ-tab `ScrollingFrame`, and 3-deep nested groups in the donation/greeting toasts. Each adds to the texture budget the blank symptom depends on.
- **Admin Hub "score edit" could not persist Robux — only preview it** (`Client/Controllers/AdminHubController.luau`). The manual-adjust sheet wired every Robux entry to `fakerobux` (`CMD_FAKE_ROBUX`), a donation *preview* command that plays the aura/notif but writes nothing (documented "no persist" in `CommandLibraryDomain`); the persistent path (`setrobux`/`CMD_ADD_ROBUX` → `runAddRobux` → `donationService:addManualRobuxAdjustment` → `repo:adjustRobuxTotal` → OrderedDataStore `IncrementAsync`) had a UI entry point for cash (`addcash`) but **none for Robux**, so a Robux "score edit" always vanished on rejoin. The "score edit" mode now carries a Cash/Robux currency toggle mirroring the cash "credit" sheet: Robux routes to `CMD_ADD_ROBUX` (persists), Cash to `CMD_ADD_CASH`, with the amount label and quick-chips (`DONATE_ROBUX_CHIPS` / `DONATE_IDR_CHIPS`) switching per currency. Both persistent adjustments stay owner-tier (`CommandLibraryDomain`: `setrobux` / `addcash` = `"owner"`) behind the Admin Hub's existing `canUseAdminPanel` gate — unchanged. Validated end-to-end through the real `CommandLibraryExecute` remote in the thebasic place: `/setrobux me 500` reached `runAddRobux`, `addManualRobuxAdjustment` returned ok, and the Robux total moved 42 → 542.

### Security
- **License hardening — server-side enforcement, leak forensics, and tamper response (ADR 0006).** The kit is sold per-buyer and its hand-made GUI is the product; a place was copied and the GUI lifted. Client-side theft cannot be *prevented* (the server hands the client the data), so this release makes a copy **non-functional, traceable, and takedown-ready** rather than pretending to be uncopyable. Six pillars:
  - **Fail-closed license gating** (`Server/Services/LicenseService.luau`). The old logic failed *open* on every non-success — a never-verified server, a blank `ApiUrl`, and a `universe_mismatch` 403 all enabled full features, so a fresh copy ran at full power. The server's answer is now classified: a **definitive denial** (403 `universe_mismatch`, or status `revoked`/`expired`/`unlicensed`) sets a **sticky hard-deny** (features off, and a later network blip cannot re-open it); a **previously-verified** server that goes unreachable keeps its last verdict for a **24 h grace** then closes; genuinely-undeterminable cases (timeout / DNS / no ApiUrl / Studio-no-secret) stay optimistic on purpose (we can't distinguish a flaky-network legit buyer from a firewalled thief — the VPS-side checks close that gap instead). The verdict is consumed at **three independent hot paths** — donations (`donation_http`), shop grants (`shop_grant`), and **admin/staff commands** (`CommandExecutionService:execute`, the single choke point for every raw + registered command; previously computed but never consumed) — so stripping one site misses the others.
  - **HttpService-required boot gate** (`Server/Main.server.luau`). Right after the boot log, before any system initialises, the server checks `HttpService.HttpEnabled`; if HTTP is **off the kit does not boot at all** (no services, no remotes; sets `Hazastudio_ClubKit:SetAttribute("BootHalted", "http_disabled")`). Thieves commonly disable HttpService to blind the phone-home — this turns that bypass into a dead kit. The client shows a full-screen `Client/UI/BootHaltedNotice.luau` overlay ("Club Kit paused — enable Allow HTTP Requests in Game Settings → Security, then rejoin") read from the replicated `BootHalted` attribute. **⚠ Buyers must enable HttpService or the kit will not run — see the upgrade guide.** Legit buyers already run with HTTP on for donations, so they are unaffected.
  - **Leak beacon** (`LicenseService.luau` + VPS backend). On a 403 `universe_mismatch` the server (HTTP is server-only, so exploit clients cannot read the URL) fires once to `POST /v2/beacon` with `universe_id`, `place_id`, `creator_id` (the infringing owner — the DMCA target), job id, kit version/build, and player count. The **VPS** forwards to a Discord webhook **from an allowed IP** — the only path that works, since Discord IP-blocks Roblox datacenters (the webhook the previous AC scripts reached for silently 403s in production). The VPS enriches the alert with the place name + owner display/@username resolved from the universe, and also sends a rate-limited **green "licensed" heartbeat** on `/v2/license/verify` (1×/24 h licensed, 1×/1 h unlicensed) so licensed *and* unlicensed places both surface. The webhook URL lives only in the VPS `.env`, never in the kit or repo.
  - **Per-buyer watermark + AI-reader notice** (`Shared/Notice.luau`, `KitProduct.luau` header, `ConsoleBanner.luau`). A visible proprietary/ownership notice (`© Hazastudio, licensed per buyer; copies are traced`) as DMCA ownership proof, an F9 console watermark printing the running `Universe <GameId>`, and a **benign** AI-reader notice that informs an AI assistant the code is proprietary and to advise verifying a license — a notice, not an attack or injection (static text can't tell a thief from a paying buyer using AI to customise, and must never sabotage a paying buyer). A true per-buyer *hidden* canary is a deferred Packager follow-up; until then a leaked copy is attributed by which buyer's secret it authenticates with.
  - **Live-exploiter response** (`Client/Services/SaveInstanceGuardService.luau`, `Server/Init/TamperGuard.luau`, `Config.AntiTamper`). A **behavioural** `saveinstance` detector (Studio-guarded `game:FindService("UGCValidationService")` probe — no name blacklist, so no innocent-GUI false positives) reports once to the server, which logs, **kicks**, and reports the player to the beacon (a distinct "exploit tool detected in a licensed place" Discord embed). **Client-brick is default OFF** (`BRICK_ON_DETECT = false`) and hard-gated to confirmed signals only — a false brick on a paying customer is worse than missing a thief; owners opt in once they trust the detector in their own place.
  - **Self-integrity tripwire** (`Server/Init/IntegrityTripwire.luau`). Runs at boot **independently** of the enforcement gate (its own HTTP post), so the most common strip — flipping `KitProduct.LicenseEnforcementEnabled = false`, which silences `LicenseService` — does not silence this: on a licensed place where enforcement was explicitly disabled it beacons `enforcement_disabled`. Deeper module-hash self-checks are a future iteration.
  - **Honest scope.** Enforcement that runs inside the copied place is a speed bump a determined thief who reads the whole server tree can strip; it stops the copy-paste reseller who never opens the code (most of them). The durable teeth are server-side — the VPS refusing an unlicensed universe plus **per-buyer rotatable secrets** (`POST /admin/games/{key}/rotate-secret` kills a leaked copy surgically) — and **DMCA**, armed by the watermark + beacon forensics. Deferred: the universe check on the *data* endpoints (a cross-cutting kit+backend change; the live `/license/verify` universe check + beacon + rotation already catch and kill the lazy copy) and the per-buyer hidden canary.

## [2.9.2] - 2026-08-26

### Fixed
- **Donation notification reliability v4 — clients always answer, and two notifs in one frame no longer merge** (`DonationService`, `DonationNotificationController`, `Types.DonationNotifPayload`). Client: a muted announce now acks `{skipped = "muted"}` before returning, and a missing notification GUI installs a minimal listener that replies `{skipped = "no_gui"}` plus a chat fallback — previously both returned silently *before the remote was even connected*, so the server saw no response at all and could not distinguish "player ignored it" from "delivery failed". Ack/display remotes are resolved via `WaitForChild` to close a first-player race. Server: `skipped` is forwarded to the delivery ledger, and DLQ reports now carry a reason (`left` | `timeout`) plus attempt count so the backend can tell a player-left from a real no-response failure. Payload gains `kind = "donation:<id>"` so `NetworkManager` frame coalescing can no longer merge two donation notifications aimed at the same target — the older one used to simply vanish.
- **Stale Rojo `init` twins are now swept on both install paths** — closing the root cause flagged (but not fixed) in 2.9.1. Rojo collapses `SomeFolder/init.luau` **into** the folder, so the resulting Script/ModuleScript already *is* the init; a surviving **child** named `init` is pre-Rojo cruft. It is never refreshed, because `SourceSyncCore.applyFile` only ever writes the collapsed instance (`RojoPathMap.parseRepoPath` maps `init.*` to the parent name correctly — the mapping was never the bug), so the twins freeze at whatever source they held when they were created and drift further from the real script with every update. The template place carried **15** such pairs; 11 were inert ModuleScripts (nothing requires `X.init`), but the four `EffectDonate/{BlackHole,LocalNuke,GreenHammer,Blossom}` twins are **LocalScripts, which auto-run** — their frozen copies still used the pre-move require path and threw `Utils is not a valid member of Folder "…Client.Effects"` on every client boot. Both entry points now sweep them: `SourceSyncCore.applyEngineUpdate` (existing buyer places self-heal on Update Engine) and `PackagerCore.unpack` (fresh installs self-heal even from an older `.rbxm`). The sweep scope is derived from `Manifest.SERVICE_ROOTS` rather than hardcoded, so it cannot drift from the manifest; that list covers the four `Hazastudio_ClubKit` subtrees **and** the vendored `ReplicatedStorage.Icon` (TopbarPlus), which is kit-owned — it ships in the pack and is listed in `ENGINE_SOURCE_PREFIXES`. Anything outside those roots (buyer folders, genuinely third-party systems) is never touched. Template place cleaned (15 removed, 0 left anywhere in the place); verified by playtest: `Utils is not a valid member` count went 4+ → **0**, topbar intact (11 icons, zero Icon-related errors).

### Added
- **Auto Dance** (`Client/Controllers/AutoDanceController.luau` + `Config.AutoDance`, topbar toggle). Ported from the legacy HIERAPOLIS `AnimationsUI` "AUTO" button: while enabled it shuffles a random dance emote every 3–6 seconds. Client-only by construction — each cycle goes through `SyncController:onEmoteSelected`, so the server only ever sees an ordinary emote selection, identical to a manual click. No new remote, no server state, nothing persisted (matching legacy, where the toggle resets on rejoin). Two legacy details were kept deliberately because they carry the feel: the **randomised** interval rather than a fixed one, and the **never-repeat-the-current-animation** rule. The no-repeat rule matters more in Club Kit than it did in legacy — `onEmoteSelected` toggles an emote *off* when re-selected while playing, so a repeat would silently stop the dance instead of continuing it. Button is temporarily a TopbarPlus pill on the **left** strip at `Config.AutoDance.TOPBAR_ORDER = 4`, immediately after "Lead Dance" (order 3), and reuses the dance panel button's own artwork (`rbxassetid://104629759158002`) so the dance controls read as one cluster. Placement is pending a proper home inside the dance panel UI.
- **Auto Dance ↔ dance sync interaction, handled in both directions.** Enabling auto drops an active leader sync (`UNSYNC_ON_ENABLE`), and — the direction that actually bites — starting a sync while auto is running makes auto **switch itself off** rather than fight it. Without that second rule the shuffle loop keeps issuing its own emote picks, and `SyncService:onAnimationStart` silently detaches the player from their leader ("become our own root", `SyncService.luau:937`). That detach path fires **no** notification, so the follower's client keeps a stale `isSyncing = true`; since `onEmoteSelected`'s toggle-off branch is gated on `not state.isSyncing`, `STOP_ON_DISABLE` would then *replay* the emote instead of stopping it — i.e. the Auto button would appear stuck on. Auto now yields to sync via an `isSyncing` store subscription plus a guard inside the loop tick (covers the gap between the sync landing and the subscription firing), and yields **without** issuing the stop-emote so the sync system keeps ownership of the animation.

## [2.9.1] - 2026-08-26

### Fixed
- **Packager shipped a `ClubKitConfig` that fails to compile** (`PackagerCore.blankTemplateConfigSource`). The blank-template regex matched only the `AdminUserIds` table literal (`AdminUserIds%s*=%s*{[^}]*}`) and replaced it with an already-annotated `{} :: { [number]: boolean }`. Once the buyer/template source carried that annotation itself — as the current template place does, written across three lines — the original trailing `:: { [number]: boolean }` survived the substitution and the result chained two type assertions (`{} :: T :: T`), which is a **Luau syntax error**: every fresh install from the pack would have loaded a dead config module. The substitution now consumes an existing annotation when one is present, and is idempotent. Verified in Studio: the old form fails to compile, the new form compiles and is byte-stable when applied twice.
- **Donation-effect scripts (`EffectDonate/{BlackHole,LocalNuke,GreenHammer,Blossom}`) could ship with a duplicate nested `init` copy of themselves**, one folder deeper than the real script — its `script.Parent.Parent.Parent.Utils` require then resolved to `Client.Effects` instead of `Client`, throwing `Utils is not a valid member of Folder` on boot and leaving the duplicate half-run. Root cause is in the packaging/export pipeline (the checked-in `src/` source was never duplicated), so this only ever shipped inside already-packaged/unpacked buyer places, not from a fresh Rojo sync. No source fix landed this release — flagging so the master "thebasic" export gets the stray `init` children stripped before the next `.rbxm` is cut, or every future unpack reintroduces it.

### Added
- **`Config.PanelZoom` toggle** (`Shared/Constants/Config.luau`) for the shared camera FOV zoom-in effect on modal panel open/close (`AnimationHelper:_tweenCameraZoom`, wired into `presentBackdropEffects`/`dismissBackdropEffects` and used by every panel that calls them: Shop, Gift, Admin Panel, Admin Hub, Music Player, Couple, Donation, Avatar profile card, Top Menu, Paid Broadcast, Join Community prompt). Previously always-on with no way to disable, unlike the sibling `Config.PanelBlur` which already had `ENABLED`. Defaults to `false` (off).
- **SyncBhms add-on: Lead Dance topbar restored** (`extras/place-packs/SyncBhms/bridge/SyncBhmsLeadDanceBridge.client.luau` + `SyncBhmsLeadDanceFollowerSync.server.luau`, optional install). Reuses Club Kit's own `SyncLeadTopbarController` module but routes requests through `SyncBhmsAcmBridge` instead of `SyncController`, so the topbar "Lead Dance" icon works under `Features.LegacySyncBhms = true` (where Club Kit's own dance panel/`SyncService` is disabled). The dropdown is now dynamic — mirrors BHMS's own follower graph (`Character.Syncing`, `SyncServer/Modules/SyncManager.luau`) onto `Character.IsLeader`/`FollowerCount` — instead of just listing everyone holding the `LeadDance` role.

## [2.9.0] - 2026-08-25

### Fixed
- **MultiOption / segmented settings rows (e.g. Graphics "Overall Quality") were completely dead after the GUI wrappers were converted from CanvasGroup to plain Frame.** `MenuSettingsCore.resolveSegmentedButtonFrame` located the option-button container by class — the row's only `CanvasGroup` — falling back to `FindFirstChildWhichIsA("Frame")`. Once converted, the row holds *two* same-named `Frame` children (label frame + options frame), so the fallback picked the **first** one (the label), found no buttons inside it, and bailed out early: option labels were never set (rendering as placeholder "Head" text) and no click handlers were ever wired. It now identifies the container by what it actually holds — the descendant with the most direct `TextButton` children — which is immune to both the class change and child ordering.
- **GenericBroadcast announcements stopped showing after the notification GUI was redesigned from CanvasGroup to a plain Frame (diagnosed on KASTA).** `GenericBroadcastController` required the `GenericBroadcast` wrapper to strictly be a `CanvasGroup`; once a buyer redesign changed it to a `Frame`, the strict check failed and the whole announcement system silently no-opped (`/announce`, paid broadcasts). The wrapper is only ever used for `Position`/`AnchorPoint`/`Visible`/`GetChildren`, so it now accepts any `GuiObject` — same compat pattern already used for `AdminPanelUI`'s CanvasGroup→Frame redesign.
- **Vote-skip window closed after ~1 second instead of 15.** `Config.VOTE_SKIP_DURATION` was set to `1` (present since the earliest tracked history) while both the server (`MusicSession.luau`) and client (`MusicPlayerUIBinder.luau`) fall back to `15` whenever the config value is missing — so the vote modal's own countdown assumed 15s while the server closed the session after 1s, making it look like the vote UI "closes itself" almost immediately. Set `VOTE_SKIP_DURATION = 15` to match the intended fallback.
- **AFK auto-rejoin could only ever make ONE attempt per idle streak, so a single failed rejoin guaranteed the 20-minute idle disconnect.** The server charged a rate token (1 per 900s) *before* attempting the teleport, while the whole margin between the 17-minute trigger and the 20-minute kick was 171 seconds — every retry inside that window came back `denied_rate_limited` with a ~900s hint. A token now opens one AFK **cycle** (idle streak) rather than one request: every rung of the new escalation ladder reuses it, and only a *new* cycle needs a fresh token (abuse protection verified intact). Rate window trimmed 900s → 600s so a fresh streak always finds a token.
- **AFK retry state leaked across idle streaks and could dead-end a session permanently.** Reset was wired only to `UserInputService.InputBegan`, but mouse movement — which *does* reset Roblox's idle clock — arrives via `InputChanged` and never fires `InputBegan` (measured). A streak that exhausted its 3 attempts, or parked a ~15-minute retry timestamp, carried that state into the next streak and silently sent zero requests. State is now reset from the engine's own signal: any drop in `Player.Idled`'s `idleTime` means a new streak.
- **`afkGuardService:onPlayerRemoving` never ran** (pre-existing). `afkGuardService` was declared *below* the `Players.PlayerRemoving` handler that closes over it, so the closure captured a nil global and the guard `if afkGuardService and ...` was always false — leaking in-flight teleport entries. Forward-declared alongside `sessionCommandService` / `commandExecutionService`, matching the existing convention.
- **A teleport that never happened was reported as success.** `safeTeleportAsync` returned success whenever no `TeleportInitFailed` arrived within 10s, even with the player still in the server — burning the attempt while the player rode the idle clock into a disconnect. The AFK path now requires a confirmed departure (`requireConfirmedExit`); manual `/rejoin` keeps the optimistic behaviour so a merely-slow teleport does not show a false failure.
- **A notification failure could abort the rejoin request.** The `Idled` handler incremented the attempt counter, then called `NotifService` unprotected, and only pcall-wrapped the `FireServer` after it — so a throw inside the notification centre (a GUI buyers actively reshape) consumed the attempt without ever sending the request. The remote is now fired first and all notifications are pcall-wrapped.

### Changed
- **Amendment to ADR 0004 — unlinked donor nicknames on the cash workspace board are now shown raw, unfiltered** (`DonationService.getWorkspaceSaweriaLeaderboard` / `getWorkspaceDailySaweriaLeaderboard`). The broadcast text filter was turning valid Indonesian donor nicknames into `####` / unrelated censored words whenever the filter author was unresolvable — worse UX than the moderation risk, for a low-traffic surface. Owner-accepted tradeoff for this one surface only; everything else ADR 0004 covers (donation messages, bio, `/status`, music names, `communityName`, linked-donor display) is still filtered exactly as before. `filteredProviderDisplayName` removed; the two call sites now use `cleanOptionalMessage` (trim + length clamp only).
- **AFK rejoin now escalates on a 4-rung ladder instead of a single 17-minute attempt** (`Config.AfkGuard.REJOIN_LADDER`): same-server at 13:00 and 14:30, then any-server at 16:00 and 17:30, with a hard stop at 19:00. Timing is derived from measured `Player.Idled` behaviour (first fire ~129s, then exactly every 30s), so rungs land at ~13:09 / 14:39 / 16:09 / 17:39 — four independent chances with ~2m51s of margin left after the last, versus one attempt and no margin before.
- Per-request server-side retry (`MAX_RETRY` + 30s sleep + new-server fallback) removed: it blocked the in-flight guard for ~60s and starved the very retries it was meant to provide. One request = one attempt; the ladder owns retry timing. `MAX_RETRY`, `RETRY_DELAY_SEC`, `CLIENT_RETRY_BACKOFF_SEC` and `MAX_CLIENT_ATTEMPTS` are retained as deprecated no-ops so existing buyer configs keep loading.

### Added
- **UI image warm-up (`Client/Services/ImagePreloadService.luau`).** Panel artwork is now warmed during the loading screen — a window that previously warmed only dance animations — in three tiers: topbar/branding chrome, then first-open panel icons, then everything authored into the GUIs (swept from PlayerGui, since StarterGui lives outside the Rojo tree and has no code-side manifest). Measured: a cold image costs ~0.53–0.56s between assignment and `IsLoaded`, which is exactly the blank-then-pop on first open; warming drops the same display to ~0.05–0.06s. Two measured facts shape the implementation and should not be "simplified" away: `PreloadAsync` with a **string id is a no-op for images** (only the instance form works), and an **unparented** ImageLabel preloads fine (so warming costs no render work). Batches are throttled on `ContentProvider.RequestQueueSize` and run under a watchdog, because `PreloadAsync` hangs indefinitely on assets the backend never serves.
- **`Client/Utils/ImageSwap.luau`** — assigns images without ever showing a blank frame, replacing the `.Image = ""` → async-fill pattern that guarantees a gap by construction. Keeps the previous image or a placeholder until the new content is confirmed decoded, then cross-fades; generation-guarded so a stale fetch can't land on a recycled list row.
- `Config.ImagePreload` for tuning. `KEEP_RESIDENT` defaults to **false**: the texture-eviction claim behind it is community lore rather than documented behaviour and could not be reproduced, so the memory cost stays opt-in.
- **Grouped-list corner rounding for settings/profile rows** (`Client/Utils/GroupedRowCornerUtil.luau`). Within a `SectionContentWrapper`, the first *visible* row gets rounded top corners, the last gets rounded bottom, middle rows are square, and a lone visible row is rounded on all four — using `UICorner`'s per-corner radius properties. Conditionally hidden rows are excluded, so the group re-rounds correctly as rows show/hide. Wired into `SettingsTabBinder` (on every conditional-visibility refresh) and `ProfileTabBinder` (on every profile patch).
- **AFK leak metric.** `afk_cycle_opened` / `afk_rejoin_confirmed` / `afk_cycle_closed_rejoined` / `afk_cycle_lost_player` make it possible to distinguish "left because the rejoin worked" from "left because Roblox idle-kicked them" — previously indistinguishable, which is why the failure was only ever visible as user complaints.

## [2.8.9] - 2026-08-23

### Fixed
- **Spender Team names in the Roblox PlayerList now follow the renamed roles.** The buyer-facing `ClubKitConfig.SpenderRoles` still carried the old labels (`Top Rupiah Spender` / `Top Robux Donator`), which overrode `Roles.luau` — so the Team column showed `TOP DONOR` / `TOP SUPPORTER` even after the v2.8.8 role rename. Updated the buyer config labels/chatTags/toolFolders/specialRank to **Top Cash Spender** / **Top Robux Spender**, so the PlayerList teams now read `TOP CASH SPENDER` / `TOP ROBUX SPENDER`.

## [2.8.8] - 2026-08-23

### Changed
- **PlayerList stat titles reverted to `Cash` / `Robux`** (v2.8.7 renamed them by mistake — the "Spender" naming belongs on roles, not the stat columns).
- **Spender team/role names clarified:** `Top Rupiah Spender` → **Top Cash Spender**, `Top Robux Donator` → **Top Robux Spender** — matching chat tags, special rank text and tool folders, all in `Roles.luau` + `ClubKitConfigSchema.luau`. Legacy aliases kept (e.g. `/setrole "top rupiah spender"` still resolves), and new-name aliases added.

## [2.8.7] - 2026-08-23

### Changed
- **Donation rank chips are now capped at the top 20** (`Config.Overhead.DONATION_CHIP_MAX_RANK = 20`). Donors ranked 1–20 show the ranked chip (`#N RUPIAH` / `#N ROBUX`) as before; donors beyond the top 20 get a single **"SUPPORTER"** chip (reusing the Rupiah wrapper, no rank number) instead of a ranked chip. A donor who already has a ranked chip in either category shows no SUPPORTER chip.
- **PlayerList stat titles clarified:** `Cash` → **Top Cash Spender**, `Robux` → **Top Robux Spender** (`Config.PlayerList.CASH_STAT_NAME` / `ROBUX_STAT_NAME`).

### Notes
- One "SUPPORTER" chip max per player even when they donate to both categories without ranking top-20 in either — the ranked chip always wins when present.

## [2.8.6] - 2026-08-23

### Changed
- **Overhead donation rank chips now show for EVERY donor, not just the top-10.** New `Config.Overhead.DONATION_CHIP_MAX_RANK` (default `0` = unlimited; set a number to cap) governs the `#N RUPIAH` / `#N ROBUX` chips, decoupled from `SpenderRoles.*.MaxRank`. Top-Spender **roles**, tool grants, chat tags, playerlist spender colors and join greetings all keep their top-10 semantics — they re-check MaxRank independently, verified live (rank-27 donor gets a chip, role stays Guest).
- **Cash rank resolution fallback for donors beyond the workspace leaderboard (top-50).** When the workspace leaderboard misses, the chip rank now falls back to `getPlayerCashStats` (backend full rank over all donors, 45s positive cache + exponential negative cache) — so donor #51+ still resolves a chip while online.
- Live leaderboard diff and manual cash adjust now track ranks up to 100 (was 10), so the persisted ranks that feed chips stay current for the top 100; donors ranked >100 get their chip via the fallback above. Gate intentionally capped at 100 (the polled leaderboard's fetch ceiling) to bound DataStore write churn.

## [2.8.5] - 2026-08-23

### Added
- **Cross-server donor cash sync.** After a donation is applied (backend `total_after`), the server publishes the donor's ABSOLUTE total on a dedicated MessagingService topic; every other server in the game applies it instantly to their donor cache, overhead cache, and the player's leaderstat Cash if online. Payloads are idempotent and drop-safe (monotonic apply — stale/duplicate/lower totals are ignored; message drops fall back to the existing 45s TTL cache path). Token-bucket guarded (~8/s) so donation storms cannot approach the MessagingService per-game publish cap. Gated by `Config.Donation.CROSS_SERVER_CASH_SYNC_ENABLED`.
- **Boot leaderboard kick (delayed 30s).** A fresh server now pulls the backend leaderboard at ~30s instead of waiting up to 120-150s for the first periodic job tick, so in-map cash boards fill within half a minute. Delayed past the cold-start join-load window — the original immediate kick caused a second DataStore burst and StandardRead throttling; 30s clears it. Single extra HTTP call per server lifetime.
- **Join-time cash fetch retry.** A failed first cash fetch at join no longer strands the player at Cash=0 for the failure-cache window: one delayed retry (3s) runs before the exponential negative-cache path takes over.

### Changed
- **Donation-triggered leaderboard refresh debounce 10s → 4s** (`Config.Donation.LEADERBOARD_REFRESH_DEBOUNCE`, was hardcoded). 4s is the effective floor — the downstream rebuild coalesce (5s) and broadcast min-interval (3s) dominate anything lower. Worst case during a donation storm: 15 HTTP/min, well inside budget.
- **Donor-profile failure cache is now exponential** (`Config.Donation.DONOR_FAILURE_BACKOFF_STEPS = {5,10,30,120}`, was flat 120s): transient backend hiccups recover in 5s instead of sticking joiners at Cash=0 for two minutes; real outages still escalate to the full cooldown.

### Fixed
- **Stale-overwrite race in the donor cash cache.** `fetchDonorCashProfile` and `getPlayerCashStats` wrote `donorCashCache` unconditionally — an in-flight HTTP/leaderboard result issued *before* a donation landed could resolve *after* the instant event write and clobber it with a stale total. All writes now go through a single guarded helper: an event-written entry (<10s old) is never overwritten by a lower non-event total (monotonic max). Event writes also carry forward the prior rank instead of blanking it.
- **Instant leaderstat write is now monotonic** (never lowers an already-higher value).

## [2.8.4] - 2026-08-23

### Fixed
- **Community names on the donation leaderboard no longer pass through Roblox text filtering.** Community names come from the player's Roblox group list (platform-moderated at source, same as usernames/display names), so re-filtering was redundant — and whenever the filter author was unresolvable (group-owned place + owner offline) valid group names were stored as `#####`. `writeMetadata` now stores the group name as-is (still length/clamp-sanitized).
- **Self-heal for already-hashed community names.** Board builds detect stored `#####` names, re-resolve the real group name once via `GroupService:GetGroupInfoAsync`, and persist the clean value — places with legacy hashed rows clean themselves on the next board rebuild, no new donation needed.

## [2.8.3] - 2026-08-23

### Fixed
- **First-time donor notifications lost (`failed_resolve`) with "attempt to call a nil value".** The Lapis-2 donor-total fallback called `fetchDonorCashProfile()` at a call site **above** its `local function` definition inside `createDonationService`. With no forward declaration, the earlier reference resolved to a nil global and the phase-2 resolve worker crashed for any donor missing from the cached leaderboard (first-ever donations, dashboard test names) — the donation silently went to `failed_resolve` instead of showing. The function is now forward-declared before `_pollNotifications` and assigned later in the scope. Verified: a webhook donation for a brand-new donor resolves and displays end-to-end.
- **Game-data API base URL now points at the self-hosted VPS** (`https://api.hazastudio.id/social`) instead of the retired Cloudflare worker — overhead group-rank / community lookups keep working after the migration.

## [2.8.2] - 2026-08-22

### Fixed
- **Provider donation messages always censored to `#####` ("pager semua").** Roblox `FilterStringAsync` requires the filter author to be **connected to the current server** (it errors *"sender must be connected to the current server"* otherwise). On group-owned places where the donor is offline and the game owner is also offline, the previous fallback (`userId = 1`, then the owner) was never a connected player, so every filter call failed and `censoredMessageFallback` replaced every donor name/message with hashes. `DonationService.resolveTextFilterUserId()` now falls back to **any currently-online player** as the broadcast author when the donor is not connected (and returns `nil` only when nobody is online). Donation messages and names now render as typed, still fully Roblox-filtered. Verified on a group-owned place: `filterForBroadcast` returns the clean string and the notification renders the message intact.

## [2.8.0] - 2026-08-21

Avatar Context Menu v2 redesign (buyer-toggleable) + camera zoom/blur backdrop; double-avatar fix; background blur enabled globally for panel backdrops.

### Added
- **Avatar Context Menu v2 (`Features.AvatarContextMenuV2`).** Buyers can now pick between the **legacy v1** design (3D rotating avatar `ViewportFrame`, GUI `AvatarContextMenu`) and the **redesigned v2** (static full-body profile picture via `Players:GetUserThumbnailAsync` `AvatarThumbnail`, GUI `AvatarContextMenuV2`). New buyer flag `ClubKitConfig.Features.AvatarContextMenuV2` (default `false` = v1, fully backward compatible — existing places keep the 3D avatar). Surfaced in the plugin Config Features panel as "Avatar context menu v2 (redesign)". `AvatarContextUI` picks the GUI by the flag, disables the other variant so both never render at once, and falls back to whichever ACM GUI exists if the buyer kept only one. Both variants share the same open/close/data pipeline and public API, so `AvatarContextController` needed no changes.
- **Camera zoom + background blur backdrop (v2).** Opening the v2 panel now tweens the camera FOV in and fades in a `BlurEffect` backdrop, restored on close — the same backdrop language as TopMenu/Settings/Music via `AnimationHelper.presentBackdropEffects` / `dismissBackdropEffects`. New config `Config.AvatarContext.BACKDROP_BLUR_NAME = "AvatarContextBlur"`. Backdrop state is reset on `resetVisualState()` so a re-load cycle cannot desync the camera/blur on the next close. Backdrop only applies to v2; legacy v1 keeps the classic flat backdrop.
- **Background blur enabled globally (`Config.PanelBlur.ENABLED = true`).** The shared frosted `BlurEffect` backdrop used by shop/gift/couple/donation/admin/music/top-menu modals is now on by default (camera zoom always worked; the Lighting blur was previously gated off). Affects every panel using the shared backdrop — set up per-place via `ClientSettings.BackgroundBlur` to opt out.

### Fixed
- **Double avatar in the 3D viewport (v1).** A second `AvatarViewport3D` bound to the same `ViewportFrame` (or a superseded in-flight `load()`) could leave an orphan `WorldModel` behind, rendering a duplicate avatar stacked under the new one. `AvatarViewport3D.load()` and `cleanup()` now destroy **every** `WorldModel` child of the viewport (via a shared `_destroyAllWorldModels()` helper), not just the most recently tracked one. Verified: repeated open/close cycles leave exactly one `WorldModel` + one avatar model.
- **Avatar/profile picture hidden for Studio test players.** Studio multiplayer test players use **negative** userIds (`-1`, `-2`, …). The old `userId <= 0` guard treated them as "no target" and hid the avatar; now only `userId == 0` means "no target" so test players render correctly (`GetUserThumbnailAsync` and the 3D pool both resolve negative ids fine).

## [2.7.1] - 2026-08-20

Couple chat tag toggle + group-owner text-filter fix.

### Added
- **Couple chat tag toggle (`Features.ShowCoupleChatTag`).** Buyers can now hide the couple chat tag (💕 partner) shown in the General/chat prefix without disabling the couple system. New buyer config flag `ClubKitConfig.Features.ShowCoupleChatTag` (default `true`) → resolved to `Config.Couple.SHOW_CHAT_TAG` and read by the client `ChatTagsController`. `false` hides the tag in chat only — the couple system, overhead couple name, and announcements are unaffected. Default `true` keeps all existing places unchanged (fully backward compatible); surfaced in the plugin Config Features panel as "Couple chat tag (General)".

### Fixed
- **Community / provider-donor names showing as `#####` on group-owned places.** On a group-owned place `game.CreatorId` is a **group id, not a user id**, so the text filter (`FilterStringAsync` author) failed and every community name on the donation leaderboard (and every unlinked Saweria/Bagibagi donor name on workspace boards) was stored as `#####`. New `TextFilterUtil.resolveFilterAuthorUserId()` resolves a valid filter-author userId — the creator for user-owned places, or the **group owner** (via `GroupService:GetGroupInfoAsync`, memoized) for group-owned places — and both call sites (`DonationLeaderboardRepository` community metadata, `DonationService` provider-donor display names) now use it. User-owned places are unchanged; DataStore keys are untouched; names already stored as `#####` re-render correctly the next time a donation rewrites that community's metadata.

## [2.7.0] - 2026-08-19

Donation notification reliability (enterprise-grade, evidence-tested) + per-role announce cooldown.

### Added
- **Per-role-group `/announce` cooldown, buyer-configurable.** New `ClubKitConfig.Announcement.RateLimits` lets buyers set a separate announce budget for each group — `Leadership` (Staff+), `Spender` (Royale/Top/Spender), `Member` (membership ≥ MinMembership), `Player` (everyone else). Example: `RateLimits = { Leadership = { Max = 20, Window = 60 }, Player = { Max = 1, Window = 120 } }`. Partial override is fill-forwarded per group. Buyer intent is detected from the raw `ClubKitConfig` (not the fill-forwarded state), so a buyer who never sets `RateLimits` keeps the legacy single budget (`RATE_MAX`/`RATE_WINDOW`) — fully backward compatible. One shared resolver (`AnnouncementRateLimitDomain`) serves both the `/announce` chat command and the external-admin facade, so Adonis/Kohl's announces respect the same per-role budgets.

- **Enterprise-grade donation notification reliability (opt-in).** New `ClubKitConfig.Donation.ReliabilityV2 = true` enables an end-to-end delivery ledger so a cash donation notification is never silently lost between the payment webhook and a player's screen:
  - **Worker v3 API** (`tools/donation-api`): durable `notification_deliveries` + `delivery_acks` D1 tables, `POST /game/:key/v3/deliveries` (register recipients), `POST /game/:key/v3/delivery-ack` (batch ack), `GET /game/:key/v3/delivery-status` (retry view), `POST /game/:key/v3/delivery-dlq` (exhausted-retry report), plus admin audit endpoints `GET /admin/games/:key/delivery-report` and `GET /admin/games/:key/dlq`.
  - **Server ack tracking + retry** (`DonationService`): every fired notification is tracked per online player; a client ack removes it, no ack within `NOTIF_ACK_RETRY_AFTER_SECS` (default 8s) re-fires to that player, and after `NOTIF_ACK_MAX_ATTEMPTS` (default 20) the delivery lands in the Worker DLQ for audit — never dropped silently.
  - **Client ack on enqueue** (`DonationNotificationController`): the client fires `DonationNotifAck` with the `donationId` the moment a notification is safely queued (delivery guarantee) — not after the display animation, which would race the retry window under burst.
  - Default off (`ReliabilityV2 = false`); existing buyers keep legacy fire-and-forget until they opt in. Fully additive — no breaking changes to v1/v2 endpoints or buyer config.
  - **Hardened by evidence-based load testing** (30- and 50-donation bursts injected into D1, measured end-to-end against the live v3 ledger): client now acks on **enqueue** (delivery guarantee) rather than after the display animation — a burst drains over minutes, so display-timing-based ack was causing false-positive DLQ marks; client added an idempotent retry-dedup guard by `donationId` (a server retry to an already-queued/showing notification is a no-op, so bursts can't flood the queue); retry window raised to `NOTIF_ACK_RETRY_AFTER_SECS=8` × `NOTIF_ACK_MAX_ATTEMPTS=20` (~160s) to comfortably cover worst-case burst drain; fixed a forward-reference crash in `handleNotifAck` and a nil-guard crash in the client retry-dedup path — both only surfaced under real burst load.
  - **Resolve-failure visibility (no more silent loss).** A donation whose phase-2 resolve crashes (or yields nothing displayable) previously vanished without a trace — it never reached `fireCashDonationPresentation`, so it never entered the delivery ledger. These are now reported to the ledger with a `roblox_user_id=0` sentinel row and `status='failed_resolve'`, surfaced in the admin DLQ endpoint alongside per-user retry exhaustion. Every donation is now accounted for: `acked` (delivered), `dlq` (client unreachable after retries), or `failed_resolve` (server-side processing error) — never silently dropped.
  - **No more client queue eviction (ever).** The old lowest-amount eviction silently discarded small donations when the queue filled — a direct violation of the no-silent-loss guarantee. Eviction is removed entirely; the queue is now a soft cap with backlog display scaling plus a hard floor (`NOTIF_BACKLOG_HARD_FLOOR_SECS`, default 2s) so a deep burst drains in bounded time without ever dropping a paid donation.
  - **Ack race fix (ack can beat registration).** Under burst load the client's enqueue-ack can reach the Worker before the server's `deliveries` registration round-trip; the ack endpoint is now an UPSERT (was UPDATE), so the delivery lands `acked` instead of being stuck `sent` forever. Verified: 60/60 delivered+acked, 0 failures, on a 60-donation burst (2× the incident size).
- **Notification queue capacity raised** `NOTIF_MAX_QUEUE` 20 → 100 so burst donation waves (e.g. 12 donations in one hour) no longer force client-side eviction of small-amount notifications.

## [2.6.7] - 2026-08-18

Text-filtering compliance hardening (Roblox ToS) — all player-supplied and external free-text surfaces now pass through Roblox text filtering before they are stored or shown to other players. Full policy: `docs/adr/0004-text-filtering-policy.md`.

### Fixed
- **`/status` text above heads was never filtered.** Status (and bio) text set via `/status`, `/setbio`, the profile menu, or the command library is now filtered at write (`ProfileCommandService`); the overhead billboard and profile popups only ever render filtered text. A rejected/failed filter returns the "Roblox could not review that text" error instead of saving.
- **Profile bio/status re-filter used the wrong author.** The avatar-context popup filtered with the *viewer's* userId as author (wrong age context); it now filters with the *writer's* userId per viewer.
- **External donor nicknames on workspace boards.** Saweria/Bagibagi nicknames (typed on the external payment platform — not Roblox-moderated) shown for unlinked donors on the donation boards are now filtered (memoized per name so board refreshes don't burn filter quota). On filter failure a `####` mask is shown — raw external text is never displayed.
- **Music manage names/creators.** Admin/DJ-supplied track names, track creators, and playlist names are now filtered before storing; a failed filter rejects the edit with `filter_failed`.
- **Community board name from the donation worker.** `communityName` ingested from the worker API is now filtered (author = place owner) before the DataStore write.
- **Robux donation name no longer falls back to the raw display name** when filtering fails — falls back to the platform-moderated username instead.

### Changed
- **New canonical filter module `TextFilterUtil`** (`Shared/Utils/TextFilterUtil.luau`). The 8 previously duplicated inline `TextService` filter implementations (donations, shop, broadcast, crowd, admin title, sign tools, profile menu, avatar context) now all route through one module with consistent trim/clamp/retry semantics. No behavior change for already-compliant surfaces beyond unified retry (sign tools intentionally stay single-attempt to protect the filter quota). Roblox DisplayNames remain intentionally un-filtered (platform-moderated — ADR 0004 D1).

## [2.6.6] - 2026-08-18

Unlimited level cap + donation cinematic push-in.

### Changed
- **Levels are now unlimited (was capped at 100).** `Config.Level.MAX_LEVEL` default changed `100` → `0` (`0` = no cap). Players past level 100 now keep earning XP and leveling up; existing capped players resume leveling on their next XP gain (their stored XP was held at `needed-1`, so the very next gain triggers the level-up loop). `/setlevel` admin command now accepts any level ≥ 1. Note for buyers who want the old behavior: set `MAX_LEVEL` back to `100` (or any cap) — the cap logic itself is unchanged and was verified working before switching the default.
- **Donation cinematic now zooms in.** The donation camera cinematic (triggered for tiers with `cameraDuration > 0` — i.e. ≥500 R$ / ≥50rb cash) previously used a fixed-FOV orbit (`DonationOrbit`). It now uses a new `DonationPushIn` mode: a pure dolly zoom — the camera holds its framing in front of the donor (no orbit) while the FOV eases 54 → 42 over the first few seconds, then holds. `DonationPushIn` is also registered in the Cinematic Dock movement list so admins can select it manually.

## [2.6.5] - 2026-08-17

Donation webhook fix + optional read-only music library mode.

### Added
- **Read-only music library mode** — `ClubKitConfig.Features.MusicReadOnlyLibrary = true` runs the music library with **no DataStore at all** (fast boot, no DataStore errors). Boot skips `MusicRepository:loadAll`, seeds the library straight from the `MusicCatalog` script into memory, and never starts the sync poll loop; all DataStore writes become no-ops via a read-only guard in `MusicRepository._setAsync` that still lets mutators commit to memory. In-game song requests keep working — the request-history playlist lives in memory and is lost on restart. The Manage tab is hidden for every rank (`MusicService:isManageAllowed` returns false, which also server-blocks the manage remotes; the DJ tab hides too since it shares the same manage-permission gate). Default stays `false` (editable mode: DataStore read/write, in-game edits persist), so existing buyers are unaffected. Playlists/tracks previously saved in DataStore are **not deleted** while read-only is on — they just don't appear, and show up again when switching back to editable. Toggle also listed in the Packager Config panel ("Read-only music library (no DataStore)").

### Fixed
- **Real (external) cash donations no longer show "Total: First donation" on the notif chip and now update the Cash leaderstat.** Two layers, both on the webhook path (manual `/fakecash` / Admin Hub were unaffected, which is why they always looked correct): (1) `getPlayerCashStats` no longer refuses the donor-profile API call for a player who isn't yet a "known donor" — that local set only tracks donors seen *this server session*, so anyone who donated while the server was offline was kept at `Cash=0` forever even though the backend had their history. The call is still cheap: true non-donors are negative-cached (120s failure cache), and hidden users still never hit HTTP. (2) When a donation notification arrives before the leaderboard cache includes the donor, the notif now falls back to the donor-profile API for `totalDonationAmount` instead of firing with `nil` → the chip shows the donor's real total. `Config.Donation.SKIP_API_FOR_UNKNOWN_DONORS` is now a legacy no-op (kept so older configs don't error).

## [2.6.4] - 2026-08-16

Neutral "Cash" currency option.

### Added
- **`Donation.Currency = "CASH"`** — a third cash-display option with neutral "Cash" labels (`Top Cash Spender` / `Top Cash` / chip suffix `CASH`) for venues that don't want to name Rupiah or Peso. Display-only like the others; amounts are not converted. Also added to the Packager Donations currency dropdown (`Cash (neutral)`).

## [2.6.3] - 2026-08-16

Admin Hub UX tweaks.

### Changed
- **Admin Hub phone scale 0.44 → 0.5** — `Admin.HUB_GUI_SCALE_MOBILE` (and the matching `MobileScale.ADMIN_HUB_GUI` fallback) raised so the Admin Hub is less cramped on phone layouts.
- **Admin Hub announce box no longer pre-fills "Welcome to the club!"** — the Announce sheet now opens empty so the placeholder ("Say something to the server…") shows instead of a default message you have to clear first.

## [2.6.2] - 2026-08-16

Seamless AFK rejoin (no loading/prompt interruptions) + solo dancers converge to the top leader.

### Added
- **Seamless AFK rejoin** — an AFK auto-rejoin now lands without replaying the first-join interruptions. New `Shared/Session/RejoinMode.luau` reads the `afkRejoin` flag from the teleport data once (client-side, previously server-only; reads both `GetJoinData().TeleportData` and `GetLocalPlayerTeleportData()`) and three consumers branch on it: `LoadingBootstrap` skips the loading screen entirely on rejoin (waits for the Session/RejoinMode module to replicate before deciding, so the skip is not lost to a replication race), `JoinCommunityPromptController.tryPromptAfterGameplay` never shows the join modal on rejoin (it still shows on a normal join for non-members), and `Main.client` bypasses the music-engine start delay and forces dance warmup to run immediately so `SyncService.restoreAfterAfkRejoin` re-syncs to the last dance/leader without the usual post-gameplay defer. Normal joins are unaffected (loading screen, prompt, and warmup schedule all unchanged when the flag is absent).

### Changed
- **AFK rejoin syncs solo dancers to the top leader** — previously only players who were *following a leader* before the rejoin were re-synced (last leader → top-leader fallback); a player dancing **solo** was restored solo and never pulled into the group. Now a solo dancer also tries the current top leader (most followers, dancing) on rejoin, so the floor converges on the biggest group. Fully-idle players (no animation) are still left alone, and the whole fallback is gated by the existing `SYNC_FALLBACK_TOP_LEADER` (set false to disable). The top-leader attempt was factored into a shared helper used by both the last-leader-fallback and solo-dancer paths.

## [2.6.1] - 2026-08-16

AFK auto-rejoin latch fix (verified in playtest) + Packager automation hooks.

### Added
- **Packager plugin automation hooks** — `_G.clubkit_update_engine()` runs the same flow as the "Update engine" button (check → apply → config merge) for command-bar / MCP automation; poll `_G.clubkit_engine_update_status` (`state` = `checking`/`updating`/`done`/`error`, `progress`/`total`, `report`). Used to drive a v2.6.0 update from MiMoCode over robloxstudio-mcp without clicking the dock.

### Fixed
- **AFK auto-rejoin latched after one cycle** — post-2.6.0 report: rejoin fired once, then never again. Three causes, all server/client trust gaps: (1) `inFlightAfkRejoin` was set before `handleAfkRejoin` and only cleared on the error path or `PlayerRemoving` — a teleport that resolved ambiguously (or a `handleAfkRejoin` throw, which was never pcalled) left the flag stuck and every later request died silently as `in_flight`; (2) the request remote was fire-and-forget, so the client could not tell `rate_limited` ("wait for the 15-min token") from a fatal failure — after a successful rejoin the Roblox idle counter still reads >17 min, so the next `Idled` tick re-fires, gets rate-limited, burns all 3 attempts in ~2 min of blind 60s backoff, and latches until physical input; (3) `ClientRetryState`'s own comment claimed a reset path that did not exist. Fix: new `AfkRejoinResponse` remote carries the gate outcome back to the client (`allowed`/`denied_rate_limited`/… + `retryAfterSec` from the rate limiter); transient denials no longer burn the attempt budget — the client re-schedules from the server's hint (with jitter) and re-arms on `allowed`/`rejoin_failed`; `handleAfkRejoin` is now pcalled; the in-flight flag is cleared after `handleAfkRejoin` returns on success or error and reaped if it outlives the teleport window (stale watchdog). **Known limitation:** Roblox's native 20-minute idle kick is client-side and is *not* prevented by teleport rejoins (the idle counter survives a same-server teleport); preventing it requires synthetic input (`VirtualUser`), which Roblox's own docs call unmaintained and unreliable — this guard restores position + dance sync for semi-active players, it is not an AFK-kick bypass.
- **Dance sync lost on native respawn** — `pendingAfkSyncRestore` only fired from the teleport `wirePlayer` path (`GetJoinData`), so a native respawn (Reset button / `LoadCharacter` / reconnect) restored position but dropped the AFK dance sync. `CharacterAdded` now also restores the pending sync payload when no teleport restore is queued.

## [2.6.0] - 2026-08-16

External Admin Bridge (Adonis/Kohl's), free-announce membership gate, top-50 workspace boards; AFK rejoin teleport, DJ crackle, and boot fixes.

### Added
- **External Admin Bridge** — `ClubKitConfig.ExternalAdmin.Provider` selects `"Adonis"`, `"Kohls"`, or `"None"`. Engine exposes `ExternalAdminFacade` for optional place-pack bridge modules; Club Kit staff role changes sync one-way to the chosen admin, and `:cksetrole`/`:ckgift`/`:ckannounce` (Adonis) or `;cksetrole`/`;ckgift`/`;ckannounce` (Kohl's) run through Club Kit's own permission gates. Optional `ExternalAdminSelector` boot-gate script keeps the non-chosen admin fully off (UI included) without deleting it. See `extras/place-packs/ExternalAdminBridge/`. Membership and Spender roles never sync.
- **`ClubKitConfig.Announcement.MinMembership`** — buyer gate for free `/announce` + free broadcast panel (`Tier1`/`VIP`, `Tier2`/`VVIP`, `Tier3`/`Supreme`). Default remains VVIP+. Staff / Leadership `canAnnounce` and top spenders stay free.

### Changed
- **Workspace boards show top 50** — cash, Robux, community, and likes SurfaceGui boards paint 50 rows (was 10 cash/community, 20 Robux/likes). Fetch/cache still capped at `MAX_LIMIT` 100. Overhead top-spender tags and join-greeting top-10 are unchanged.

### Fixed
- **AFK auto-rejoin sometimes never teleports** — rejoin teleports used deprecated `TeleportToPlaceInstance`/`Teleport` behind a `pcall` only, but Roblox reports async teleport-init failures (e.g. `Flooded` throttling) exclusively via `TeleportService.TeleportInitFailed` — never as an error. A queued-but-failed teleport was treated as success: no retry, no fallback, no notification, and the in-flight flag stuck (locking the player out until they moved). Same-server and fallback teleports now use `TeleportAsync` + `TeleportOptions.ServerInstanceId` with a scoped `TeleportInitFailed` watcher (timeout resolves as success so a teleport is never double-fired). The client also retries a denied/failed request up to 3× per idle streak (60s backoff, `Player.Idled` keeps ticking while idle) instead of latching until mouse input, and transient server denials (in-flight, carry active) no longer consume the 15-minute rate window. `/rejoin` had the same pcall-only teleport bug and is fixed the same way. New engine config keys (not buyer-facing): `AfkGuard.TELEPORT_INIT_TIMEOUT_SEC`, `CLIENT_RETRY_BACKOFF_SEC`, `MAX_CLIENT_ATTEMPTS`.
- **DJ effect sliders + toggles crackle audio** — effect sliders and enable toggles no longer churn the audio DSP graph: effect instances are created once per sound and mutated in place (values guarded to actual changes; server echo replays are now no-ops when nothing changed), and effect/pitch toggles flip the `Enabled` flag instead of destroying/creating the node. Reported as crackling when typing (Kohl's side, see pack snippet) and when adjusting DJ effects.
- **ConfigBootstrap Announcement wiring** — resolve `MinMembership` without requiring `OverheadDomain` during `Config` load (was recursive module require / kit fail to boot).

## [2.5.3] - 2026-08-14

Music is global-only; vestigial zone mode removed.

### Removed
- **Zone-based music system** — music is now global-only: single server-wide session, every player hears the same track. Removes the vestigial zone mode (`Music.MODE`, `MusicZone`-tagged parts, `ZoneTrackerService`, `MusicZoneChanged` remote, `not_in_zone` errors, `MusicZoneDebug` bindable, client zone handlers + store fields). **Breaking:** if you edited engine `Config.luau` to set `Music.MODE = "zone"`, that option no longer exists — delete any `MusicZone`-tagged parts from your place. Buyer `ClubKitConfig` is unaffected (it never had zone keys).

## [2.5.2] - 2026-08-13

Gravity dial feels right, couples stay consistent, MusicCatalog groups playlists, Discord invite from config.

### Added
- **Roles & Ranks slide guide** — `docs/roles-guide.html` (+ hub / setup links) for adding roles via `ClubKitConfig`.

### Fixed
- **Music Library first-open placeholders** — Library no longer sticks on Studio template covers (`Playlist Name`) / duration (`05:26`) on first open. Loads playlists before tracks, waits one frame for layout, rebinds virtual rows when scroll window was 0, and reads `TrackLength` from `TrackDetails`.
- **Gravity drop intensity + fall anim** — `/gravity 1-10` now uses a controlled idle-down descent (PlatformStand + LinearVelocity, fall tracks suppressed) scaled by the Gravity dial; lands when near ground. No longer one-shot freefall kick (which made 1–10 feel identical and played the fall animation).
- **Gravity soft landing** — drop eases out near the floor (`RESTORE_SOFT_BRAKE_HEIGHT`), finishes slightly above ground, zeros vertical velocity, and snaps to stand height so the character no longer buries into the ground before release.
- **License timeout no longer bricks cash donations** — if license verify never succeeds (Studio timeout / network flake), features fail open instead of disabling `donation_http`; first-check-in-flight is optimistic so `donation_poll` is not a no-op.
- **Couple chat tag stuck after breakup** — flush no longer wipes session when DataStore flush fails; overhead cache no longer republishes a stale `[💕 Partner]` under Guest-fallback protection; immediate `ChatTagSync` clear via `patchCouplePresentation`; client optimistic `ChatTagStore.setCoupleTag(nil)` on breakup (initiator + partner NotifyResult).
- **Couple partner title missing on accept** — `OverheadDomain` always resolves coupled players to `relationshipMode = Taken` (Single/Fun no longer hide partner title); accept forces Taken with retry and skips needless profile cache invalidate; recovery overhead refresh + immediate presentation patch.
- **Packager Carry Upload + patch** — `ClubKitUI.button` passes the `TextButton` into `onClick`, so Carry upload no longer errors with `attempt to index nil with 'Text'`.

### Changed
- **MusicCatalog grouped playlists** — prefer `playlists = { { name = "Chill", tracks = { ... } } }` so you do not repeat `playlistName` on every line; flat `tracks` + `playlistName` still supported (legacy).
- **Top Menu Discord invite from ClubKitConfig** — set `Branding.DiscordInvite` (e.g. `discord.gg/your-invite`); Top Menu Community chip text + click open browser. Empty hides the link chip.
- **Admin Hub / Join Community mobile scale** — `04-AdminHub` root UIScale: phone **0.44** / desktop **0.88**; `16-JoinCommunPrompt`: phone **0.48** / desktop **1**. Both follow `MobileScaleService` + `PhoneLayout` (ChildAdded + viewport refresh). Admin Hub already uses `MobilePanelManager` exclusive focus via the topbar icon on phone.

## [2.5.1] - 2026-08-10

### Added
- **Packager "Include blank secrets" toggle** — Create package now ships `ServerScriptService/Hazastudio_ClubKitSecrets` by default (blank template, matching the existing "Include blank config" behavior). New `PackagerCore.collect` always blanks any filled-in `Secrets.<Field>` values before packaging (`blankTemplateSecretsSource`), so a distributed package can never carry a dev's own live API keys even if the toggle is left on for a place with real secrets configured.

## [2.5.0] - 2026-08-10

Cash currency (IDR/PHP), Admin Hub goes fully editable via ActionTemplates, Plugin gets Unpack RBXM, and Gravity/Ungravity get independent gears.

### Added
- **Plugin Unpack RBXM…** — Packager panel can pick a `.rbxm` / `.rbxmx` Club Kit package, deserialize it, and unpack into the place in one step (config/secrets preserved).
- **Cash currency: IDR + PHP** — new `ClubKitConfig.Donation.Currency` (`"IDR"` | `"PHP"`, default `"IDR"`) drives the cash symbol, thousands grouping, chip word, and spender-role label everywhere cash is shown: donation notifications, leaderboard boards, workspace boards, overhead chips, join greetings, the Settings "Name Tag Details" toggle, Command Library descriptions, admin chat command replies (`/fakecash`, `/donatecash`, `/addcash`, `/removecash`, `/dumpbagibagi`, `/listbagibagi`), and Admin Hub previews. Backed by new `CashCurrencyDomain` (currency presets) and an extended `DonationAmountFormat` (`formatCash`, `formatCashBoard`, `formatCashCompact`, `formatGrouped`); all previous `"Rp "` / `"RP "` / `"RUPIAH"` / `"Top Rupiah"` / `"IDR"` hardcodes now route through these. Display-only — amounts stay untagged integers and are **not** converted, so `MinAmount`, `AuraTiers` (`idrMin`/`idrMax`), and `WorldEffectTiers` must be retuned by hand when switching currency. Plugin **Donations** tab gets a **Cash currency** dropdown (`IDR (Rp)` / `PHP (₱)`) that writes `Donation.Currency`. Missing/unknown `Currency` fills forward to `IDR`, so existing buyer configs are unaffected.
- **Admin dashboard per-game currency** — `donation-api` gains a `games.currency` column (migration `0009_game_currency.sql`, default `IDR`) plus a `currency` dropdown in the Games table and the "Quick create" modal. The React admin panel's `formatIdr` helper was replaced by a currency-aware `formatCash`, used across overview totals, donation tables, leaderboard, donor detail, and adjust-amount modals. This is a display-only label for the ops dashboard — the in-game `ClubKitConfig.Donation.Currency` remains the source of truth and is not synced from it.
- **Admin Hub ActionTemplates** — editable sheet bodies under `StarterGui/04-AdminHub` (`ActionTemplates/*` **or** design-in-place masters on `04-ActionPopup.SheetBody` with `ActionId`). `openSheet` clones the matching master into `SheetContent` and never destroys the masters. Donate Fake preview no longer needs a player target (attributes to the admin); Manual/credit asks for a player only after that mode is selected.

### Changed
- **Separate Ungravity / Gravity gear dials** — Ungravity gear sets rise speed only; Gravity gear sets drop intensity only. Labels sync independently; Gravity tile uses restore dial, Ungravity uses float dial.
- **Admin Hub SelectedPlayerInfo** — runtime clones the redesigned `SheetBody.SelectedPlayerInfo` template (`PlayerProfilePicture` / `1-Title` / `2-SubTitle` / `ChangeButton`) instead of rebuilding an older script chip.
- **Admin Hub sheet binding** — announce / set role / gift / float speed / donations bind named children (`AnnounceMessage`, `PickGrid`/`PickKey`, `ChipRow`/`ChipValue`, donate `ModeList` + `Panel_*`) instead of always rebuilding UI from script.
- **Admin Hub shell** — section filters move from removed `01-SidebarWrapper` to top-header `Option1`–`Option5` slider (`Filter` = `all` / `utilities` / `access` / `identity` / `donations`); labels **All / Utilities / Access / Identity / Donations** via shared `SliderSelectorUtil` + `BackgroundPill` (same pattern as Music/Dance/Gift); close button binds from shell header; gallery tiles use `GroupId` for section filtering.

## [2.4.80] - 2026-08-10

Wutwut press UI softer; default A→B switch fade slightly snappier.

### Changed
- **Wutwut dance row highlight is press-held** — with `Features.WutwutDance = true`, the row no longer sticks on solid white/"played" while dancing. Press uses a soft gray tint (~30% toward white) with short fade in/out instead of the full played inversion. Desktop and mobile dance panels share this binder. With wutwut off, sticky selected behavior is unchanged.
- **Default switch crossfade** — engine / schema / template `Sync.SwitchFadeIn` / `SwitchFadeOut` / `SwitchInputCooldown` `0.55` → `0.45`. Existing buyer `ClubKitConfig` values are not overwritten by Update Engine; change manually if you still have `0.55`/`0.30` and want the new default feel.

## [2.4.79] - 2026-08-10

Wutwut reliability + comfort: panel cooldown no longer blocks restarts; SyncStore can clear pending; chain window 0.45s.

### Fixed
- **Wutwut spam blocked by SwitchInputCooldown** — with `Features.WutwutDance = true`, same-emote re-clicks in the dance panel use the short `WUTWUT_CLIENT_MIN_FIRE_INTERVAL` instead of `Sync.SwitchInputCooldown`, so rapid restarts can land inside `WUTWUT_CHAIN_WINDOW` (0.45s). Different-emote switches still use the normal cooldown.
- **Same-dance click stuck after stop (neutral)** — `SyncStore:set({ pendingAnimationName = nil })` was a no-op in Luau (nil keys are dropped), so `pending` stayed set after stop/ack and the next same-emote click always took the toggle-off path. Store now supports `_clear = { ... }`; same-selected only treats pending while `isDancePreparing`. Warmup completion no longer clobbers an in-flight prepare flag.

### Changed
- **Wutwut chain window** — `Config.Sync.WUTWUT_CHAIN_WINDOW` raised `0.32` → `0.45` for a more comfortable same-emote spam restart.

## [2.4.78] - 2026-08-09

Wutwut gate moves to a proper Features toggle (plugin panel visible).

### Changed
- **Wutwut gate is now a Features toggle** — canonical key is `ClubKitConfig.Features.WutwutDance` (default `false`), listed in `FEATURE_MANIFEST` so it appears in the plugin **Config → Features** panel ("Wutwut dance restart", group "Music & dance"). The 2.4.77 `ClubKitConfig.Sync.WutwutEnabled` key remains as a legacy alias: an explicit `true` there still enables the feature.

## [2.4.77] - 2026-08-09

Wutwut rapid dance restart returns as an opt-in feature (default off).

### Added
- **Wutwut rapid dance restart (opt-in)** — re-clicking the currently playing emote within `WUTWUT_CHAIN_WINDOW` (0.32s) hard-restarts it (fade 0 stutter); a slower re-click still toggles the dance off, and switching to a different emote keeps the normal crossfade. Restarts replicate to sync followers through the existing BFS path. Buyer-gated: `ClubKitConfig.Sync.WutwutEnabled` (default `false`; engine `Config.Sync.WUTWUT_ENABLED`, schema fill-forward adds it as `false`). Restart traffic uses its own rate bucket (`SyncRateLimit.WUTWUT_RESTART` 20/2s) and server interval (`WUTWUT_MIN_REQUEST_INTERVAL` 0.05s), so normal play/stop throttling is unchanged.

## [2.4.76] - 2026-08-09

Carry upload inside the main Club Kit plugin; Command Library Studio fix; docs + SociaBuzz art.

### Added
- **Template place delivery** — full service clone main pack (BHMS excluded); separate **SyncBhms add-on** model. Guide: `docs/delivery/TEMPLATE_PLACE.md`.
- **Carry upload in Club Kit panel** — Tools → Carry animations (scan / CreateAssetAsync upload / patch ClubKitConfig). No separate Carry Upload toolbar plugin required.

### Fixed
- **Command Library topbar click did nothing** — `CommandLibraryController.init` aborted when `Player:GetRankInGroup` threw `HttpError: NetFail` (common in Studio), so `icon.selected` never connected. `resolveRole` now pcalls `GetRankInGroup` and falls back to Guest until overhead/cache fills.

### Changed
- **Docs setup is one detailed flow** — removed Quick Start + parallel topic sections (Group/Roles/Donation/Commands/…). `setup.html` is now steps 1–9 only (insert → publish) with full detail inline; sidebar = step list; home topics reduced to Setup + Updates + Reference.
- **Docs reference page** — new `reference.html`: full command list (Command Library + owner extras), `FEATURE_MANIFEST` (plugin Config → Features), and privilege keys. Added to dock nav (ID/EN/JA/ES).
- **Docs aligned with plugin** — No showcase/demo as required step; NukeWorldPosition, Membership Game Pass, Diagnostics, and Source-only PaidBroadcast covered inside the flow. Applied across ID/EN/JA/ES.
- **SociaBuzz cash-tab illustration** — donation panel `3-SaweriaTab` now uses branded asset `rbxassetid://113679135532210` at height 160 (was temporary Bagibagi art). Gold gradient stays on.
- **Docs hub visual pass** — filled cards and tinted panels replaced by hairline separators and left rules; headings capped at 24px (page title) / 20px (section title); home page stat cards replaced by a plain key/value meta list. Language switch and theme toggle in the floating dock now keep readable contrast in light mode.
- **Docs voice is now game-owner only** — every page addresses the place owner directly instead of describing a "buyer". Seller framing removed. Applied across all four locales (ID/EN/JA/ES).
- **Docs no longer link repo-only markdown** — the 11 `releases/<version>/UPGRADE.md` links, the `docs/releases/` index link, and the `../CHANGELOG.md` links were removed from the Updates and Home pages. Release detail now lives entirely in the on-page "What's new" accordion.
- **Carry fix no longer redirects to a missing toolbar button** — logic lives in `CarryUploadCore`; standalone `CarryAnimUploaderPlugin` is deprecated.

## [2.4.75] - 2026-08-08

Hotfix: server boot blocked by stray syntax in DonationController.

### Fixed
- **DonationController boot crash** — stray `er` token after `return createDonationController` caused `Expected <eof>, got 'er'`, blocking server `Main` and leaving clients stuck on the loading screen.

## [2.4.74] - 2026-08-08

Plugin Config Features panel driven from engine schema manifest (Admin Hub + Legacy SyncBhms visible in UI).

### Changed
- **Plugin Config → Features** — toggle list now loads from `ClubKitConfigSchema.FEATURE_MANIFEST` in the synced engine (includes Admin Hub, Legacy SyncBhms). No more duplicate hardcoded feature list in the plugin.

## [2.4.73] - 2026-08-08

English localization pass for engine copy + automatic cash leaderboard title from donation provider.

### Added
- **Cash leaderboard board title auto-branding** — workspace `SaweriaDonationBoard` header now follows `ClubKitConfig.Donation.Provider` (`bagibagi` / `saweria` / `sociabuzz`) via `DonationProviderDomain.applyCashLeaderboardBrand` on paint (e.g. `BAGIBAGI DONATIONS` instead of a hardcoded `SAWERIA DONATIONS` asset label).

### Changed
- **English-only codebase copy** — comments, agent/docs (except `docs/locales/id.js` and historical `docs/releases/*` folders), warn/log strings, and default runtime player-facing strings translated from Indonesian to English. Product UI emoji preserved (AdminPanel picker, couple announce 💕/💔, preset admin title strings).
- **Default runtime strings (English)** — couple announce/breakup, donation chat tag (`[DONATION] DONATION RECEIVED`), gift lookup errors, admin test-donation notify text, and related Config defaults.
- **`ClubKitConfig.luau` template** — buyer-facing comments and section headers in English (keys/values unchanged).
- **CHANGELOG** — legacy date headers normalized (`?` → `-`); older 2.0–2.2.x bullet entries translated to English.

## [2.4.72] - 2026-08-08

Audit-driven patch: DataStore data-loss fixes, client boot hardening, and abuse-gate closures found during a full-codebase review. No new player-facing features.

### Fixed
- **LegacySyncBhms = false** now truly hides place-pack BHMS (topbar Dance + DanceGui). Pack scripts gate via `ReplicatedStorage.SyncBhmsGate`; Club Kit also disables residual `DanceGui` when the flag is off.
- **Favorites / Music favorites lost on leave** — `FavoritesRepository` / `MusicFavoritesRepository` now keep a `_pendingFlush` payload when the leave-time save fails, instead of discarding the dirty entry once `_loaded` is cleared. `flushAll` retries pending entries on the next autosave/shutdown pass (mirrors `SettingsService.pendingFlushByUserId`).
- **Sticker collection could be overwritten by a failed load** — `StickerRepository.load` returns `Err` on failure/negative-cache instead of seeding an empty default collection. `StickerService` tracks `_loadedByUserId` and rejects `addSticker` until a load has actually succeeded, so a transient DataStore hiccup can no longer wipe a player's real stickers.
- **Level XP lost on disconnect** — `Main.server.luau` now calls `levelService:flushPlayer` from `Players.PlayerRemoving`; unsaved XP for players who already left is retried via a new `levelService:flushAllPending()` from the early-shutdown flush and `BindToClose`.
- **Client boot could hang forever on a missing remote/folder** — `Main.client.luau` kit-folder waits (`Shared`/`Constants`/`Domain`/`UI`/`Utils`) and two synchronous remote waits (`Notify`, AvatarContext like-effect) now use `LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT` and fail into a warn instead of yielding forever. `CoupleController`, `SettingsController`, and `AvatarContextController` apply the same timeout to their remote waits and soft-disable (warn + stub/no-op) instead of erroring when a remote never shows up.
- **Dance panel crashed on phone layout without the mobile wrapper** — `DancePanelGuiRefs` now falls back to the desktop panel (with a warn) instead of `error()`-ing the whole dance boot task when `DancePanelGUIWrapperv2Mobile` is missing.
- **HotbarInventoryService connection leak** — character `ChildAdded`/`ChildRemoved` listeners are disconnected before rebinding on every respawn, instead of accumulating for the session.
- **ConfigBootstrap fill-forward noise on live servers** — the fill-forward summary now goes through `Logger:info` (Studio-only) instead of an unconditional `print` on every server boot.
- **Mojibake in `KitProduct.Support.Note`** and a doubly-mangled comment in `ClubKitManifest.luau` cleaned up to plain em dashes.

### Security
- **Sticker global pool** — `addSticker` only pushes into the shared/broadcast global pool for admins or Studio; regular players' own stickers still save to their personal collection as before.
- **`MusicService:resolveOrCreateTrackForAsset`** — now gated by `isManageAllowed` (admin/DJ-role), matching the other track/playlist-mutating music methods. Previously any player could resolve an arbitrary asset ID into a new shared request-history track.
- **`CommandLibraryController`** — added a central permission gate before `service:execute`: self-service and already role-gated command aliases pass through, anything else (including any future command wired in without its own check) now requires admin-panel-tier access by default.
- **`ClubKitConfig` template** — removed the hardcoded developer `OwnerUserId` / `AdminUserIds` entry from the buyer config template (now `0` / empty) so a fresh install no longer silently grants the kit author admin access. Existing places are unaffected (buyer config is never overwritten by engine sync).

## [2.4.71] - 2026-08-07

### Added
- **Docs i18n (ID / EN / JA / ES)** — `docs/i18n.js` + `docs/locales/{id,en,ja,es}.js`; language switcher; Home, Setup + Updates fully translated
- **Docs hub (multipage)** — `docs/index.html` Home, `docs/setup.html` (buyer setup guide), `docs/updates.html` (Update Engine + release highlights); shared `docs.js` theme + dark mode
- Club Kit Swiss-knife Studio plugin panel (Config / Diagnostics / Engine / Tools / Packager / Settings) — Inter font, prototype-parity dock UI; Config+Secrets Source write-back via ConfigEditCore
- **Plugin dev hot-reload** — `dev-serve.ps1` serves `plugin/*.luau` on `http://127.0.0.1:8798`; toolbar **Reload Panel** (or `reload_clubkit_panel()`) rebuilds the dock in-session via HttpService + loadstring module registry. Falls back to bundled modules when the server is offline; bootstrap itself still needs one RBXM rebuild + restart.
- **Daily donation boards (3)** — `DailyDonations` (combined Robux+Cash, sort by latest donation), `DailyDonationsRobux`, `DailyDonationsCash`. Combined payload `dailyCombined` with per-row `currencyKind`. Cash rows prefix **`RP `** and hide `RobuxLogo`; Robux rows show the logo.
- **UI MotionPresets** — shared calm motion tokens (`Client/Utils/MotionPresets`) + thin `Config.UIMotion` (`MOTION_SCALE`, center open/close times). AnimationHelper center/panel/dialog timings read presets.
- **PressFeedback** — calm press UIScale micro-interaction on Shop/Gift CTAs, TopMenu entries, MenuShell tabs/modal, Dance category tabs.
- **UISpring** — shared critically-damped UI spring driver (Heartbeat).
- **Admin Hub (`04-AdminHub`)** — action-first staff panel (gallery + player popup + sheets) wired to CommandLibrary execute; gated by `Features.AdminHub` (default **false**). Title tile opens existing Admin Panel editor. Gates: mod teleport/announce, admin gift/role/gravity/fake donate, owner ledger/reload boards.

### Changed
- **Admin Hub gated** — `Features.AdminHub` / `FeatureFlags.AdminHubEnabled` (default **false**). When off, classic Admin Panel owns the topbar; hub bootstrap is skipped.
- **Docs visual soften** — reduced outlines/borders and card chrome across Home/Setup/Updates (hairline separators + surface contrast instead of boxed cards; softer focus rings)
- **Docs hub polish** — Inter-only typography on Home/Setup/Updates (Source Serif 4 dropped from Google Fonts + `theme.css`; Lyon serif token removed), unified site header + primary CTA across the three pages, consistent hub panel/card spacing, changelog toggle chevron, inline styles moved into the stylesheet
- Plugin panel UI rebuilt for reliable PluginGui rendering — page builders split per tab, only the active page mounts in the scroll canvas; same Config/Diagnostics/Engine/Tools/Packager/Settings wiring
- **Plugin panel contrast/readability pass** — visible sidebar surface with edge separators, gradient brand logo + version line, nav accent bars, inset Config children, stronger hover/active states; engine update auto-check now runs once per Studio session (no GitHub spam on every hot-reload)
- **Plugin panel visual redesign ("Aurora Dusk")** — full from-scratch pass on `DovetailTheme` / `ClubKitUI` / `ClubKitPanel`: Inter (`Font.fromId(12187365364, weight)`) everywhere (chrome + body, no more Gotham), cool near-black surfaces with a periwinkle/violet accent duo, borderless card-based layout (elevation via background color, not strokes), tracked small-caps kickers, larger type scale, elevated stat cards, gradient brand mark, animated sticky save bar. Sidebar nav buttons remain direct opaque children of Sidebar (paint-safety rule); content is inset via `ScrollInner` position, not padding alone.
- **LiveChatDonations Footer** — hidden while idle; donor info root also hidden so message stays centered. Pop in/out polished: Back spring + fade, staggered card/total/footer, soft message settle when returning to idle.
- **`Leaderboards.DAILY_ROBUX_ENABLED`** default **true**; new **`DAILY_COMBINED_ENABLED`** / **`DAILY_COMBINED_LIMIT`**. Daily SurfaceGui resolve is part-scoped first (shared `DailyDonationsWrapper` name under different parts).
- Cash amount format on boards: `RP.` → **`RP `** (space).
- **TopMenu (topbar custom) open/close** — critically-damped spring slide + fade (`UISpring`) instead of Quart tween; interruptible mid-flight; tune via `Config.UIMotion.SIDEBAR_SPRING_FREQ`.
- **Sidebar / toast / command library / avatar context** — open/close timings unified via MotionPresets (no local 0.28/0.18 dialect copies).
- **Admin + Donation floating subpanels** — open with calm `presentCenterPanel` instead of Back `scalePop`. Streak / Couple spectacle pops unchanged.
- **Admin Hub chrome** — propagate MainWrapper polish to player/action popups + toast (panel `#0C0C0C`, corner 18, no stroke, fade headers, danger close).
- **Admin Hub motion** — hub open/close via `presentCenterPanel`; player/action overlays via `presentDialog` + dim fade; PressFeedback on tiles/sidebar/CTAs. Action feedback uses kit `NotifService` → General Notification Center (not the hub Toast frame).
- **Admin Hub popups** — closer to HTML prototype: surface `#141414`, soft stroke, larger player/action panels (360×480 / 440×560), clean headers (no white fade), 2-col pick cards + white selected chips, callout title/body variants, donate amount preview.

### Fixed
- **Top menu Cinematic Dock button** — hide `CinematicDockButton` for non-admin on desktop + phone (`TopBarMenu` / `TopBarMenuPhone`); gate matches Admin Panel (`PermissionDomain.canUseAdminPanel`), refreshed when local role/overhead cache updates.

## [2.4.70] - 2026-08-04

### Changed
- **Version nudge** — no engine feature delta vs 2.4.69; bump so Studio **Check Update** picks a fresh tag (re-sync / buyer update path).

## [2.4.69] - 2026-08-04

### Added
- **`Features.DonationWorldEffects`** — master toggle for cash Nuke/Smite/BlackHole (default true). When false: no `worldEffect` on presentation, client gates skip, Settings “World Effects” row hidden. Aura/announce/highlight unchanged.
- **`/drone start|stop`** — staff shared freecam: one pilot streams camera (~15Hz); everyone else locks to that view. Gate: admin panel. Shift+P blocked while spectating.
- **`/crowd <text>`** — staff make every player show the same chat bubble (filtered). Does not execute commands / dances.
- **SociaBuzz cash provider** — third IDR webhook path (`/webhook/sociabuzz/...`) + `Donation.Provider = "sociabuzz"` branding preset (cash tab / donor labels). Same poll + boards pipeline as Bagi-Bagi/Saweria.

### Changed
- **Studio plugin panel v2** — dock UI rebuilt (AMOLED HyperOS): tabs Engine / Tools, hero + version grid, Check/Update/Skip, channel chips (setting saved; Check still stable-only until channel sync ships), Gen Tools + Carry fix rows. No Package tab in panel.
- **Config fill-forward (Update Engine)** — louder Config merge status; broader `Features = {` finder; if missing Features keys cannot be written to Source → clear `CONFIG MERGE FAILED` (engine files still apply). Buyer values never overwritten.
- **Plugin panel motion** — hero entrance, staggered cards, tab/channel springs, press feedback, update progress bar, status pulse tones, modal scale, confetti-lite on successful Done.

## [2.4.68] - 2026-07-28

### Added
- **`/fakecash` / `/fakerobux`** — admin fake-donation preview with optional target player and message: `/fakecash [player] <amount> [message…]` (cash: notif + aura + world VFX; Robux: notif + aura only). No leaderboard persist (`testOnly`).

### Changed
- **Donation preview rename** — canonical commands are `/fakecash` and `/fakerobux`. `/testcash`, `/testrobux`, `/testsaweria`, `/testdonate` remain as deprecated aliases (same parse + admin gate).

### Fixed
- **Donation aura gray brick** — host `BasePart`s that only carry ParticleEmitter/Beam/Trail/Light are forced `Transparency = 1` (particles still render). Previously those emitters were treated as “keep visible,” so some tiers showed a plastic box at the character’s feet.

## [2.4.67] - 2026-07-28

### Added
- **MusicCatalog script seed** — fill `Hazastudio_ClubKitConfig/MusicCatalog.luau` (one line per track, multi-part `parts` up to 9). Server merge is additive to DataStore on boot; default playlist **Legacy**. Manage UI can still edit/move/delete. Toggle: `ClubKitConfig.Features.MusicCatalogSeed` (schema fill-forward). Deletes via Manage are not re-seeded (fingerprint + tombstone).

## [2.4.66] - 2026-07-24

### Changed
- **Version bump for engine sync** — empty release; no feature or bug fix changes. Use plugin **Update Engine** to pull kit `2.4.66`.

## [2.4.65] - 2026-07-23

### Changed
- **Dance panel favorite** — starring an emote only toggles the badge; it no longer rebuilds/reorders the Dance/Pose list (Favorites tab still lists favs). Cross-category favorite injection into Dance/Pose removed.

## [2.4.64] - 2026-07-23

### Fixed
- **Chat tags no longer invent `[GUEST]` for distant players** — chat tags use a thin global `ChatTagSync` roster (AboutRoster-style), not proximity-gated overhead. Name + `[tag]` share the same role/membership color; until an authoritative entry arrives, chat shows display name only.
- **Join-storm false `budget_exhausted`** — DataStoreScheduler distinguishes `inflight_saturated` vs `budget_low`; negative-cache only on real budget pressure. `MAX_INFLIGHT_PER_TYPE` / `ProfileLoader.MAX_CONCURRENCY` restored to **8**; `JOIN_DATA_READY_TIMEOUT` raised to **10s** (≥ defer).
- **Rank cache no longer poisons Guest for 10 minutes** — group rank cache stores `{ rank, ok }`; transient GroupService/worker failures use short fail TTL + `_LKG_RankId` instead of caching confirmed-zero for `RANK_CACHE_TTL`.
- **ChatTag edge hardening** — catch-up via `OverheadRosterRequest` after client wire; batch upsert ignores stale `rev`; client clears store on `PlayerRemoving`; publish gate keys off Guest **primaryTag** (not role alone) so gifted membership still publishes when rank lookup flakes; `lastGood` only from ChatTagStore.

### Added
- **`ChatTagSync` remote + client `ChatTagStore`** — server publishes tag-authoritative entries only (`rankLookupOk` and/or non-unresolved payload); joiners get a batch; leavers get remove.

## [2.4.63] - 2026-07-23

### Fixed
- **Admin giftcard false success** — `AdminSendGiftcard` now stores/replays the real outcome per `requestId` (success or failure). Retries after a failed grant no longer return `{ success = true }`.
- **Admin SetTitle permission message** — non-admin attempts notify `MSG_GIFT_NO_PERM` instead of the misleading “style not available”.
- **Admin ResetTitle silent fail** — auth / rate-limit failures now notify the admin (same messages as gift/title rate paths).

### Changed
- **Dance crossfade (map-style)** — switch + sync join use matching `Stop(fade)` + `Play(fade)`. Mid-fade zombies hard-clear only when nearly dead (`weight < 0.2`); full/mid-weight soft-out. Switch-back onto a fading track uses `AdjustWeight(1, fade)`. Defaults: switch **0.55s**, start **0.45s**, sync join **0.4s**. Buyer can tune via **`ClubKitConfig.Sync`** (`FadeIn` / `SwitchFadeIn` / `SyncJoinFade` / `SwitchInputCooldown`) — schema fill-forward + ConfigBootstrap. Sync join still samples leader phase + Length retry. `/re` restore stays hard snap.
- **`/re` in-place appearance refresh** — no `LoadCharacter` / SpawnLocation hop / camera fight. Fetches fresh `HumanoidDescription` (`ClearCachedAvatarAppearance` + `GetHumanoidDescriptionFromUserIdAsync`, no kit TTL cache) and applies with `ApplyDescriptionAsync` while staying put. Dance restores **immediately** at saved phase (not after Head wait); overhead `Avatar:Refreshed` settles separately. Failures stay in place with `MSG_REFRESH_FAILED` (no respawn fallback). Website **animation pack** is applied too (earlier locomotion-ID freeze left packs stuck on the first avatar).
- **Removed LoadCharacter `/re` camera leftover** — deleted unused `RefreshCameraPreserve` client module + `PENDING_REFRESH_ATTRIBUTE` (in-place `/re` never respawns).
- **Admin SetTitle text filter** — special titles run through `TextService` broadcast filter before persist; blocked/empty → `MSG_TITLE_FILTERED`.
- **Cash donation notif poll faster** — idle `NOTIF_POLL_INTERVAL` 15s → **5s**, burst `NOTIF_BURST_INTERVAL` 5s → **2s** (typical delay ~0–5s / ~0–2s after pay). Still well under Roblox HttpService 500/min/server and CF Workers free quota.

### Added
- **Delayed server restart early flush** — on `game.ServerRestartScheduled` (Creator Hub / Open Cloud delayed restart), kit warns all players and flushes session buffers (XP, settings, favorites, Persistence Fabric) before `BindToClose`. Gift pending already durable in DataStore; final BindToClose flush unchanged.
- **`ClubKitConfig.Sync`** — buyer knobs for dance fade transitions (documented in template).

## [2.4.62] - 2026-07-19

### Fixed
- **Name Tag Details / Badge Types hide was viewer-global** — toggles are privacy for **your** overhead only; other players' layers stay visible when they show them. Local attributes only give instant feedback on your own head.
- **Top Rupiah / Top Robux hide ignored donation chips** — `00-DonationLayers` chips (`RupiahRankWrapper` / `RobuxRankWrapper`) now respect `TopSpender` / `TopDonate` visibility (same as legacy rows).

### Changed
- Settings → Overhead public sync is **debounced (3s idle)**, **diff-before-write**, and **one short retry** to avoid UpdateAsync / refresh spam when toggling rapidly.
- Settings copy clarifies Name Tag Details / Badge Types control what others see on **your** name tag.

## [2.4.61] - 2026-07-19

### Added
- **`/re` keeps camera orbit** — client snapshots relative camera before `LoadCharacter` and re-applies yaw/pitch/zoom after the new Humanoid binds (skips freecam/cinematic/first-person).

## [2.4.60] - 2026-07-19

### Fixed
- **`/re` stuck at SpawnLocation** — production restore path: single-flight per CharacterAdded (no double-pivot race); `CharacterReady.waitForPositionRestore` waits PartsReady + in-world (+ AppearanceLoaded when available) so Roblox spawn placement does not overwrite PivotTo; pending kept until pivot succeeds; deferred re-assert if position drifts.

## [2.4.59] - 2026-07-19

### Added
- **CharacterReady (map versatility Phase A)** — shared `Shared/Utils/CharacterReady` with tiers `parts` / `adorn` / `anim`, stream-gated `pivotTo` / `streamAround`.

### Fixed
- **`/re` only once / never works (v2.4.58 regression)** — removed in-place `ApplyDescription` path (Roblox cache no-op + sticky `pendingReSyncRestore` lock). `/re` is `LoadCharacter` again with stream warm + stream restore, distinct busy message, and a lock timeout. Overhead Head settle / client rebind from 2.4.58 kept.
- **Loading overhead suppress misses late Head** — suppress watcher rebinds when Head appears/replaced instead of early-returning when Head is missing at CharacterAdded.
- **Sticker client miss on UpperTorso** — `StickerBillboardAnimator` watches server adornee priority (`UpperTorso`…), not Head-only.
- **`/bring` / `/to` on streamed maps** — teleports use the same stream-warm `pivotTo` as `/re` restore.
- **Respawn blank nametags (Phase B)** — proximity membership restores immediately on PartsReady (`recomputeNow`); overhead recovery / join broadcast run after that pass.
- **Join first broadcast wall-clock (Phase B)** — replaced unconditional `CHARACTER_READY_DELAY` sleep with AdornReady signal gate.
- **`/re` dance restore one-shot nil** — `anim` tier is parts+Animator only (no Head); `restorePreparedRefresh` waits/retries Animator briefly.
- **Head attach tax / temp-Head race** — `waitStableHead` prefers `HasAppearanceLoaded` / `CharacterAppearanceLoaded` (instant when already loaded); debounce is fallback only (e.g. some StarterCharacters).
- **Loading other-player flash on stream-in** — `hideOtherPlayers` follows `DescendantAdded` while overlay blocks.
- **CharacterReady.wait hang** — Character wait is deadline-bound (no bare `CharacterAdded:Wait()`).

### Changed
- Overhead server/client + `AnimatorUtils.isCharacterReady` route through `CharacterReady`.
- Removed dead `Avatar:Refreshed` overhead listener (no emitters after ApplyDescription `/re` removal).
- `CHARACTER_READY_DELAY` comment only (no forced sleep); GroupService settle delays unchanged.
- Phase C buyer View_Range knobs: **out of scope** (engine owns readiness).

## [2.4.58] - 2026-07-18

### Fixed
- **Overhead missing on large / streamed maps + `/re` basecamp hop** — root cause was character lifecycle, not a Roblox platform break: attach raced a temporary Head, `/re` used `LoadCharacter` (spawn → restore) and double-fired `Avatar:Refreshed`, and loading restore forced `Enabled=false`. `/re` now prefers in-place `ApplyDescription` (stay put); LoadCharacter fallback streams then restores without a second overhead attach; server waits for a stable Head before parenting the BillboardGui; client rebinds the Head watcher when Head is replaced; loading dismiss no longer clobbers Club Kit overhead `Enabled`.

## [2.4.57] - 2026-07-18

### Fixed
- **OrderedList cold-start throttle (live low CCU)** — Fable A+B+C: leaderboard cache/last-known-good served before throttle lockout; `GetSortedAsync` uses `LB_READ_RETRY_ATTEMPTS = 1`; overhead live rank resolve deferred until after LB pre-warm (`RANK_RESOLVE_DELAY_SEC`).
- **Dance broken-arm blend on switch** — dance-to-dance switch hard-stops the outgoing track (`stopFade = 0`) so Action4 weights no longer overlap during rapid clicks.
- **Carry × dance Action4 clash** — starting carry on the carried player hard-stops existing Action4 tracks; dance start is refused while `CarryWeld` is present; `Carry_*` tracks are excluded from dance classification.
- **Sync-join phase delay** — follower `TimePosition` snap uses leader `activeAnimationIds` (not first fading track) and applies immediately after `Play` when `Length` is ready.

### Changed
- **Paid Broadcast free for canAnnounce** — staff/moderator (and anyone with `canAnnounce`) see button **"Send broadcast"** and send without Robux; regular players keep the paid product prompt. Server re-checks permission so UI spoof cannot free-send.

## [2.4.56] - 2026-07-17

### Changed
- **World VFX console noise cleaned up** — when Nuke replaces Smite4/BlackHole, background `spawn` / animation-marker threads no longer dump `WorldEffectAborted` stacks to the console (expected abort). Abort detection now matches Roblox's wrapped error string via `WorldEffectFlight.isAbortError`, and the `World effect dispatch` / `skipped` diagnostics were demoted from `info` to `debug`.

### Notes
- **Donation spam hardening verified** — test/preview commands (`/testcash`, `/testsaweria`, `/testdonate`, `/testrobux`) enforce `isAdmin` server-side and manual commands (`/donatecash`, `/addcash`, …) enforce owner-or-Studio; chat commands run off server-authoritative `TextChatCommand.Triggered` / `Chatted` (no client remote), and real donations come from server-side Saweria polling / MarketplaceReceipt. No client-triggerable path can spam donation notifications or world VFX.

## [2.4.55] - 2026-07-17

### Fixed
- **World VFX dispatch never reached EffectDonate** — `WorldEffectDispatch` recreated a new parentless `BindableEvent` on every `connect`/`fire` (reuse required `Parent`, which is always nil for parentless instances), so notif fired event B while LocalNuke/Blossom/BlackHole listened on event A.

## [2.4.54] - 2026-07-17

### Fixed
- **World VFX blocked on Graphics Low** — donation Nuke/Smite/BlackHole no longer gated by `SettingsHideAllParticles` / graphics tier 0 (Low). Only explicit hide-world-effect toggle or near-zero donation VFX scale skips them. Added client/server log lines for dispatch vs skip.

## [2.4.53] - 2026-07-17

### Fixed
- **Nuke world effect crash** — `LocalNuke` required `DonationVfxClientGate` with one extra `.Parent` (`Utils` under kit root instead of `Client/Utils`), so rocket VFX errored on every play while the server still held the world-VFX queue slot for ~90s.

### Changed
- **World VFX follows donation notif queue** — Nuke/Smite4/BlackHole start when that donation's notification starts showing (client `WorldEffectDispatch`), instead of a server serial wait of 90–240s. Previous world effect is aborted when the next notif begins. Spam `/testcash` no longer delays world FX by minutes.

## [2.4.52] - 2026-07-17

### Fixed
- **Chat tag intermittently Guest** — `ChatTagsController` no longer keeps its own duplicate `OverheadUpdate` cache (it initialized after the server's initial batch, so the batch was missed and partial deltas were dropped without a baseline → tags randomly fell back to Guest). Chat tags now read from `OverheadController.getCachedPayload` (always-complete merged cache) with a last-known-good fallback so tags never downgrade to Guest once resolved.

### Added
- **CarryAnimUploaderPlugin** (`tools/CarryAnimUploaderPlugin/`) — local Studio plugin: bulk-upload `ReplicatedStorage.Carry` KeyframeSequences (`Name 1/2` → carrier/carried) via `CreateAssetAsync` Animation, then patch `ClubKitConfig.Carry.Styles.*.animations`.

### Changed
- **Chat bubble calmer on head movement** — `ClubKitChatBubble` attachment parented to `HumanoidRootPart` instead of `Head` (no neck pitch / look-down drift). Height still derived from overhead stack + `NUDGE_STUDS -0.5`.
- **Music panel tab** — selector label `Request` → `Library` (`Config.Music.TAB_LABELS.reqSong`).

## [2.4.51] - 2026-07-17

### Changed
- **Chat bubble nudge default** — `NUDGE_STUDS` 0→`-0.5` (locked from live `/height -0.5` tune).

## [2.4.50] - 2026-07-17

### Added
- **Bubble height tune commands** — `/height`, `/bh`, `/bubbleheight` (local client): `/height` status, `/height -0.5` nudge, `/height factor 0.25`, `/height reset`.

### Changed
- **Loading intro hold** — black screen + centered logo intro now stays for at least 5 seconds, and fast boot no longer skips it early.
- **Chat bubble default lower** — `HEIGHT_FACTOR` 0.38→0.25, `EXTRA_STUDS` 0, `NUDGE_STUDS` 0.

## [2.4.49] - 2026-07-17

### Fixed
- **Chat bubble still slightly high** — `HEIGHT_FACTOR` 0.5→0.38, `EXTRA_STUDS` 0.12→0.02.

## [2.4.48] - 2026-07-17

### Fixed
- **Chat bubble too high** — attachment Y used billboard center + full stack height (double-count). Now `center + height*0.5 + small pad` (`Config.ChatBubble.HEIGHT_FACTOR` / `EXTRA_STUDS`).

## [2.4.47] - 2026-07-17

### Added
- **Dynamic chat bubble offset** — bubble chat follows overhead stack height via per-character `ClubKitChatBubble` Attachment + `BubbleChatConfiguration.AdorneeName` (event-driven after OverheadUI apply; kill switch `Config.ChatBubble.ENABLED`).

### Changed
- **Chat bubble style** — background `#111111`, text color soft/pastel from speaker role (`toLightPastel` of chat primary tag color).
- **Donation roles cleanup** — removed giftable `Donatur`/`DONOR` role. Leaderboard auto-roles renamed: Robux → **Top Robux Donator** (`TOP ROBUX DONATOR`), Rupiah → **Top Rupiah Spender** (`TOP RUPIAH SPENDER`). Both capped at **top 10** for overhead chips + PlayerList/chat team (rank `#11+` no longer grants top role). Tool folders and join-greeting labels updated; legacy aliases (`Top Supporter`, `Top Donor`) still map to the new roles. Dynamic top roles are not giftable.

## [2.4.46] - 2026-07-17

### Fixed
- **Couple accept → Taken** — after a proposal is accepted, both players' profile `relationshipMode` is forced to `Taken` (overrides prior Single / Fun) so overhead shows Taken + partner display name. Profile menu syncs for online players. (`showCoupleName` + public CoupleName layer already forced in `CoupleDomain.applyCouple`.)
- **Couple breakup not persisting** — flush session write-behind before `invalidateCache` on accept/breakup/open panel (cache clear was dropping dirty couple clears before DataStore write). `breakupBoth` now returns Err if initiator save fails or player is not coupled.
- **Music queue wipe on long-run poll** — library `loadAll` no longer replaces in-memory tracks with `{}` on failed/incomplete DataStore reads (returns Err, keeps prior snapshot). Poll `onLibraryReloaded` no longer hard-prunes user queue when tracks are temporarily missing; explicit admin delete still uses `pruneDeletedTracks`.

## [2.4.45] - 2026-07-16

### Fixed
- **Carry physics** — carried parts (including `HumanoidRootPart`) are fully `Massless` + `CanCollide = false` while welded, so the carrier is not drag-loaded. Carrier keeps normal WalkSpeed/JumpPower (jump allowed). Carrier carry anim priority lowered to `Action` so Sync dance (`Action4`) can play; carried stays `Action4` + `PlatformStand` so they remain stuck/limp on the weld.

## [2.4.44] - 2026-07-16

### Fixed
- **Dance predictive local play** — removed client `LoadAnimation`+`Play` on click (was causing double-weight, stale row jumps, toggle race, sync fights). Keep optimistic row UI + `FireServer` + click `PreloadAsync` warm only; server remains sole playback authority. Stale `anim_result` stop/error ignored while a newer selection is pending.

## [2.4.43] - 2026-07-16

### Fixed
- **PlayerSessionStore flush race** — generation guard + single-flight flush; stale in-flight writes reschedule instead of overwriting newer session data.
- **Favorites recv leak** — dance + music favorites no longer replicate via Player Attributes; owner-only `REMOTE_SYNC_FAVORITES` / `REMOTE_FAVORITES_SYNC` push JSON to the owning client.
- **Favorites DataStore churn** — write-behind debounce (`FAVORITES_SAVE_DEBOUNCE_SEC`, default 8s); flush on leave/shutdown via existing session store.

### Added
- **`DonationVfxClientGate`** — client gate for legacy EffectDonate scripts (`SettingsHideAllParticles`, `SettingsGraphicsTier`, `SettingsDonationVfxScale`).
- **`SettingsHideAllParticles` player attribute** — mirrors graphics preset for VFX gates.
- **AvatarPrewarmPool `setActive`** — proximity tick scan pauses while ACM panel is closed.
- **Loading intro frame** — script-built blank + centered `Branding.LOGO_IMAGE` + `BlurEffect` before cinematic camera/dance; blur clears with progress (`Config.Loading.INTRO_*`).
- **Dance warm during loading** — tier1 `PreloadAsync` starts in boot; finish can hold until tier1 ready (`DANCE_WARMUP_DURING_LOADING`, `HOLD_LOADING_FOR_DANCE_TIER1`).

### Changed
- **Dance full-catalog PreloadAsync** — `DANCE_PRELOAD_FULL_CATALOG` (default on): after tier1 ready, background `ContentProvider:PreloadAsync` continues for the rest of the dance/pose catalog (content cache only; no mass `LoadAnimation`). Kill switch: set `false` to restore 32-asset envelope.
- **Dance click path** — optimistic row selection + `FireServer` immediately (no warmup gate); predictive local Play after per-click preload; reconcile on `anim_result`.
- **Dance panel selection UI** — update previous + current row only (instant, no full-list 0.5s tweens).
- **Phone graphics boot** — provisional `Low` preset via `PhoneLayout` until Settings sync arrives (was `Balanced`).
- **DonationEffect remote** — world nuke VFX broadcast uses `UnreliableRemoteEvent` (cosmetic-only; may drop under congestion).
- **Donation aura clones** — `CollectionService:AddTag(..., "DonationEffect")` so `SettingsController` scale/hide applies.
- **TitleColorPreset SharedTick** — skips billboard entries beyond `MaxDistance` from camera.
- **Cinematic dock magnifier** — disabled on phone layout and graphics tier ≤ 0.
- **Donation notification marquee** — position updates throttled to ~30 Hz.
- **EffectDonate** — GreenHammer / BlackHole / Blossom / LocalNuke respect `DonationVfxClientGate` after world-effect prefs.

## [2.4.42] - 2026-07-15

### Fixed
- **Join DataStore `budget_exhausted` storm** — join GetAsync no longer runs multi-second `withRetry` backoff inside the shared scheduler slot (`JOIN_READ_RETRY_ATTEMPTS = 1`). Secondary join kinds (settings/stickers/music favorites/likes/favorites) defer `SECONDARY_JOIN_DELAY_SEC` (default 4s). Overhead recovery requeues via ProfileLoader instead of parallel `loadStrict`. Reduces FailedCount / nametag load fails at ~15–25 CCU join storms.
- **Plugin toolbar Check Update / Update Engine** — `plugin-build` previously ran sync via Output only without enabling the DockWidget (`widget.Enabled`), so the panel looked like it only appeared during Play. Toolbar clicks now always `openPanel()` (plus Open Panel button); work is deferred so the dock can paint.

### Added
- **ClubKitConfig fill-forward** — new engine `ClubKitConfigSchema` + runtime merge: buyer keys win; missing keys (Features, JoinCommunity, nested safe sections) filled from schema. `ARRAY_REPLACE_KEYS` keeps buyer lists wholesale (`AuraTiers`, `WorldEffectTiers`, `RoleCategories`, `StyleOrder`, etc.).
- **Update Engine config patch** — after successful engine sync, plugin additively inserts missing `Features` keys and missing top-level sections into buyer `ClubKitConfig` Source (never overwrites existing values); status reports `Config patch: added N key(s)`.

### Changed
- **ClubKitShowcase = dev-only** — moved out of engine tree to `tools/dev/ClubKitShowcase.luau` (not Rojo-synced / not fetched by Update Engine). Demo place: inject ModuleScript under `Shared/Config` manually. Update Engine / Packager destroy any `ClubKitShowcase` under `Hazastudio_ClubKit`.
- **Update Engine UI** — DockWidget uses Studio design `UpdatePluginGUI`/`UpdatePage` (embedded rbxmx): compact dock fonts, **Update engine** / **Stay on this version**. RBXM Packager options card removed from panel (toolbar Export/Unpack keep safe defaults).
- **ProfileLoader join tuning** — `SECONDARY_JOIN_DELAY_SEC`, `RETRY_DELAYS` (aligned with negative-cache TTL); `budget_exhausted` fails the job without holding concurrency for long waits.

## [2.4.41] - 2026-07-15

### Changed
- **Donation cash tab brand** — `ClubKitConfig.Donation.Provider` drives Saweria vs Bagibagi illustration (asset + height + `UIGradient-Gold`), title (`Support us on Saweria!` / `Bagibagi!`), and fixes ScreenGui typo `BagiBagi`.

### Fixed
- **Donation Robux panel** — PaidBroadcast Developer Product ID reliably excluded (tonumber bootstrap + ClubKitConfig fallback + final strip). Optional `Donation.EXCLUDED_ROBUX_PRODUCT_IDS` for extra hides.

## [2.4.40] - 2026-07-15

### Changed
- **Donation Robux panel** — auto/catalog list hides Developer Products that are offsale (`IsForSale ~= true`). Kill switch: `Config.Donation.HIDE_OFFSALE_ROBUX_PRODUCTS = false`. PaidBroadcast product ID also excluded from the donation catalog.

## [2.4.39] - 2026-07-15

### Added
- **NetworkPerf** — `Config.NetworkPerf` kill switches + lightweight 1s counters (`NetworkPerfCounters`) for OverheadUpdate / MusicStateSync / OverheadUI apply rates (`ENABLE_COUNTERS` default off).
- **NetworkManager frame coalesce** — `Config.Network.ENABLE_FRAME_COALESCE` (default on): same target + message kind (+ optional `userId`) keep-last per Heartbeat flush. Immediate paths still `flushNow()`.

### Changed
- **Music DJ sync** — effect / playbackSpeed knobs send effects-only `MusicStateSync` (`kind = djEffects`) with ~12/s trailing coalesce instead of full `getState()` fan-out (`DJ_EFFECTS_DELTA_ONLY`, `DJ_STATE_SYNC_THROTTLE`).
- **Overhead join** — `sendAllExistingTo` proximity-only by default (`OVERHEAD_JOIN_PROXIMITY_ONLY`); distant players still get Snapshot-on-enter.
- **DeltaCompressor** — nested deep-equal when `DEEP_DELTA_NESTED` (default on) so badge/style tables do not inflate deltas.
- **OverheadUI apply** — per-userId keep-last coalesce each Heartbeat; `SKIP_OVERHEAD_UI_APPLY` debug skip.
- **Donation world VFX** — concurrent cap via `DONATION_VFX_MAX_CONCURRENT` (default 1; `0` disables). `WORKSPACE_LB_PAINT_PAUSE` skips workspace SurfaceGui paint for A/B.
- **Cinematic dock topbar** — button stays visible for all ranks; non-admin click does not open the dock and shows a server Notify toast (`You don't have permission to use this feature.`). Broadcast/actions remain server-gated.

### Fixed
- **Freecam cursor lock after exit** — Shift+P toggle raced `FreecamEnabled` attribute (double Stop / wrong `enabled`), then `PlayerState.Pop` restored `MouseBehavior.LockCenter` while Shift still held. Exit now owns attribute sync once and force-unlocks mouse (`Default` + icon) with short re-assert. Same unlock on MobileFreecam stop.
- **Music DJ toggles** — removed global `UserInputService` hit-tests that could toggle DJ mode / FX switches while another music tab was open (overlapping AbsolutePosition). Switches now use a single `Activated` path; input `Active` only while the DJ tab is active.

## [2.4.38] - 2026-07-15

### Added
- **Co-Owner role (kit default)** — Owner-tier badge (`01-OwnerCoOwnerBadge`) + Owner-like permissions; assign only via `/setrole` / aliases `coowner` / `co-owner`. Injected by `RoleCategoryBuilder` even if buyer `RoleCategories` omit it. No group-rank auto-assign.

## [2.4.37] - 2026-07-15

### Changed
- **Shop self-buy → Game Pass** — `BUY_GAMEPASS_ID` / `BuyGamePassId` for one-time membership buy (`PromptGamePassPurchase` + join `UserOwnsGamePassAsync` sync via `grantMembershipIfHigher`). Gift stays Developer Product (`GIFT_ID`). Legacy `BUY_ID` / `BuyId` still honored in `ProcessReceipt` so existing `membershipBadge` buyers and in-flight receipts are safe. Config placeholders `0` until buyer fills ClubKitConfig.

## [2.4.36] - 2026-07-15

### Changed
- **Client Main register headroom** — late-boot `require`s moved to `Client/Init/ClientModuleBag` so `Main.client` stays under the Luau 200-local limit (~184 → ~127 top-level locals).
- **Server Main register headroom** — services/controllers/repos + shared helpers moved to `Server/Init/ServerModuleBag` (`Main.server` ~189 → ~115). MusicBootstrap + PersistenceFabricHooks unchanged.
- **MusicPlayerUIBinder headroom** — cover/title helpers extracted to `MusicPlayerCoverHelpers` (~191 → ~158 top-level locals). Behavior unchanged.
- **Tooling** — `tools/count-locals.ps1` + AGENTS guardrail for the register budget.

## [2.4.35] - 2026-07-15

### Fixed
- **Server Main boot crash (`Out of local registers`)** — Luau 200-local limit hit in `Main.server` when Music enabled (failed at `musicControllerErr`). Persistence Fabric hooks moved to `Init/PersistenceFabricHooks`; Music wiring moved to `Init/MusicBootstrap` so those locals no longer inflate Main's register peak. Restores server boot + remotes (DonationEffect, etc.).

## [2.4.34] - 2026-07-15

### Changed
- **Persistence Fabric** — production DataStore admission + session write-behind + InvalidateBus:
  - Global `DataStoreScheduler` (reserve budget + key mutex); `BudgetGate` adapts to it (`USE_LEGACY_PER_REPO_BUDGET_GATE` kill-switch).
  - Overhead write-behind via `PlayerSessionStore` (debounce flush; skip no-op fingerprints); Settings skip unchanged saves; Favorites/Music leave dirty-only.
  - `CrossServerCache` coalesces `userIds`, skips origin `JobId`, token bucket + MemoryStore soft lease (`USE_LEGACY_CROSS_SERVER_CACHE` kill-switch).
  - AvatarLike skips unchanged OrderedDataStore score / metadata; backfill `ListKeysAsync` gated.
  - `Config.ProfileLoader.MAX_CONCURRENCY` default 8→4. QA: [`docs/PERSISTENCE_FABRIC_QA.md`](docs/PERSISTENCE_FABRIC_QA.md).

## [2.4.33] - 2026-07-14

### Changed
- **Studio live `/removerobux` allowed** — with `USE_STUDIO_DATASTORE_ISOLATION=false`, `/removerobux` can clear production Robux LB from Studio Play; `/setrobux` stays blocked. Warn log on live remove.

## [2.4.32] - 2026-07-14

### Changed
- **Dance panel remembers scroll per tab** — switching Dance ↔ Pose ↔ Favorites restores each tab's last scroll position; search still resets to top; close/reopen keeps last position.

## [2.4.31] - 2026-07-14

### Added
- **Donation rank chip gradient anim** — opt-in `ClubKitConfig.Features.DonationRankGradientAnim` (default off) → `Config.Overhead.ANIMATE_DONATION_RANK_GRADIENT`. Robux = sheen, Rupiah = prism; no-op if wrapper has no `UIGradient`.

## [2.4.30] - 2026-07-14

### Changed
- **Studio DataStore isolation off** — `USE_STUDIO_DATASTORE_ISOLATION = false` in kit Config (and OneTimeLeaderboardSeeder) so Studio Play uses live production keys.
- **ClubKitShowcase excluded from releases** — not fetched by Update Engine; stripped from RBXM pack; removed from place on engine update if present.

## [2.4.29] - 2026-07-14

### Changed
- **Leaderboard displayName one-shot heal** — after UserService resolve, persist `displayNameVerified` to `DonationLeaderboardMetadata_v1` (BudgetGate write-back). DN==username only re-resolves until verified. `LeaderboardIdentity.fetchUserInfos` routes through `HttpApi` (admission/shared cache). Live donation/adjust/seeder writes set verified=true.

## [2.4.28] - 2026-07-14

### Fixed
- **Robux board displayName stuck as username** — `DonationController` called `enrichEntryList` with the module as 1st arg (dot-fn), so enrich was a no-op. Call fixed; when `displayName == username`, identity is re-resolved via UserService using existing `userId` (no re-seed). OneTimeLeaderboardSeeder now uses `UserService:GetUserInfosByUserIdsAsync` instead of non-existent `Players:GetUserDisplayNameAsync`.

## [2.4.27] - 2026-07-14

### Fixed
- **Donation notif flood on boot** — empty v2 notification cursor replayed full cash history (ASC from 1970) each server start. Cold-start now seeds a tip cursor at boot time and keeps `notificationSkipBeforeUnix` for the server lifetime so backlog is not broadcast as live `[DONASI]` chat.

## [2.4.26] - 2026-07-14

### Fixed
- **KitProduct UTF-8 BOM crash** — `KitProduct.luau` had a BOM (`U+FEFF`) that made Luau fail parse (`Expected identifier… U+feff`), cascading ConfigBootstrap / Main / effects load errors. BOM stripped; Manifest cleaned the same way.

## [2.4.25] - 2026-07-14

### Changed
- **Dance per-tier preload budget (Phase 4)** — tier1 / tier2 budgets inside `DANCE_PRELOAD_MAX_ASSETS` (`TIER1_BUDGET=12`, `TIER2_BUDGET=20`). Full warmup uses tier1 then tier2 instead of one flat dump. Kill switch: `Config.Sync.USE_LEGACY_FLAT_PRELOAD_BUDGET = true`.
- **Server dance track prewarm admission** — max 2 concurrent characters + ~24 loads/sec globally; cancel on leave / character swap.
- **Donation leaderboard rebuild coalesce** — trailing 5s rebuild/paint for donation updates; skip paint when fingerprint unchanged; missing-board paint retries capped at 3.

## [2.4.24] - 2026-07-14

### Changed
- **TitleColorPreset shared tick (Phase 3)** — Gradient / Stroke / Dropshadow use one ~30Hz shared Heartbeat instead of one per instance. `SKIP_HIDDEN` skips ticks when title/GUI ancestors are not visible. Kill switch: `Config.TitleColorPreset.USE_LEGACY_PER_INSTANCE_HEARTBEAT = true`.

## [2.4.23] - 2026-07-14

### Changed
- **Interest radius (Phase 2)** â€” proximity subscribe enter default **80â†’55** studs, hysteresis buffer **20â†’15** (leave at 70). Cuts overhead/sync Recv at high CCU while still covering Medium nametag (48). Kill switch: `Config.Interest.USE_LEGACY_VIEW_RANGE = true` restores 80/20.

## [2.4.22] - 2026-07-14

### Fixed
- **Settings update rejected: payload too large** â€” SettingsUpdate uses `Config.Settings.MAX_PAYLOAD_BYTES` (8KB) instead of Security 1KB, so full settings saves (e.g. hide world effect) work.
- **HTTP API throttle spiral** â€” `HttpApi` negative-caches failures, caps concurrent Roblox API calls (`MAX_CONCURRENT`), and waiters no longer fall through to retry after a failed leader fetch.
- **LeaderboardIdentity double-API** â€” no immediate legacy `Players` UserInfos / `GetNameFromUserIdAsync` after UserService failure; negative-cache and retry later.
- **Overhead getGroups** â€” respects negative cache; no wait-then-retry storm on failure.

### Changed
- **`Config.HttpApi`** â€” `ADMISSION_ENABLED`, `MAX_CONCURRENT=4`, `NEGATIVE_CACHE_TTL=30` (kill-switchable).

## [2.4.21] - 2026-07-14

### Fixed
- **Leaderboard UserService storm** â€” workspace enrich now slices to paint limits (20) before identity resolve; `LeaderboardIdentity` no longer treats DisplayName==Username as stale, batches UserService lookups, and caches success/failure. Likes/robux repos stop unconditional identity/thumbnail API calls (prefer `rbxthumb://`).
- **Overhead GroupService storm** â€” proximity snapshot-on-enter reuses cached/S1 payload instead of full rebuild; `OverheadService.getGroups` self-caches even when HttpApi was previously off.

### Changed
- **`Config.HttpApi.ENABLED = true`** â€” TTL cache + dedup for GroupService/Players wrappers; `getUserInfosByUserIdsAsync` uses a real multi-id batch.
- **Dance preload cap** â€” `DANCE_PRELOAD_MAX_ASSETS = 32` applies to tier1/tier2/full ContentProvider preload (cuts client Animation RAM from full-catalog warmup). `SERVER_DANCE_TRACK_PREWARM_MAX` 10â†’8.

## [2.4.20] - 2026-07-13

### Fixed
- **Leaderboard LoadingOverlay double text** â€” client no longer starts a second loading-text animation when `CLIENT_PAINT_DATA` is false (server-only paint). Fixes stacked/ghost cycling messages on one overlay label.

### Changed
- **Music library scroll performance** â€” virtual track lists coalesce redraws to 1/frame, recycle rows by track id (free-list), use fixed single-line titles, debounce search (~180ms), skip playlist enter tweens on refresh, and normalize list covers to `rbxthumb` 150Ã—150 (client + new server history writes).

## [2.4.19] - 2026-07-13

### Added
- **F9 console Hazastudio banner** â€” ASCII art + kit version + contact (`KitProduct.Support`) printed once on client/server boot.
- **Workspace leaderboard setup checker** â€” `tools/CheckWorkspaceLeaderboardSetup.editmode.luau` audits board/poster/marquee names + GUI hierarchy (LoadingOverlay, cards, template) vs paint contract.
- **Workspace leaderboard runtime probe** â€” `tools/ProbeWorkspaceLeaderboardRuntime.playmode.luau` (Play + Command Bar) dumps LoadingOverlay/MainContent visibility, which overlay TextLabel kit would pick, and top-card sample text after paint.

### Changed
- **Production logs quieter** â€” Logger gates DEBUG/INFO/WARN in live; ERROR emits as red (`TestService:Error`) without throwing. Client Main boot noise (`print`/`warn`) Studio-only.

## [2.4.18] - 2026-07-13

### Fixed
- **Music topbar setMenu crash** â€” stopped re-applying `setMenu` on every icon show (TopbarPlus was destroying menu children by stale UID â†’ `attempt to index nil with 'destroy'` / `noticeChanged`). Added nil-guards in Icon Menu/Dropdown/toggled handlers.

## [2.4.17] - 2026-07-13

### Added
- **Music topbar Load Track** â€” music icon opens a horizontal TopbarPlus `setMenu` with **Music Player** (opens panel) and **Load Track** (hard `resyncPlayback` without rejoin). Honest toasts for muted Settings volume / still loading / idle.

### Changed
- **TopbarPlus labels use Inter** â€” kit `styleTopbarPill` applies font asset `rbxassetid://12187365364` (including music menu children).
- **Topbar Menu button shows "Menu" label** â€” uses `Config.TopbarMenu.LABEL` (was icon-only).

### Fixed
- **Music Load Track / resync** â€” manual resync now force-stops tracked sounds before GetState + restart; fade-in completion re-asserts store volume so a stuck fade cannot leave Volume at 0.
- **VIP on community join not applying mid-session** â€” after JoinCommun `PromptJoinAsync`, Roblox `IsInGroup` often lags past the old ~6s server wait, so Tier1 was only granted on place rejoin. Server now waits longer, schedules follow-up grants, invalidates group cache, and refreshes overhead in `recovery` mode; client fires delayed `CommunityVipRecheck` retries (and one recheck on "Already joined").
- **OverheadGui full placeholders on respawn** â€” respawn briefly enabled the raw BillboardGui template before a payload paint, and proximity could drop self mid-respawn so recovery had zero recipients. Server keeps GUI disabled until clients apply data, always includes the subject in broadcast recipients, and client re-seeds pending payload from cache on `CharacterAdded`.

## [2.4.16] - 2026-07-12

### Changed
- **Version bump for engine sync** ï¿½ empty release; no feature or bugfix changes. Use plugin **Update Engine** to pull kit `2.4.16`.

## [2.4.15] - 2026-07-12

### Added
- **VIP on community group join** ï¿½ feature flag `Features.VipOnCommunityJoin` (default `false`). When enabled and `Group.GroupId > 0`, players who `IsInGroup` get Tier1 VIP (`membershipBadge`, same path as shop buy). Also re-checks after JoinCommun `PromptJoinAsync` via `CommunityVipRecheck` remote (server-authoritative). Buyer must set `Features.VipOnCommunityJoin = true` in `ClubKitConfig` (manual merge; source sync does not replace config).

## [2.4.14] - 2026-07-12

### Fixed
- **Join Community button label** - CTA text ("Join Community" / "Already joined") writes to nested `JoinCommunityButton > TextLabel` instead of only `TextButton.Text` (Studio layout uses the child label).
- **Join greeting CountDownBar color** - no longer applies role accent / overwrites `BackgroundColor3` or Studio `UIGradient`; bar keeps designer colors while width/progress timing unchanged.

## [2.4.13] - 2026-07-12

### Changed
- **Join greeting title + chip amount** - second line is `{Gelar} {DisplayName} has entered the space!` (not Welcome back). Role greetings (Owner / Leadership / Content and any roles in those categories) use that role's **display title** from Roles config. Top Robux / Top Cash greetings use `Top Spender #N` / `Top Donor #N` (`Config.JoinGreeting.GELAR_TITLES`). Spender toasts also send `amount` / `amountText` / `amountKind` from overhead totals and show the total on the Universal chip (`Versatilechiptext` append, or a dedicated Amount/Value/Robux/Cash label if present).

## [2.4.12] - 2026-07-12

### Changed
- **Join Community modal always shows** - `16-JoinCommunPrompt` opens after gameplay even if the player is already in the group (feature flag + `GroupId > 0` unchanged). Already-in-group CTA uses `BUTTON_ALREADY_JOINED` ("Already joined") and dismisses without `PromptJoinAsync`; non-members keep `BUTTON_JOIN` ("Join Community") then PromptJoinAsync.
- **Join greeting duration ~7s** - `Config.JoinGreeting` MESSAGE_HOLD 3.7 + MESSAGE_FADE 0.25x2 + WELCOME_HOLD 2.8 so the toast CountDownBar runs ~7 seconds (was ~15s).

## [2.4.11] - 2026-07-12

### Fixed
- **NukeWorldPosition ignored by LocalNuke** - active EffectDonate rocket used hardcoded `SPAWN_POSITION` + required `workspace.NukeModel`; `ClubKitConfig.Donation.NukeWorldPosition` only fed disabled `NukeEffectController`. Descent/impact now uses `Config.Donation.NUKE_WORLD_POSITION`; launch pad falls back to that stage if `NukeModel` is missing. BlackHole / GreenHammer / Blossom stage anchors also read the same config.
- **Double Join Greeting** - server claimed an in-flight lock before yielding `getPayload` (`buildPayload`), so concurrent `onPlayerReady` + cash `onPayloadUpdated` could both fire the same RoyaleSpender toast ~1s apart. Client also ignores duplicate remotes per joiner for the session.

### Changed
- **game-data `/community` allowlist** - Join Commun worker endpoint now accepts any authenticated `gameKey` (empty `COMMUNITY_ENABLED_GAMES`); secret auth unchanged. Clients like `night-zone` only need matching `GameKey` + `GameDataApiSecret`.

## [2.4.10] - 2026-07-12

### Fixed
- **Join Commun +99 / "others" missing** - when game-data `/community` returned members but Open Cloud meta omitted/`0`-coerced `memberCount`, the kit treated the total as known-empty (or skipped roproxy after worker OK) so body used `BODY_THREE` without others and hid `CounterLeft`. Now: worker sends `null` + `memberCountKnown`; kit rejects inconsistent `0` + samples and falls through to `MEMBER_INFO_URL` for count; client DEBUG log once (`memberCount`, `memberCountKnown`, `remainder`, `counterFound`).

## [2.4.9] - 2026-07-12

### Changed
- **Join Commun CounterLeft** - badge shows remainder after 8 thumbs (`memberCount - 8`) whenever count is known and > 8; display capped at `+99` (no k/M/B on the badge).
- **Join Commun body with names** - up to 3 names + compact remaining (`Name1, Name2, and Name3 and 10.6M others already joined this community.`) via `BODY_WITH_NAMES` (k/M/B OK in body, not +99-capped).

### Fixed
- **Join Commun roproxy 429 noise** - when game-data `/community` succeeds (members and/or count/emblem), the same resolve no longer falls through to `MEMBER_INFO_URL` / `MEMBER_USERS_URL`. Roproxy is only used when the worker is skipped (no secret) or failed. HTTP 429 on `MEMBER_INFO_URL` logs DEBUG once with short backoff instead of WARN spam.

---

## [2.4.8] - 2026-07-12
### Added
- **Join Commun via game-data worker** - preferred source for Join Community modal data is now `GET /game/:gameKey/community/:groupId` on the game-data-api worker (Open Cloud + cached). Returns `memberCount`, `members[]` (display names), optional `emblemUrl` in one call. Allowlist includes `the-basic` (+ `nuwa`). Requires `Secrets.GameDataApiSecret` + deployed worker; Studio without secret still falls back to roproxy `MEMBER_INFO_URL` / `MEMBER_USERS_URL` (DEBUG skip log).

### Fixed
- **Join Commun thumbs HTTP 400** - hardened `MEMBER_USERS_URL` fetch for huge groups (e.g. 3996161): default `sortOrder=Asc` (not Desc), clamp limit without using `POOL_SIZE=40`, retry Asc/no-sort/`limit=100`, then fallback `GET /v1/groups/{id}/roles` — `/roles/{roleSetId}/users`. Fail log always includes final `url`, `statusCode`, `body`, `kitVersion` (once). Note: Roblox HttpService locks `User-Agent` (cannot set browser UA).

---

## [2.4.7] - 2026-07-12

### Fixed
- **Join Commun thumbs empty** - `MEMBER_USERS_URL` used `limit=40`, but Roblox Groups `/v1/groups/{id}/users` only accepts `limit` in `{10, 25, 50, 100}` -> HTTP 400 and `remoteUsers=0`. Default is now `limit=50`; service clamps any template `limit=` to the nearest valid page size. Failed users requests log a truncated response body once (via `RequestAsync`).

---

## [2.4.6] - 2026-07-12


### Changed
- **Join Commun copy** - social strip no longer repeats the raw MemberCount on subtitle and body. Subtitle stays qualitative (`Players already in this community.`); body carries a compact count once (`Over 10.6M players already joined.` / light alt pool). VIP TITLE/SUBHEADLINE unchanged.
- **Join Commun counts** - MemberCount / CounterLeft / body extras use compact `k`/`M`/`B` (e.g. `10589188` -> `10.6M`, `1200` -> `1.2k`).
- **Join Commun thumbs** - server fetches one page of group members via `MEMBER_USERS_URL` (default `groups.roproxy.com/.../users?limit=40`), O(k) sample of 8, 300s cache; in-experience pool is secondary fill. Requires `HttpEnabled` (same as count). No Http to `*.roblox.com`.

### Fixed
- **Join Commun MemberCount log noise** - missing engine `MemberCount` is expected; log demoted to DEBUG once (fallback to `MEMBER_INFO_URL` unchanged).

---

## [2.4.5] - 2026-07-12

### Changed
- **Join Commun logo (JoinCommun-only)** - `16-JoinCommunPrompt` `CommunityLogo` now prefers the Roblox **group emblem** (`GroupService:GetGroupInfoAsync` -> `EmblemUrl`, or `rbxthumb` GroupIcon when info succeeds but the field is omitted), then optional `MEMBER_INFO_URL` / roproxy JSON `emblemUrl` via `JoinCommunityMembersService`, then soft fallback to `Branding.LogoImage`, then the Studio GUI default. BrandLogoApplier no longer stamps Branding onto JoinCommun; shop / overhead / boards / other `CommunityLogo` targets are unchanged.

### Fixed
- **Join community MemberCount** - `GroupService:GetGroupInfoAsync` usually has **no** `MemberCount` field (official docs omit it), so v2.4.4 cached `0` and the modal showed "Be among the first.". Now: warn once when the field is missing/fails; never treat online/pool size as the community total; resolve real total via optional `MEMBER_INFO_URL` (default `groups.roproxy.com` group-info JSON, or buyer worker / `ClubKitConfig.JoinCommunity.MemberInfoUrl`). Payload includes `memberCountKnown`. Empty thumbs with known count > 0 use "%d players already joined."; unknown count uses neutral `BODY_NO_COUNT` (not a false empty claim). Full random roster still needs a proxy - game servers cannot Http `groups.roblox.com`.

---

## [2.4.4] - 2026-07-12


### Fixed
- **Join community roster** - stop calling `groups.roblox.com` via HttpService (Roblox blocks Http to own domains even with `HttpEnabled`). MemberCount stays on `GroupService:GetGroupInfoAsync`; avatar strip samples an in-experience pool of community members seen in this place (PlayerAdded + online warm), with optional MemoryStore cross-server share. Client online in-group merge unchanged.

## [2.4.3] - 2026-07-12

### Changed
- **Join community member samples** - social strip shows a **random** sample of players already in the community. Efficient path: **1** Http page (pool ~40), `GroupService` for MemberCount, **300s cache**, O(k) random pick (no full shuffle / no multi-page crawl); client server-first (skips mass `IsInGroupAsync` when sample is full). Pre-warm delayed 12s after boot. Requires `HttpService.HttpEnabled`.
- **Join community headline** - keep VIP incentive on title/subheadline (`Join our community, and get free VIP.` / `Limited time, save up to 50 Robux.`); only the member strip uses community-join wording.

---

## [2.4.2] - 2026-07-12

### Changed
- **Join community copy** - drop VIP framing; modal uses community-join wording (`Join our community.` / `...already joined this community`) via `Config.JoinCommunityPrompt` TITLE/SUBHEADLINE/BODY_* (overwrites Studio placeholders on open).
- **Join greetings after loading** - client holds greeting toasts until `enterGameplay` (loading dismiss + cinematic camera reveal finished), then plays full ~15s sequence so the toast is not burned during the loading click wait.

---

## [2.4.1] - 2026-07-12

### Fixed
- **Join community modal placeholders** - `CommunityLogo` now follows `ClubKitConfig.Branding.LogoImage` (NAME_MATCH + explicit set on open); avatar strip fills from online in-group members then server-fetched group roster (Http via `JoinCommunityMembersService`); `Subtitle` / `Body` use live MemberCount + up to 3 display names; `CounterLeft` only when MemberCount > 8.

### Changed
- **Join greeting duration ~15s** - `Config.JoinGreeting` MESSAGE_HOLD 8.0 + WELCOME_HOLD 6.3 (+ fades) so the toast CountDownBar runs ~15 seconds (was ~5s).
- **Buyer must set community logo** - set `ClubKitConfig.Branding.LogoImage` to your community logo asset (not the kit default `79426970537296`). Engine applies it to loading/poster/boards **and** the Join Community modal `CommunityLogo`.

---

## [2.4.0] - 2026-07-12


### Added
- **Join greeting notifications** — when Owner, Leadership (category id 1), Content (category id 3), top-10 Robux, or top-10 cash spender joins, all clients see a `GreetingNotifications` / `GeneralGreetings` toast (once per session). Role eligibility follows `ROLE_TO_CATEGORY` (buyer-added Leadership/Content roles auto-greet). Toggle: `Features.JoinGreetings` (default on). Sequence: creative message -> fade -> `Welcome back, ?` (Owner: `Welcome back, owner {DisplayName}`) -> dismiss. Toast motion reuses **GenericBroadcast** enter/exit (`UIScale` 0.84->0.9 / 0.81, `GroupTransparency`, Quad 0.28/0.22) + linear **CountDownBar** with role accent; message swap uses `TextTransparency` crossfade (no abrupt `Visible` toggles). Template must be a `CanvasGroup`.

### Changed
- **Join community on load** — after loading/`enterGameplay`, wait 2s then show custom `16-JoinCommunPrompt` with **Shop/Gift/PaidBroadcast** center-modal motion (`AnimationHelper.presentCenterPanel` / `dismissCenterPanel`: UIScale 0.96->1 Sine, PanelBlur + FOV zoom). **Skip entirely if already in group** (no auto CoreGui). Join CTA dismisses modal first, then `GroupService:PromptJoinAsync`; Close dismisses only. Avatar strip clones up to 8 in-server member headshots; `CounterLeft` `+(total-8)` only when group member count > 8. Replaces v2.3.1 auto-`PromptJoinAsync` after 0.75s. Toggle / `GroupId` gates unchanged. Missing GUI -> warn + skip (no CoreGui fallback).

---

## [2.3.1] - 2026-07-12



### Added
- **Prompt join community on load** — after loading/`enterGameplay`, client shows Roblox `GroupService:PromptJoinAsync` for `ClubKitConfig.Group.GroupId` (once per session, always prompt even if already a member). Toggle: `Features.PromptJoinCommunityOnLoad` (default on); skipped when `GroupId` is `0`.

---

## [2.3.0] - 2026-07-11

### Fixed
- **ProcessReceipt money safety** — in-memory purchase dedupe marked only after `PurchaseGranted` (paid broadcast / buy / gift / Robux no longer skip retries after a failed side-effect); shop gifts **peek** pending then **consume after** successful `grantMembership`; Robux LB receipt uses **intent-before-Increment** (`userIncrementStarted` / `communityIncrementStarted`) so progress-fail after Increment cannot double-credit; community credit frozen from receipt claim `communityId` on resume.
- **Studio DataStore isolation restored (safe default)** — `USE_STUDIO_DATASTORE_ISOLATION = true` prefixes `Studio_*` keys in Studio Play; set the flag `false` in `Config.luau` only for intentional live-key debug (manual `/setrobux` etc. blocked while writing live). Boot log distinguishes isolated vs live-from-Studio.
- **Loading enterGameplay miss** — if LoadingScreenUI never attaches (or already finished), client still calls `enterGameplay` so DanceWarmup / `ClientGameplayReady` are not stuck.
- **Robux/community LB cache cross-server** — write path publishes MessagingService invalidation so other shards drop local + MemoryStore LB keys (not only the writing server).
- **Overhead / AvatarContext CharacterAdded** — per-player connection maps Disconnect on `PlayerRemoving` (session LuaHeap hygiene).
- **World VFX memory leaks** — client single-flight (`WorldEffectFlight`) aborts prior Nuke/Smite4/BlackHole (Destroy clones, stop sounds, disconnect Heartbeats/markers, restore Lighting); BlackHole always `impactVisuals:Destroy()`; AvatarPrewarmPool generation tokens ignore stale loads + Destroy-on-overwrite; UI/DJ/broadcast sounds use `Sound:Play()` + Ended/Debris (not orphaning `PlayLocalSound`).
- **Gravity / Ungravity scope + permission** — `/ungravity` and `/gravity` (plus Shift+U / Shift+G) now affect **all players** on the server (including joiners while float mode is active), and are gated to **Owner / Leadership** (`PermissionDomain.canUseAdminPanel` — same gate as Admin panel). Regular players no longer get self-float.
- **DataStore join storm** — live ~4-player joins no longer flood the request queue from boot LB pre-warm + parallel Settings/Stickers/MusicFavorites GetAsync + double SharedProfileLoader enqueue + streak UpdateAsync when already counted.

### Changed
- **World VFX server queue** — `WORLD_EFFECT_DURATIONS` per effect (Nuke 90s / Smite4 180s / BlackHole 240s); `NUKE_DEFAULT_DURATION` 20->90. Worker always waits after broadcast. NukeEffectController stays disabled (would double VFX).
- **LocalNuke fireworks** — `FIREWORK_COUNT` 140->40 (temp PlaceMemory spike).
- **Leaderboard boot pre-warm** — paint empty/loading boards immediately; defer heavy `buildWorkspaceLeaderboardPayload` (~25s); likes metadata GetAsync capped at 20 (identity fallback beyond).
- **Join reads** — Settings / Stickers / Music favorites fold into SharedProfileLoader; SyncDance favorites registered before first enqueue (no second enqueue).
- **Studio DataStore** — default isolation again (reverses v2.2.2 "Studio = live" for safety). Opt into live keys explicitly via `USE_STUDIO_DATASTORE_ISOLATION = false`.

---

## [2.2.9] - 2026-07-11

### Changed
- **Music topbar** — moved to the right strip, leftmost order (left of Command): Music -> Command -> Admin -> Menu.
- **Community leaderboard credit** — Robux donations use the same effective community as badges: `/setcommun` **or** primary Roblox group (when `PRIMARY_FALLBACK_ENABLED` and not yet `/clearcommun`).

---

## [2.2.8] - 2026-07-11

### Fixed
- **Donation panel rank flicker** — do not clear/`#-` on failed rank lookup; `assignRobuxTopDonate` align limit 100 + skip miss; `getDonorProfile` uses `getPlayerRobuxRank`; panel merges overhead so nil rank does not overwrite `#N` when total > 0. Clear rank when total is actually 0 still works (v2.2.7).
- **Duplicate role team/chat colors** — `RolesDomain` auto-remaps conflicting `teamColor` + `roleColor.primary` (buyer ClubKitConfig) so PlayerList/leaderboard teams and chat tags stay unique.

### Changed
- **Default music volume** — 50% -> **100%** (settings + music player store). Existing saves still on old default **50** are migrated once to **100**.
- **Cinematic/freecam topbar icon** — `Icons.Topbar.Camera` -> `rbxassetid://131545412033411` (menu cinematic + MobileFreecam HP).
- **Carry template anim IDs** — `ClubKitConfig.Carry` kit template uses buyer anims (6 kit style names; legacy CoupleHug/Pasakal/PiggyUpperBack removed from template).

---

## [2.2.7] - 2026-07-11

### Fixed
- **Donation panel rank sticky** — merge no longer keeps `#N` when total is already 0; overhead also drops rank chip when donated = 0; `/removerobux` invalidate + refresh overhead.

---

## [2.2.6] - 2026-07-11

### Fixed
- **Branding.LogoImage** — logging target vs default; support ImageButton + names `LogoImage`/`ClubLogo`; re-apply after workspace board paint.

---

## [2.2.5] - 2026-07-11

### Added
- **Branding.LogoImage** — set club logo once in `ClubKitConfig.Branding.LogoImage`; boot auto-applies to ImageLabels still using kit default ID (`79426970537296`) on loading / poster / leaderboard.

---

## [2.2.4] - 2026-07-11

### Fixed
- **Dance favorites 1KB cap** — `Validator.favoritesUpdate` no longer uses `Security.MAX_PAYLOAD_BYTES` (1KB command); dedicated limit `Config.Favorites.MAX_PAYLOAD_BYTES` = 32KB (~54 favorites case). Rate limit `FAVORITES_UPDATE` 5/5s -> 15/5s.
- **Donation burst poll** — `getNotifPollDelay` (5s / 45s window) now wired to `BackgroundJobScheduler:setInterval` after each `donation_poll` (previously dead after scheduler migration).
- **Cash LB overhead** — removed routine `refreshAll` after leaderboard sync; `assignPlayer`/`clearPlayer` already call `refreshPlayer` (force path unchanged).
- **Donation notif queue** — backlog shortens display; when full, evict smallest amount in queue (not drop large new donations).

### Added
- **Studio clear-self donation** — `/removecash me` / `/removerobux me` (or `@me`) clears your own donation data; **Studio-only**. Live still uses username/userId (owner).

---

## [2.2.3] - 2026-07-11

### Fixed
- **Gravity / Ungravity naming** — `/ungravity` (+ Shift+U) = float; `/gravity` (+ Shift+G) = restore. Previously keybind & `/gravity N` were reversed in meaning.
- **Ungravity -> gravity drop** — restore no longer zeroes Y (float first); immediately kicks downward + Freefall for faster descent.

---

## [2.2.2] - 2026-07-11

### Changed
- **DataStore: Studio = live** — removed `Studio_*` prefix / isolation; Play in Studio uses the same production keys so testing mirrors live (writes from Studio affect real data).
- **PlayerList TeamColor unique** — runtime auto-remaps BrickColor when config roles collide, so players do not land on the wrong team in Roblox leaderboard.

---

## [2.2.1] - 2026-07-11

### Fixed
- **Source sync Script.Source limit** — `MusicPlayerUIBinder.luau` (247k) exceeded Roblox 200k limit; split into `MusicPlayerUIBinderPart2.luau` so Update Engine plugin can write Source.

### Changed
- **Music player UI source split** — late methods load from sibling ModuleScript; binder API unchanged.

---

## [2.2.0] - 2026-07-11

### Added
- **Gravity / Ungravity** — float mode per player: Shift+G (float), Shift+U (restore), `/gravity 0-10`, `/ungravity`. Dance/sync still works; fall anim suppressed.

### Fixed
- **Music topbar icon** — logo could disappear while music played (global mode): `MusicTopbarIcon.show()` is now idempotent, restores parent via `alignmentHolder`, and re-asserts after panel boot.

### Changed
- Packager plugin layout — source in `tools/ClubKitPackagerPlugin/plugin/`, build output in `plugin-build/`

---

## [2.1.0] - 2026-07-10

Studio plugin **Git source sync** — update engine Luau from GitHub tag without export/upload RBXM.

### Added
- `SourceSyncCore`, `RojoPathMap` — fetch `.luau` from GitHub tag, write `Source` to place
- Dovetail UI: `UpdaterPanel`, `PackagerPanel`, `DovetailTheme`, `DovetailUI`
- Toolbar **Check Update** + **Update Engine**
- `tools/release.ps1` — validate version + git tag/push from Cursor
- `RolesDomain.buildStudioToolFolderList` — include membership tool folders

### Changed
- Packager plugin refactor — separate panels, Dovetail dark theme widget
- `EnsureRoleToolFolders` — delegates to shared studio module

---

## [2.0.0] - 2026-07-10

Initial git baseline + dev v2 release. Continues from v1.3 handover with latest session fixes.

### Added
- Git version control (portable MinGit + `git.ps1`)
- Release workflow: `AGENTS.md`, `CHANGELOG.md`, `UPGRADE_PROGRESS.md`, `.cursor/rules/clubkit-versioning.mdc`

### Fixed
- `/re` — refresh avatar via `LoadCharacter()` + restore position & dance sync
- Command GUI — keyboard no longer stuck in textbox after panel close (PC/laptop)
- Mobile freecam — avatar body no longer moves when camera is moved
- Circular require crash on boot — `DonationProviderDomain` lazy-requires `Config`

### Changed
- Rate limit session commands `/re` etc.: `3` -> `10` per 30 seconds (`Config.Session.RATE_MAX`)
- Product version: `1.3.0` -> `2.0.0` (new semver track for git-based upgrades)

---

## [1.3.0] - 2026-07-09

Handover baseline release. Audit & fix details: [`HANDOVER.md`](HANDOVER.md).

### Added
- Donation provider preset (`bagibagi` / `saweria`)
- `DonationCash` pipeline + leaderboard seeder tool
- Split `AuraTiers` + `WorldEffectTiers`

### Fixed
- Critical audit C1–C6, high severity H1–H13 (see HANDOVER)

[Unreleased]: compare with VERSION + UPGRADE_PROGRESS.md
[2.4.73]: docs/releases/2.4.73/
[2.4.72]: docs/releases/2.4.72/
[2.0.0]: docs/releases/2.0.0/
[1.3.0]: HANDOVER.md
