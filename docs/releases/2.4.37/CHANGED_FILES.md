# Changed Files — v2.4.36 → v2.4.37

## Summary

- Shop self-buy migrated to Game Pass; gift stays Dev Product
- Breaking: soft — buyer must set `BuyGamePassId` (placeholders `0`)

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Shared/Constants/Config.luau` | `BUY_GAMEPASS_ID` + legacy `BUY_ID` |
| `Shared/Config/ConfigBootstrap.luau` | `BuyGamePassId` overlay + validate |
| `Shared/Domain/ShopDomain.luau` | `isBuyGamePass` / legacy buy product |
| `Server/Services/ShopService.luau` | `grantMembershipIfHigher` |
| `Server/Controllers/ShopController.luau` | Game Pass finished + join sync |
| `Client/Services/ShopService.luau` | `PromptGamePassPurchase` for buy |
| `KitProduct.luau` | KitVersion 2.4.37 |

## Buyer-owned — review manual, jangan replace blind

| Path | Action |
|------|--------|
| `ClubKitConfig` `Shop.Products` | Tambah `BuyGamePassId` per tier; keep `GiftId`; `BuyId` optional legacy |
| Secrets | No change |

## Tools / docs

| Path | Change |
|------|--------|
| `CLUB_KIT_SETUP.md` | Shop Game Pass docs |
| `VERSION` / Manifest / CHANGELOG | 2.4.37 |
| `docs/releases/2.4.37/*` | Upgrade + changed files |
| Template `ClubKitConfig.luau` in repo | Example `BuyGamePassId = 0` (live place: edit milik sendiri) |
