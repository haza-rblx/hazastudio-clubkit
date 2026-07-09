# Changelog

Semua perubahan penting Club Kit dicatat di sini.

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versi mengikuti [Semantic Versioning](https://semver.org/).

Versi aktif: lihat file [`VERSION`](VERSION).

---

## [Unreleased]

_(belum ada perubahan)_

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
