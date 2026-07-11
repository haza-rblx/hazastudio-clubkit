# Changed Files — v2.2.5 → v2.2.6

## Summary

- Scope: Brand logo apply diagnostics + broader match + re-apply after board paint
- Breaking: no
- Git tag: `v2.2.6`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Utils/BrandLogoApplier.luau` | mutated/matched stats; ImageButton; name match |
| `src/.../Server/Main.server.luau` | Log targetLogo; warn if still default |
| `src/.../Server/Controllers/DonationController.luau` | Re-apply after workspace board paint |
| `src/.../KitProduct.luau` | KitVersion `2.2.6` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan; pastikan `Branding.LogoImage` di-set |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.6` |
| `docs/releases/2.2.6/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.6` |
