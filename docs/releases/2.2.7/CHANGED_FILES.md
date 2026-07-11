# Changed Files — v2.2.6 → v2.2.7

## Summary

- Scope: Sync donation panel / overhead ranks with cleared totals
- Breaking: no
- Git tag: `v2.2.7`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/Controllers/DonationSystemController.luau` | Sanitize + replace sticky donor profile |
| `src/.../Client/Services/DonationRobuxService.luau` | Trust zero totals; clear rank when total 0 |
| `src/.../Server/Services/OverheadService.luau` | Drop rank chips when donated = 0 |
| `src/.../Server/Services/DonationService.luau` | Profile nil rank if total 0; removerobux refresh |
| `src/.../KitProduct.luau` | KitVersion `2.2.7` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.7` |
| `docs/releases/2.2.7/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.7` |
