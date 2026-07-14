# Changed Files — v2.4.31 → v2.4.32

## Summary
- Dance panel remembers scroll position per tab
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Client/UI/DancePanelUIBinder.luau` | Per-tab `CanvasPosition` save/restore; clear on search; keep on close/open |
| `KitProduct.luau` | Version 2.4.32 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.32 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `CHANGELOG.md` / `docs/releases/2.4.32/` | Release notes |
| `VERSION` | 2.4.32 |
| `UPGRADE_PROGRESS.md` | Reset |
