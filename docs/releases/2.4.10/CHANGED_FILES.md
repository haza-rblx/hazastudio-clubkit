# Changed Files — v2.4.9 → v2.4.10

## Summary

- JoinCommun: reject bogus memberCount 0 + samples; fall through MEMBER_INFO_URL when worker OK but count unknown; CounterLeft/+99 + others when count known; DEBUG fill
- Breaking: **no** (behavior fix only)
- Git tag: `v2.4.10`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | Reject worker `0`+samples; fall through MEMBER_INFO_URL when count unknown |
| `src/.../Controllers/JoinCommunityPromptController.luau` | CounterLeft finder hardened; DEBUG fill; reject inconsistent 0 count |
| `src/.../KitProduct.luau` | KitVersion `2.4.10` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan — no required merge |
| `Secrets` | Pertahankan — no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/game-data-api/src/worker.js` | Do not coerce missing meta count to `0`; send `memberCountKnown` (redeploy separately) |
| `tools/game-data-api/README.md` | Document memberCount null / known flag |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.10` |
| `docs/releases/2.4.10/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.10` |
