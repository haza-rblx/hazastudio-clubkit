# Upgrade v2.4.39 → v2.4.40

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.

## What's new

- **Donation Robux panel** — Developer Product yang **offsale** (`IsForSale ~= true`) tidak ditampilkan di list panel. Product PaidBroadcast juga dikecualikan dari catalog donate.

## Breaking changes

Tidak ada. Buyer `ClubKitConfig` / `Secrets` tidak diganti.

Kill switch (engine `Config.Donation`):

| Flag | Default |
|------|---------|
| `HIDE_OFFSALE_ROBUX_PRODUCTS` | `true` |

Set `false` jika ingin tampilkan semua product (termasuk offsale) lagi.

## Config changes

Tidak wajib edit buyer config.

## QA setelah upgrade

- [ ] Developer Product offsale di Creator Dashboard → tidak muncul di donation panel
- [ ] Product on-sale tetap muncul + prompt purchase OK
- [ ] Setelah ubah on-sale status, tunggu refresh ~5 menit atau restart server
- [ ] ClubKitConfig + Secrets tetap nilai buyer
