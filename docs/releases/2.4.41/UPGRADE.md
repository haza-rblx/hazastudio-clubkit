# Upgrade v2.4.40 → v2.4.41

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Pastikan `ClubKitConfig.Donation.Provider` = `"bagibagi"` atau `"saweria"`.

## What's new

- **Cash tab brand** — Provider mengatur ilustrasi + tinggi + `UIGradient-Gold` + title (`Support us on Saweria!` / `Bagibagi!`). Typo ScreenGui `BagiBagi` diperbaiki.
- **PaidBroadcast hide** — ProductId PaidBroadcast lebih andal dikeluarkan dari list Robux donation (tonumber + fallback + strip final). Opsional `EXCLUDED_ROBUX_PRODUCT_IDS`.

## Breaking changes

Tidak ada. Buyer `ClubKitConfig` / `Secrets` tidak diganti.

## Config

| Field | Nilai |
|-------|--------|
| `Donation.Provider` | `"bagibagi"` (default) atau `"saweria"` |
| `Donation.ProviderLink` | URL halaman donate (sudah ada) |

## QA setelah upgrade

- [ ] `Provider = "saweria"` → logo Saweria, height 200, gradient off, title Saweria
- [ ] `Provider = "bagibagi"` → logo BB, height 120, gradient on, title Bagibagi
- [ ] PaidBroadcast Dev Product tidak muncul di Robux donation list
- [ ] ClubKitConfig + Secrets tetap nilai buyer
