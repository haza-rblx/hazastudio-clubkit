# Upgrade v2.4.37 → v2.4.38

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Opsional: paste template `RoleCategories` Leadership agar CoOwner terlihat di config; engine inject tetap jalan tanpa paste.
4. Assign Co-Owner hanya via chat: `/setrole <player> CoOwner` (aliases: `coowner`, `co-owner`).

## What's new

- **Co-Owner** sebagai role kit-default: badge Owner-tier, permission seperti Owner, **tanpa** `groupRanks`.
- Inject otomatis di `RoleCategoryBuilder` jika `RoleCategories` buyer tidak punya `CoOwner`.
- Aliases `coowner` / `co-owner` di-force ke CoOwner (tidak bisa di-hijack ke Staff via alias lama).

## Breaking changes

Tidak ada. Buyer `ClubKitConfig` / `Secrets` tidak diganti. Role baru tersedia setelah engine update.

## Config (opsional)

Untuk dokumentasi di place config, tambahkan di Leadership sebelum Staff:

```lua
{
  id = "CoOwner",
  displayName = "Co-Owner",
  badgeAsset = "01-OwnerCoOwnerBadge",
  groupRanks = {}, -- setrole only
},
```

Tidak wajib — engine inject jika hilang.

## QA setelah upgrade

- [ ] `/setrole Me CoOwner` → badge Owner/CoOwner, admin/gift/commands seperti Owner
- [ ] `/setrole Me Staff` kembali normal
- [ ] Group join tidak auto-assign CoOwner
- [ ] ClubKitConfig + Secrets tetap nilai buyer
