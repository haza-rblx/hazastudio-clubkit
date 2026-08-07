# Changed Files — v2.4.72 → v2.4.73

## Summary
- English localization pass (~160 files): comments, warn/log strings, default runtime copy
- Cash leaderboard board title auto-branded from `ClubKitConfig.Donation.Provider`
- Breaking: **no** (logic unchanged; default player-facing copy is English)
- Git tag: `v2.4.73` (vs `v2.4.72`)

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.73` |
| `src/.../Shared/Constants/Config.luau` | Comments + default runtime strings → English; UTF-8 mojibake fix |
| `src/.../Shared/Domain/DonationProviderDomain.luau` | **`applyCashLeaderboardBrand`**, `getCashLeaderboardTitle`, uppercase legacy replacements |
| `src/.../Shared/Leaderboards/WorkspaceLeaderboardRenderer.luau` | Apply cash board provider branding on paint/loading |
| `src/.../Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template comments → English (keys/values unchanged) |
| `src/**/*.luau` (engine) | ~130 files — comments, warn/log, player-facing defaults → English |

Notable runtime copy (defaults):
- Couple announce / breakup strings
- Donation chat: `[DONATION] DONATION RECEIVED`
- Gift: `Username not found`, `Looking up …`
- Admin test donation notify strings

## Buyer-owned — review manually, do not replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Review `Donation.Provider` — now drives cash **board title** too |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | No change required |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/*.luau` | Comments/strings → English; `KIT_VERSION` → `2.4.73` |
| `tools/*.luau`, `tools/*.ps1` | Dev tool comments → English |
| `AGENTS.md`, `README.md`, `CLUB_KIT_SETUP.md`, `QA_CHECKLIST.md`, `CHANGELOG.md` | English + version bump |
| `docs/releases/2.4.73/**` | This release |
| `docs/locales/id.js` | **Unchanged** (intentional Indonesian buyer UI) |
| Historical `docs/releases/2.4.xx/**` | **Unchanged** (except new `2.4.73/`) |

## Optional / not in engine sync

- `plugin-build/` — rebuild plugin RBXM if you ship plugin binary
- Workspace board **Part/GUI asset names** still use legacy `SaweriaDonationBoard` — only the **title text** is auto-branded
