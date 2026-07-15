# Changed Files — v2.4.40 → v2.4.41

## Summary

- Donation cash tab Saweria/Bagibagi branding from Provider
- Harden PaidBroadcast exclusion from Robux donation list
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/DonationProviderDomain.luau` | Illustration presets + `applyCashTabBrand`; BagiBagi typo |
| `src/StarterPlayerScripts/.../Client/UI/DonationSystemUI.luau` | Apply cash tab brand on init |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | PaidBroadcast.ProductId via tonumber |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `EXCLUDED_ROBUX_PRODUCT_IDS` |
| `src/ServerScriptService/.../Server/Controllers/ShopController.luau` | Resolve PaidBroadcast ID + final strip |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.41 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Set `Donation.Provider` (`bagibagi` / `saweria`) |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.41 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.41 |
| `docs/releases/2.4.41/*` | Upgrade guide |
