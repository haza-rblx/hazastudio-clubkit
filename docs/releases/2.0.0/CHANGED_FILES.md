# Changed Files — v1.3.0 → v2.0.0

Initial git baseline. Semua source di-track dari commit ini.

## Summary

| Metrik | Nilai |
|--------|-------|
| Scope | Full kit source (`src/`) + docs + tools |
| Breaking | Tidak (buyer config/secrets tetap terpisah) |
| Git tag | `v2.0.0` |

## Core — ganti via RBXM (highlight fix v2)

| Path | Ringkasan |
|------|-----------|
| `src/ServerScriptService/.../SessionCommandService.luau` | `/re` via `LoadCharacter` + restore |
| `src/ReplicatedStorage/.../Config.luau` | `RATE_MAX` 10 |
| `src/ReplicatedStorage/.../DonationProviderDomain.luau` | Fix circular require |
| `src/StarterPlayerScripts/.../CommandLibraryUI.luau` | Keyboard focus release |
| `src/StarterPlayerScripts/.../CommandLibraryController.luau` | Close panel fix |
| `src/StarterPlayerScripts/.../MobileFreecamController.luau` | Lock avatar saat freecam |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Pertahankan milik venue |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Pertahankan milik venue |

## Docs / tooling baru

| Path | Ringkasan |
|------|-----------|
| `AGENTS.md` | Agent release workflow |
| `CHANGELOG.md` | Changelog |
| `UPGRADE_PROGRESS.md` | Dev progress tracker |
| `VERSION` | `2.0.0` |
| `git.ps1` | Git portable wrapper |
| `.cursor/rules/clubkit-versioning.mdc` | Cursor rule rilis |
| `docs/releases/` | Upgrade guides per versi |
