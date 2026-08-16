# Changelog

All notable Club Kit changes are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

Active version: see [`VERSION`](VERSION).

---

## [Unreleased]

### Changed
- **AFK rejoin syncs solo dancers to the top leader** — previously only players who were *following a leader* before the rejoin were re-synced (last leader → top-leader fallback); a player dancing **solo** was restored solo and never pulled into the group. Now a solo dancer also tries the current top leader (most followers, dancing) on rejoin, so the floor converges on the biggest group. Fully-idle players (no animation) are still left alone, and the whole fallback is gated by the existing `SYNC_FALLBACK_TOP_LEADER` (set false to disable). The top-leader attempt was factored into a shared helper used by both the last-leader-fallback and solo-dancer paths.

### Added
- **Seamless AFK rejoin** — an AFK auto-rejoin now lands without replaying the first-join interruptions. New `Shared/Session/RejoinMode.luau` reads the `afkRejoin` flag from the teleport data once (client-side, previously server-only; reads both `GetJoinData().TeleportData` and `GetLocalPlayerTeleportData()`) and three consumers branch on it: `LoadingBootstrap` skips the loading screen entirely on rejoin (waits for the Session/RejoinMode module to replicate before deciding, so the skip is not lost to a replication race), `JoinCommunityPromptController.tryPromptAfterGameplay` never shows the join modal on rejoin (it still shows on a normal join for non-members), and `Main.client` bypasses the music-engine start delay and forces dance warmup to run immediately so `SyncService.restoreAfterAfkRejoin` re-syncs to the last dance/leader without the usual post-gameplay defer. Normal joins are unaffected (loading screen, prompt, and warmup schedule all unchanged when the flag is absent).

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
