# Changed Files - v2.4.12 -> v2.4.13

## Summary

- Join greeting entered-the-space copy, role/spender gelar, Universal chip amount
- Breaking: **no** (copy/UI behavior only; additive payload fields)
- Git tag: `v2.4.13`

## Core - replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Constants/Config.luau` | `ENTERED_SPACE_TEMPLATE`; `GELAR_TITLES` spender/donor templates |
| `src/.../Services/JoinGreetingService.luau` | Smart `resolveGelar` from Roles label; `amount`/`amountText`/`amountKind` on payload |
| `src/.../Controllers/JoinGreetingController.luau` | Entered-space line; bind amount to Universal chip / amount labels |
| `src/.../KitProduct.luau` | KitVersion `2.4.13` |

## Buyer-owned - review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan - Roles display titles feed gelar; no required merge |
| `Secrets` | Pertahankan - no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.13` |
| `docs/releases/2.4.13/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.13` |
