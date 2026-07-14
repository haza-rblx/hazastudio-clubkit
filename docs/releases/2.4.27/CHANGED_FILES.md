# Changed Files — v2.4.26 → v2.4.27

## Summary
- 1 core service fix (donation notification cold-start)
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `ServerScriptService/.../DonationService.luau` | Tip-cursor cold-start; keep skip-before-unix for server lifetime |
| `KitProduct.luau` | Version 2.4.27 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.27 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `CHANGELOG.md` | 2.4.27 section |
| `docs/releases/2.4.27/` | Upgrade guide |
| `VERSION` | 2.4.27 |
