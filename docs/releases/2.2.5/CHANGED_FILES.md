# Changed Files — v2.2.4 → v2.2.5

## Summary

- Scope: Branding.LogoImage auto-apply
- Breaking: no
- Git tag: `v2.2.5`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Utils/BrandLogoApplier.luau` | Boot scan + watch by default kit asset id |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Wire LogoImage → Config.Branding.LOGO_IMAGE |
| `src/.../Shared/Constants/Config.luau` | Config.Branding LOGO / DEFAULT |
| `src/.../ReplicatedFirst/.../LoadingBootstrap.client.luau` | Apply on loading ScreenGui |
| `src/.../Main.client.luau` | Apply + watch PlayerGui / StarterGui |
| `src/.../Main.server.luau` | Apply + watch Workspace / StarterGui |
| `src/.../KitProduct.luau` | KitVersion `2.2.5` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Tambah `Branding.LogoImage` jika ingin custom (template repo sudah punya field) |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.5` |
| `CLUB_KIT_SETUP.md` | Document LogoImage |
| `docs/releases/2.2.5/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.5` |
