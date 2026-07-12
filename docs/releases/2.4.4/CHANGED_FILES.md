# Changed Files — v2.4.3 → v2.4.4

## Summary

- 2 engine files + version bumps / release docs
- Breaking: **no** (behavior change: no Http group roster)
- Git tag: `v2.4.4`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | Remove Http roster; in-experience + MemoryStore pool; GroupService MemberCount only |
| `src/.../Constants/Config.luau` | `MEMORY_STORE_*` knobs; POOL/CACHE comments for in-experience pool |
| `src/.../KitProduct.luau` | KitVersion `2.4.4` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan (no required merge) |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.4` |
| `docs/releases/2.4.4/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.4` |
