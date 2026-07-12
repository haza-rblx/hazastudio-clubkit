# Changed Files — v2.4.2 ? v2.4.3

## Summary

- 5 engine/docs files in this release (+ version bumps / release docs)
- Breaking: **no**
- Git tag: `v2.4.3`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | 1-page pool + O(k) random pick + 300s cache; delayed pre-warm |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Server-first fill; online IsInGroup only if sample incomplete |
| `src/.../Constants/Config.luau` | `POOL_SIZE=40`, `CACHE_TTL=300`, VIP headline + community strip copy |
| `src/.../KitProduct.luau` | KitVersion `2.4.3` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan (no required merge) |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.3` |
| `docs/releases/2.4.3/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.3` |
