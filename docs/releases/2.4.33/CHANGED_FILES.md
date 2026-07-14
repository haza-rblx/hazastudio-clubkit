# Changed Files — v2.4.32 → v2.4.33

## Summary
- 2 core files changed
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Server/Services/DonationService.luau` | `/removerobux` allowed when Studio writes live; warn log |
| `Shared/Constants/Config.luau` | Clearer `MSG_STUDIO_LIVE_DATASTORE_BLOCKED` |
| `KitProduct.luau` | Version 2.4.33 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.33 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `CHANGELOG.md` / `docs/releases/2.4.33/` | Release notes |
| `VERSION` | 2.4.33 |
| `UPGRADE_PROGRESS.md` | Reset |
