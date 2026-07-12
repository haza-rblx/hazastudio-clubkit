# Changed Files — v2.4.7 → v2.4.8

## Summary

- Engine JoinCommun + game-data-api worker community endpoint; version bumps / release docs
- Breaking: **no** (preferred worker path when secret present; roproxy fallback retained)
- Git tag: `v2.4.8`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | Prefer worker `/community`; roproxy Asc/retry/roles fallback; richer fail log |
| `src/.../Constants/Config.luau` | JoinCommun preference comments; `COMMUNITY_ENDPOINT_ENABLED` |
| `src/.../KitProduct.luau` | KitVersion `2.4.8` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan; merge GameDataApi / JoinCommunity notes if needed |
| `Secrets` | Pertahankan; add/set `GameDataApiSecret` for primary worker path |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/game-data-api/src/worker.js` | `GET /game/:gameKey/community/:groupId`; allowlist `the-basic` + `nuwa` |
| `tools/game-data-api/README.md` | Community endpoint + the-basic notes |
| `tools/game-data-api/.dev.vars.example` | `SECRET_THE_BASIC` + `ROBLOX_GROUP_API_KEY` |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.8` |
| `docs/releases/2.4.8/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.8` |
