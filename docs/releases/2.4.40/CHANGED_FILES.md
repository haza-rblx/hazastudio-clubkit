# Changed Files — v2.4.39 → v2.4.40

## Summary

- Donation Robux catalog filters offsale Developer Products
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Donation.HIDE_OFFSALE_ROBUX_PRODUCTS` (default true) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/ShopController.luau` | IsForSale / GetProductInfo filter; exclude PaidBroadcast ID |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.40 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Tidak wajib diubah |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.40 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.40 |
| `docs/releases/2.4.40/*` | Upgrade guide |
