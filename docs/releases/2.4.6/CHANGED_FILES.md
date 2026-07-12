# Changed Files — v2.4.5 → v2.4.6

## Summary

- 3 engine files + version bumps / release docs
- Breaking: **no** (behavior: compact counts, copy, remote thumbs, quieter logs)
- Git tag: `v2.4.6`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | MEMBER_USERS_URL page + cache; DEBUG for missing MemberCount; remote-first thumbs |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Compact k/M/B; qualitative subtitle; body count once + alt pool |
| `src/.../Constants/Config.luau` | `MEMBER_USERS_URL`, copy keys / `BODY_EMPTY_WITH_COUNT_ALT` |
| `src/.../KitProduct.luau` | KitVersion `2.4.6` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan; no required merge |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.6` |
| `docs/releases/2.4.6/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.6` |