# Changed Files — v2.2.8 → v2.2.9

## Summary

- Scope: Music topbar right strip; community LB primary fallback on donate
- Breaking: no
- Git tag: `v2.2.9`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Main.client.luau` | Music `placeTopbarIcon` (Right) |
| `src/.../Shared/Constants/Config.luau` | Orders Music 1 / Command 2 / Admin 3 / Menu 4 |
| `src/.../Server/Services/OverheadService.luau` | `resolveEffectiveCommunity` |
| `src/.../Server/Controllers/ShopController.luau` | Donation community = effective community |
| `src/.../KitProduct.luau` | KitVersion `2.2.9` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.9` |
| `docs/releases/2.2.9/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.9` |
