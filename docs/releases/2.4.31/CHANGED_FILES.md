# Changed Files — v2.4.30 → v2.4.31

## Summary
- Opt-in donation rank chip UIGradient animation
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Client/UI/OverheadUI.luau` | Sheen/prism anim on donation chip gradients (flag-gated) |
| `Shared/Constants/Config.luau` | `Overhead.ANIMATE_DONATION_RANK_GRADIENT` default false |
| `Shared/Config/ConfigBootstrap.luau` | Wire `Features.DonationRankGradientAnim` → Overhead flag |
| `KitProduct.luau` | Version 2.4.31 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.31 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Merge opsional: `Features.DonationRankGradientAnim = true` (setelah UIGradient di wrapper) |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `CHANGELOG.md` / `docs/releases/2.4.31/` | Release notes |
| `VERSION` | 2.4.31 |
| `UPGRADE_PROGRESS.md` | Reset |
