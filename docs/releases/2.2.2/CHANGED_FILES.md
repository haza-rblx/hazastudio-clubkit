# Changed Files — v2.2.1 → v2.2.2

## Summary

- Scope: Remove Studio DataStore isolation; unique PlayerList TeamColor
- Breaking: Studio now writes production DataStore keys (intentional)
- Git tag: `v2.2.2`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Constants/Config.luau` | Hapus `Studio_*` isolation; bare production keys |
| `src/.../Server/Main.server.luau` | Boot log Studio = live |
| `src/.../Server/Services/DonationService.luau` | Hapus blokir write Studio→live |
| `src/.../Server/Controllers/OverheadController.luau` | Auto-unique TeamColor |
| `src/.../KitProduct.luau` | KitVersion `2.2.2` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/OneTimeLeaderboardSeeder/...` | Tanpa Studio_ prefix |
| `tools/.../ClubKitManifest.luau` | `2.2.2` |
| `docs/releases/2.2.2/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.2` |
