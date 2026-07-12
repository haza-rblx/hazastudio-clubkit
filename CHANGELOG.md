# Changelog

Semua perubahan penting Club Kit dicatat di sini.

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versi mengikuti [Semantic Versioning](https://semver.org/).

Versi aktif: lihat file [`VERSION`](VERSION).

---

## [Unreleased]

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
- **Join greeting notifications** — when Owner, Leadership (category id 1), Content (category id 3), top-10 Robux, or top-10 cash spender joins, all clients see a `GreetingNotifications` / `GeneralGreetings` toast (once per session). Role eligibility follows `ROLE_TO_CATEGORY` (buyer-added Leadership/Content roles auto-greet). Toggle: `Features.JoinGreetings` (default on). Sequence: creative message → fade → `Welcome back, …` (Owner: `Welcome back, owner {DisplayName}`) → dismiss. Toast motion reuses **GenericBroadcast** enter/exit (`UIScale` 0.84→0.9 / 0.81, `GroupTransparency`, Quad 0.28/0.22) + linear **CountDownBar** with role accent; message swap uses `TextTransparency` crossfade (no abrupt `Visible` toggles). Template must be a `CanvasGroup`.

### Changed
- **Join community on load** — after loading/`enterGameplay`, wait 2s then show custom `16-JoinCommunPrompt` with **Shop/Gift/PaidBroadcast** center-modal motion (`AnimationHelper.presentCenterPanel` / `dismissCenterPanel`: UIScale 0.96→1 Sine, PanelBlur + FOV zoom). **Skip entirely if already in group** (no auto CoreGui). Join CTA dismisses modal first, then `GroupService:PromptJoinAsync`; Close dismisses only. Avatar strip clones up to 8 in-server member headshots; `CounterLeft` `+(total-8)` only when group member count > 8. Replaces v2.3.1 auto-`PromptJoinAsync` after 0.75s. Toggle / `GroupId` gates unchanged. Missing GUI → warn + skip (no CoreGui fallback).

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
- **World VFX server queue** — `WORLD_EFFECT_DURATIONS` per effect (Nuke 90s / Smite4 180s / BlackHole 240s); `NUKE_DEFAULT_DURATION` 20→90. Worker always waits after broadcast. NukeEffectController stays disabled (would double VFX).
- **LocalNuke fireworks** — `FIREWORK_COUNT` 140→40 (temp PlaceMemory spike).
- **Leaderboard boot pre-warm** — paint empty/loading boards immediately; defer heavy `buildWorkspaceLeaderboardPayload` (~25s); likes metadata GetAsync capped at 20 (identity fallback beyond).
- **Join reads** — Settings / Stickers / Music favorites fold into SharedProfileLoader; SyncDance favorites registered before first enqueue (no second enqueue).
- **Studio DataStore** — default isolation again (reverses v2.2.2 “Studio = live” for safety). Opt into live keys explicitly via `USE_STUDIO_DATASTORE_ISOLATION = false`.

---

## [2.2.9] — 2026-07-11

### Changed
- **Music topbar** — pindah ke strip kanan, order paling kiri (sebelah kiri Command): Music → Command → Admin → Menu.
- **Community leaderboard credit** — donasi Robux pakai community efektif sama seperti badge: `/setcommun` **atau** primary Roblox group (kalau `PRIMARY_FALLBACK_ENABLED` dan belum `/clearcommun`).

---

## [2.2.8] — 2026-07-11

### Fixed
- **Donation panel rank flicker** — jangan clear/`#-` pada rank lookup gagal; `assignRobuxTopDonate` align limit 100 + skip miss; `getDonorProfile` pakai `getPlayerRobuxRank`; panel merge overhead supaya nil rank tidak menimpa `#N` saat total > 0. Clear rank saat total benar-benar 0 tetap jalan (v2.2.7).
- **Duplicate role team/chat colors** — `RolesDomain` auto-remap `teamColor` + `roleColor.primary` yang bentrok (ClubKitConfig buyer) supaya PlayerList/leaderboard teams dan chat tags unik.

### Changed
- **Default music volume** — 50% → **100%** (settings + music player store). Existing saves still on old default **50** are migrated once to **100**.
- **Cinematic/freecam topbar icon** — `Icons.Topbar.Camera` → `rbxassetid://131545412033411` (menu cinematic + MobileFreecam HP).
- **Carry template anim IDs** — `ClubKitConfig.Carry` kit template pakai anim buyer (6 style kit names; legacy CoupleHug/Pasakal/PiggyUpperBack dibuang dari template).

---

## [2.2.7] — 2026-07-11

### Fixed
- **Donation panel rank sticky** — merge tidak lagi nempel `#N` saat total sudah 0; overhead juga drop rank chip kalau donated = 0; `/removerobux` invalidate + refresh overhead.

---

## [2.2.6] — 2026-07-11

### Fixed
- **Branding.LogoImage** — logging target vs default; support ImageButton + nama `LogoImage`/`ClubLogo`; re-apply setelah workspace board paint.

---

## [2.2.5] — 2026-07-11

### Added
- **Branding.LogoImage** — ganti logo club sekali di `ClubKitConfig.Branding.LogoImage`; boot auto-apply ke ImageLabel yang masih pakai ID bawaan kit (`79426970537296`) di loading / poster / leaderboard.

---

## [2.2.4] — 2026-07-11

### Fixed
- **Dance favorites 1KB cap** — `Validator.favoritesUpdate` tidak lagi pakai `Security.MAX_PAYLOAD_BYTES` (1KB command); limit khusus `Config.Favorites.MAX_PAYLOAD_BYTES` = 32KB (kasus ~54 favorites mentok). Rate limit `FAVORITES_UPDATE` 5/5s → 15/5s.
- **Donation burst poll** — `getNotifPollDelay` (5s / 45s window) sekarang di-wire ke `BackgroundJobScheduler:setInterval` setelah tiap `donation_poll` (sebelumnya dead setelah migrasi scheduler).
- **Cash LB overhead** — hapus `refreshAll` rutin setelah leaderboard sync; `assignPlayer`/`clearPlayer` sudah `refreshPlayer` (force path tetap).
- **Donation notif queue** — backlog memendekkan display; saat penuh, evict amount terkecil di antrian (bukan drop donasi besar yang baru).

### Added
- **Studio clear-self donation** — `/removecash me` / `/removerobux me` (atau `@me`) clear data donasi sendiri; **Studio-only**. Live tetap pakai username/userId (owner).

---

## [2.2.3] — 2026-07-11

### Fixed
- **Gravity / Ungravity naming** — `/ungravity` (+ Shift+U) = float; `/gravity` (+ Shift+G) = restore. Sebelumnya keybind & `/gravity N` terbalik secara makna.
- **Ungravity → gravity drop** — restore tidak lagi nol-kan Y (ngambang dulu); langsung kick ke bawah + Freefall supaya turun lebih cepat.

---

## [2.2.2] — 2026-07-11

### Changed
- **DataStore: Studio = live** — hapus prefix `Studio_*` / isolation; Play di Studio memakai key production yang sama agar testing mencerminkan live (write dari Studio mempengaruhi data asli).
- **PlayerList TeamColor unique** — runtime auto-remap BrickColor bila config role bentrok, supaya player tidak nyasar ke team lain di leaderboard Roblox.

---

## [2.2.1] — 2026-07-11

### Fixed
- **Source sync Script.Source limit** — `MusicPlayerUIBinder.luau` (247k) melebihi batas Roblox 200k; dipecah ke `MusicPlayerUIBinderPart2.luau` agar plugin Update Engine bisa menulis Source.

### Changed
- **Music player UI source split** — late methods load dari sibling ModuleScript; API binder tidak berubah.

---

## [2.2.0] — 2026-07-11

### Added
- **Gravity / Ungravity** — float mode per player: Shift+G (float), Shift+U (restore), `/gravity 0-10`, `/ungravity`. Dance/sync tetap jalan; anim fall di-suppress.

### Fixed
- **Music topbar icon** — logo bisa hilang meski lagu jalan (global mode): `MusicTopbarIcon.show()` sekarang idempotent, restore parent via `alignmentHolder`, dan re-assert setelah panel boot.

### Changed
- Packager plugin layout — source di `tools/ClubKitPackagerPlugin/plugin/`, build output di `plugin-build/`

---

## [2.1.0] — 2026-07-10

Studio plugin **Git source sync** — update engine Luau dari GitHub tag tanpa export/upload RBXM.

### Added
- `SourceSyncCore`, `RojoPathMap` — fetch `.luau` dari GitHub tag, tulis `Source` ke place
- Dovetail UI: `UpdaterPanel`, `PackagerPanel`, `DovetailTheme`, `DovetailUI`
- Toolbar **Check Update** + **Update Engine**
- `tools/release.ps1` — validasi versi + git tag/push dari Cursor
- `RolesDomain.buildStudioToolFolderList` — include membership tool folders

### Changed
- Packager plugin refactor — panel terpisah, widget Dovetail dark theme
- `EnsureRoleToolFolders` — delegasi ke shared studio module

---

## [2.0.0] — 2026-07-10

Initial git baseline + rilis dev v2. Melanjutkan dari handover v1.3 dengan fix session terbaru.

### Added
- Git version control (portable MinGit + `git.ps1`)
- Release workflow: `AGENTS.md`, `CHANGELOG.md`, `UPGRADE_PROGRESS.md`, `.cursor/rules/clubkit-versioning.mdc`

### Fixed
- `/re` — refresh avatar pakai `LoadCharacter()` + restore posisi & dance sync
- Command GUI — keyboard tidak stuck di textbox setelah panel ditutup (PC/laptop)
- Mobile freecam — badan avatar tidak ikut gerak saat kamera digerakkan
- Circular require crash saat boot — `DonationProviderDomain` lazy-require `Config`

### Changed
- Rate limit session command `/re` dll.: `3` → `10` per 30 detik (`Config.Session.RATE_MAX`)
- Versi produk: `1.3.0` → `2.0.0` (semver baru untuk track upgrade via git)

---

## [1.3.0] — 2026-07-09

Rilis baseline handover. Detail audit & fix: [`HANDOVER.md`](HANDOVER.md).

### Added
- Donation provider preset (`bagibagi` / `saweria`)
- `DonationCash` pipeline + leaderboard seeder tool
- Pisah `AuraTiers` + `WorldEffectTiers`

### Fixed
- Critical audit C1–C6, high severity H1–H13 (lihat HANDOVER)

[Unreleased]: compare with VERSION + UPGRADE_PROGRESS.md
[2.0.0]: docs/releases/2.0.0/
[1.3.0]: HANDOVER.md
