# Changelog

Semua perubahan penting Club Kit dicatat di sini.

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versi mengikuti [Semantic Versioning](https://semver.org/).

Versi aktif: lihat file [`VERSION`](VERSION).

---

## [Unreleased]

## [2.4.33] - 2026-07-14

### Changed
- **Studio live `/removerobux` allowed** — with `USE_STUDIO_DATASTORE_ISOLATION=false`, `/removerobux` can clear production Robux LB from Studio Play; `/setrobux` stays blocked. Warn log on live remove.

## [2.4.32] - 2026-07-14

### Changed
- **Dance panel remembers scroll per tab** — switching Dance ↔ Pose ↔ Favorites restores each tab's last scroll position; search still resets to top; close/reopen keeps last position.

## [2.4.31] - 2026-07-14

### Added
- **Donation rank chip gradient anim** — opt-in `ClubKitConfig.Features.DonationRankGradientAnim` (default off) → `Config.Overhead.ANIMATE_DONATION_RANK_GRADIENT`. Robux = sheen, Rupiah = prism; no-op jika wrapper tanpa `UIGradient`.

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
- **Join greeting gelar + chip amount** - second line is `{Gelar} {DisplayName} has entered the space!` (not Welcome back). Role greetings (Owner / Leadership / Content and any roles in those categories) use that role's **display title** from Roles config. Top Robux / Top Cash greetings use `Top Spender #N` / `Top Donor #N` (`Config.JoinGreeting.GELAR_TITLES`). Spender toasts also send `amount` / `amountText` / `amountKind` from overhead totals and show the total on the Universal chip (`Versatilechiptext` append, or a dedicated Amount/Value/Robux/Cash label if present).

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
- **Join Commun thumbs HTTP 400** - hardened `MEMBER_USERS_URL` fetch for huge groups (e.g. 3996161): default `sortOrder=Asc` (not Desc), clamp limit without using `POOL_SIZE=40`, retry Asc/no-sort/`limit=100`, then fallback `GET /v1/groups/{id}/roles` ? `/roles/{roleSetId}/users`. Fail log always includes final `url`, `statusCode`, `body`, `kitVersion` (once). Note: Roblox HttpService locks `User-Agent` (cannot set browser UA).

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
- **Join greeting notifications** ? when Owner, Leadership (category id 1), Content (category id 3), top-10 Robux, or top-10 cash spender joins, all clients see a `GreetingNotifications` / `GeneralGreetings` toast (once per session). Role eligibility follows `ROLE_TO_CATEGORY` (buyer-added Leadership/Content roles auto-greet). Toggle: `Features.JoinGreetings` (default on). Sequence: creative message -> fade -> `Welcome back, ?` (Owner: `Welcome back, owner {DisplayName}`) -> dismiss. Toast motion reuses **GenericBroadcast** enter/exit (`UIScale` 0.84->0.9 / 0.81, `GroupTransparency`, Quad 0.28/0.22) + linear **CountDownBar** with role accent; message swap uses `TextTransparency` crossfade (no abrupt `Visible` toggles). Template must be a `CanvasGroup`.

### Changed
- **Join community on load** ? after loading/`enterGameplay`, wait 2s then show custom `16-JoinCommunPrompt` with **Shop/Gift/PaidBroadcast** center-modal motion (`AnimationHelper.presentCenterPanel` / `dismissCenterPanel`: UIScale 0.96->1 Sine, PanelBlur + FOV zoom). **Skip entirely if already in group** (no auto CoreGui). Join CTA dismisses modal first, then `GroupService:PromptJoinAsync`; Close dismisses only. Avatar strip clones up to 8 in-server member headshots; `CounterLeft` `+(total-8)` only when group member count > 8. Replaces v2.3.1 auto-`PromptJoinAsync` after 0.75s. Toggle / `GroupId` gates unchanged. Missing GUI -> warn + skip (no CoreGui fallback).

---

## [2.3.1] - 2026-07-12



### Added
- **Prompt join community on load** ? after loading/`enterGameplay`, client shows Roblox `GroupService:PromptJoinAsync` for `ClubKitConfig.Group.GroupId` (once per session, always prompt even if already a member). Toggle: `Features.PromptJoinCommunityOnLoad` (default on); skipped when `GroupId` is `0`.

---

## [2.3.0] - 2026-07-11

### Fixed
- **ProcessReceipt money safety** ? in-memory purchase dedupe marked only after `PurchaseGranted` (paid broadcast / buy / gift / Robux no longer skip retries after a failed side-effect); shop gifts **peek** pending then **consume after** successful `grantMembership`; Robux LB receipt uses **intent-before-Increment** (`userIncrementStarted` / `communityIncrementStarted`) so progress-fail after Increment cannot double-credit; community credit frozen from receipt claim `communityId` on resume.
- **Studio DataStore isolation restored (safe default)** ? `USE_STUDIO_DATASTORE_ISOLATION = true` prefixes `Studio_*` keys in Studio Play; set the flag `false` in `Config.luau` only for intentional live-key debug (manual `/setrobux` etc. blocked while writing live). Boot log distinguishes isolated vs live-from-Studio.
- **Loading enterGameplay miss** ? if LoadingScreenUI never attaches (or already finished), client still calls `enterGameplay` so DanceWarmup / `ClientGameplayReady` are not stuck.
- **Robux/community LB cache cross-server** ? write path publishes MessagingService invalidation so other shards drop local + MemoryStore LB keys (not only the writing server).
- **Overhead / AvatarContext CharacterAdded** ? per-player connection maps Disconnect on `PlayerRemoving` (session LuaHeap hygiene).
- **World VFX memory leaks** ? client single-flight (`WorldEffectFlight`) aborts prior Nuke/Smite4/BlackHole (Destroy clones, stop sounds, disconnect Heartbeats/markers, restore Lighting); BlackHole always `impactVisuals:Destroy()`; AvatarPrewarmPool generation tokens ignore stale loads + Destroy-on-overwrite; UI/DJ/broadcast sounds use `Sound:Play()` + Ended/Debris (not orphaning `PlayLocalSound`).
- **Gravity / Ungravity scope + permission** ? `/ungravity` and `/gravity` (plus Shift+U / Shift+G) now affect **all players** on the server (including joiners while float mode is active), and are gated to **Owner / Leadership** (`PermissionDomain.canUseAdminPanel` ? same gate as Admin panel). Regular players no longer get self-float.
- **DataStore join storm** ? live ~4-player joins no longer flood the request queue from boot LB pre-warm + parallel Settings/Stickers/MusicFavorites GetAsync + double SharedProfileLoader enqueue + streak UpdateAsync when already counted.

### Changed
- **World VFX server queue** ? `WORLD_EFFECT_DURATIONS` per effect (Nuke 90s / Smite4 180s / BlackHole 240s); `NUKE_DEFAULT_DURATION` 20->90. Worker always waits after broadcast. NukeEffectController stays disabled (would double VFX).
- **LocalNuke fireworks** ? `FIREWORK_COUNT` 140->40 (temp PlaceMemory spike).
- **Leaderboard boot pre-warm** ? paint empty/loading boards immediately; defer heavy `buildWorkspaceLeaderboardPayload` (~25s); likes metadata GetAsync capped at 20 (identity fallback beyond).
- **Join reads** ? Settings / Stickers / Music favorites fold into SharedProfileLoader; SyncDance favorites registered before first enqueue (no second enqueue).
- **Studio DataStore** ? default isolation again (reverses v2.2.2 ?Studio = live? for safety). Opt into live keys explicitly via `USE_STUDIO_DATASTORE_ISOLATION = false`.

---

## [2.2.9] ? 2026-07-11

### Changed
- **Music topbar** ? pindah ke strip kanan, order paling kiri (sebelah kiri Command): Music -> Command -> Admin -> Menu.
- **Community leaderboard credit** ? donasi Robux pakai community efektif sama seperti badge: `/setcommun` **atau** primary Roblox group (kalau `PRIMARY_FALLBACK_ENABLED` dan belum `/clearcommun`).

---

## [2.2.8] ? 2026-07-11

### Fixed
- **Donation panel rank flicker** ? jangan clear/`#-` pada rank lookup gagal; `assignRobuxTopDonate` align limit 100 + skip miss; `getDonorProfile` pakai `getPlayerRobuxRank`; panel merge overhead supaya nil rank tidak menimpa `#N` saat total > 0. Clear rank saat total benar-benar 0 tetap jalan (v2.2.7).
- **Duplicate role team/chat colors** ? `RolesDomain` auto-remap `teamColor` + `roleColor.primary` yang bentrok (ClubKitConfig buyer) supaya PlayerList/leaderboard teams dan chat tags unik.

### Changed
- **Default music volume** ? 50% -> **100%** (settings + music player store). Existing saves still on old default **50** are migrated once to **100**.
- **Cinematic/freecam topbar icon** ? `Icons.Topbar.Camera` -> `rbxassetid://131545412033411` (menu cinematic + MobileFreecam HP).
- **Carry template anim IDs** ? `ClubKitConfig.Carry` kit template pakai anim buyer (6 style kit names; legacy CoupleHug/Pasakal/PiggyUpperBack dibuang dari template).

---

## [2.2.7] ? 2026-07-11

### Fixed
- **Donation panel rank sticky** ? merge tidak lagi nempel `#N` saat total sudah 0; overhead juga drop rank chip kalau donated = 0; `/removerobux` invalidate + refresh overhead.

---

## [2.2.6] ? 2026-07-11

### Fixed
- **Branding.LogoImage** ? logging target vs default; support ImageButton + nama `LogoImage`/`ClubLogo`; re-apply setelah workspace board paint.

---

## [2.2.5] ? 2026-07-11

### Added
- **Branding.LogoImage** ? ganti logo club sekali di `ClubKitConfig.Branding.LogoImage`; boot auto-apply ke ImageLabel yang masih pakai ID bawaan kit (`79426970537296`) di loading / poster / leaderboard.

---

## [2.2.4] ? 2026-07-11

### Fixed
- **Dance favorites 1KB cap** ? `Validator.favoritesUpdate` tidak lagi pakai `Security.MAX_PAYLOAD_BYTES` (1KB command); limit khusus `Config.Favorites.MAX_PAYLOAD_BYTES` = 32KB (kasus ~54 favorites mentok). Rate limit `FAVORITES_UPDATE` 5/5s -> 15/5s.
- **Donation burst poll** ? `getNotifPollDelay` (5s / 45s window) sekarang di-wire ke `BackgroundJobScheduler:setInterval` setelah tiap `donation_poll` (sebelumnya dead setelah migrasi scheduler).
- **Cash LB overhead** ? hapus `refreshAll` rutin setelah leaderboard sync; `assignPlayer`/`clearPlayer` sudah `refreshPlayer` (force path tetap).
- **Donation notif queue** ? backlog memendekkan display; saat penuh, evict amount terkecil di antrian (bukan drop donasi besar yang baru).

### Added
- **Studio clear-self donation** ? `/removecash me` / `/removerobux me` (atau `@me`) clear data donasi sendiri; **Studio-only**. Live tetap pakai username/userId (owner).

---

## [2.2.3] ? 2026-07-11

### Fixed
- **Gravity / Ungravity naming** ? `/ungravity` (+ Shift+U) = float; `/gravity` (+ Shift+G) = restore. Sebelumnya keybind & `/gravity N` terbalik secara makna.
- **Ungravity -> gravity drop** ? restore tidak lagi nol-kan Y (ngambang dulu); langsung kick ke bawah + Freefall supaya turun lebih cepat.

---

## [2.2.2] ? 2026-07-11

### Changed
- **DataStore: Studio = live** ? hapus prefix `Studio_*` / isolation; Play di Studio memakai key production yang sama agar testing mencerminkan live (write dari Studio mempengaruhi data asli).
- **PlayerList TeamColor unique** ? runtime auto-remap BrickColor bila config role bentrok, supaya player tidak nyasar ke team lain di leaderboard Roblox.

---

## [2.2.1] ? 2026-07-11

### Fixed
- **Source sync Script.Source limit** ? `MusicPlayerUIBinder.luau` (247k) melebihi batas Roblox 200k; dipecah ke `MusicPlayerUIBinderPart2.luau` agar plugin Update Engine bisa menulis Source.

### Changed
- **Music player UI source split** ? late methods load dari sibling ModuleScript; API binder tidak berubah.

---

## [2.2.0] ? 2026-07-11

### Added
- **Gravity / Ungravity** ? float mode per player: Shift+G (float), Shift+U (restore), `/gravity 0-10`, `/ungravity`. Dance/sync tetap jalan; anim fall di-suppress.

### Fixed
- **Music topbar icon** ? logo bisa hilang meski lagu jalan (global mode): `MusicTopbarIcon.show()` sekarang idempotent, restore parent via `alignmentHolder`, dan re-assert setelah panel boot.

### Changed
- Packager plugin layout ? source di `tools/ClubKitPackagerPlugin/plugin/`, build output di `plugin-build/`

---

## [2.1.0] ? 2026-07-10

Studio plugin **Git source sync** ? update engine Luau dari GitHub tag tanpa export/upload RBXM.

### Added
- `SourceSyncCore`, `RojoPathMap` ? fetch `.luau` dari GitHub tag, tulis `Source` ke place
- Dovetail UI: `UpdaterPanel`, `PackagerPanel`, `DovetailTheme`, `DovetailUI`
- Toolbar **Check Update** + **Update Engine**
- `tools/release.ps1` ? validasi versi + git tag/push dari Cursor
- `RolesDomain.buildStudioToolFolderList` ? include membership tool folders

### Changed
- Packager plugin refactor ? panel terpisah, widget Dovetail dark theme
- `EnsureRoleToolFolders` ? delegasi ke shared studio module

---

## [2.0.0] ? 2026-07-10

Initial git baseline + rilis dev v2. Melanjutkan dari handover v1.3 dengan fix session terbaru.

### Added
- Git version control (portable MinGit + `git.ps1`)
- Release workflow: `AGENTS.md`, `CHANGELOG.md`, `UPGRADE_PROGRESS.md`, `.cursor/rules/clubkit-versioning.mdc`

### Fixed
- `/re` ? refresh avatar pakai `LoadCharacter()` + restore posisi & dance sync
- Command GUI ? keyboard tidak stuck di textbox setelah panel ditutup (PC/laptop)
- Mobile freecam ? badan avatar tidak ikut gerak saat kamera digerakkan
- Circular require crash saat boot ? `DonationProviderDomain` lazy-require `Config`

### Changed
- Rate limit session command `/re` dll.: `3` -> `10` per 30 detik (`Config.Session.RATE_MAX`)
- Versi produk: `1.3.0` -> `2.0.0` (semver baru untuk track upgrade via git)

---

## [1.3.0] ? 2026-07-09

Rilis baseline handover. Detail audit & fix: [`HANDOVER.md`](HANDOVER.md).

### Added
- Donation provider preset (`bagibagi` / `saweria`)
- `DonationCash` pipeline + leaderboard seeder tool
- Pisah `AuraTiers` + `WorldEffectTiers`

### Fixed
- Critical audit C1?C6, high severity H1?H13 (lihat HANDOVER)

[Unreleased]: compare with VERSION + UPGRADE_PROGRESS.md
[2.0.0]: docs/releases/2.0.0/
[1.3.0]: HANDOVER.md
