# Changed Files — v2.4.19 → v2.4.20

## Summary

- Leaderboard overlay dual-animation fix
- Music library virtual-list performance MVP
- Breaking: **no** (music titles single-line in virtual lists)
- Git tag: `v2.4.20`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Leaderboards/WorkspaceLeaderboardRenderer.luau` | Client skip bootstrap loading anim when not CLIENT_PAINT_DATA |
| `src/.../Client/Controllers/DonationLeaderboardController.luau` | Bootstrap only when CLIENT_PAINT_DATA |
| `src/.../Client/UI/MusicPlayerUIBinder.luau` | Coalesce + identity recycle + list thumb + fixed title |
| `src/.../Client/UI/MusicPlayerUIBinderPart2.luau` | Search debounce, listThumb covers, no playlist re-animate |
| `src/.../Server/Services/MusicService.luau` | Request-history covers rbxthumb 150 |
| `src/.../KitProduct.luau` | KitVersion `2.4.20` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.20` |
| `docs/releases/2.4.20/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.20` |
