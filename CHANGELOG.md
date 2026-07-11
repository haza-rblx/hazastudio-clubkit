# Changelog

Semua perubahan penting Club Kit dicatat di sini.

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versi mengikuti [Semantic Versioning](https://semver.org/).

Versi aktif: lihat file [`VERSION`](VERSION).

---

## [Unreleased]

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
