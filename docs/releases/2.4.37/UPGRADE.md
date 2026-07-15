# Upgrade v2.4.36 → v2.4.37

**Tanggal:** 2026-07-15

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. **Manual (config tidak diganti plugin):** di `ClubKitConfig.Shop.Products` tambah `BuyGamePassId` per tier (Game Pass ID dari Creator Dashboard). Biarkan `GiftId`. `BuyId` boleh tetap (legacy ProcessReceipt).
3. Save + Publish
4. Rejoin → F9 **2.4.37**

## What's new

- Shop **beli sendiri** memakai **Game Pass** (one-time), bukan Developer Product.
- Gift membership tetap **Developer Product**.
- Buyer lama dengan `membershipBadge` dari Dev Product **tetap aman** (tidak dihapus; sync Game Pass hanya upgrade jika lebih tinggi).

## Breaking

Buyer harus isi `BuyGamePassId` — kalau masih `0`, tombol Buy shop tidak prompt (warn di Output). Gift tidak terdampak jika `GiftId` sudah terisi.

## Config changes

```lua
Shop.Products.Tier1 = {
  BuyGamePassId = 0, -- NEW — Game Pass self-buy
  GiftId = ...,      -- unchanged
  BuyId = ...,       -- optional legacy Dev Product
  Price = ...,
}
```

## QA

- [ ] Banner 2.4.37
- [ ] Buy dengan Game Pass ID terisi → prompt Game Pass → badge update
- [ ] Gift masih Dev Product
- [ ] Player yang sudah VIP dari pembelian lama → badge tetap tanpa beli ulang
- [ ] Join dengan Game Pass owned → sync badge jika belum / upgrade tier
