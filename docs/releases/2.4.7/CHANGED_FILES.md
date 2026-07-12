# Changed Files — v2.4.6 → v2.4.7

## Summary

- 2 engine files + version bumps / release docs
- Breaking: **no** (fix: valid users API limit + clamp + fail log)
- Git tag: `v2.4.7`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Constants/Config.luau` | `MEMBER_USERS_URL` default `limit=50`; POOL_SIZE comment |
| `src/.../Services/JoinCommunityMembersService.luau` | Clamp `limit=` to {10,25,50,100}; RequestAsync + body snippet on fail |
| `src/.../KitProduct.luau` | KitVersion `2.4.7` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan; no required merge |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.7` |
| `docs/releases/2.4.7/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.7` |
