# Changed Files - v2.4.13 -> v2.4.14

## Summary

- Join Commun CTA nested TextLabel; Join greeting CountDownBar keeps Studio colors
- Breaking: **no**
- Git tag: `v2.4.14`

## Core - replace via source sync

| Path | Change |
|------|--------|
| `src/.../Controllers/JoinCommunityPromptController.luau` | `setJoinButtonLabel` prefers nested TextLabel |
| `src/.../Controllers/JoinGreetingController.luau` | Removed CountDownBar role accent / UIGradient overwrite |
| `src/.../KitProduct.luau` | KitVersion `2.4.14` |

## Buyer-owned - review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan - no required merge |
| `Secrets` | Pertahankan - no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.14` |
| `docs/releases/2.4.14/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.14` |
