# Changed Files — v2.4.8 → v2.4.9

## Summary

- JoinCommun: skip roproxy when worker OK / quiet 429; CounterLeft +99; body 3 names + compact others
- Breaking: **no** (behavior/copy tweaks only)
- Git tag: `v2.4.9`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | Skip MEMBER_INFO/USERS when worker `ok`; 429 → DEBUG once + fail TTL backoff |
| `src/.../Controllers/JoinCommunityPromptController.luau` | CounterLeft `memberCount-8` (+99 cap); body Oxford names + compact remaining |
| `src/.../Constants/Config.luau` | `BODY_WITH_NAMES` replaces `BODY_WITH_EXTRA` wording |
| `src/.../KitProduct.luau` | KitVersion `2.4.9` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan — no required merge |
| `Secrets` | Pertahankan — no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.9` |
| `docs/releases/2.4.9/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.9` |
