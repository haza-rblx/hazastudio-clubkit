# Upgrade v2.4.30 → v2.4.31

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets
4. (Opsional) Kalau sudah ada `UIGradient` di `RobuxRankWrapper` / `RupiahRankWrapper`, tambah di `ClubKitConfig.Features`:

```lua
DonationRankGradientAnim = true,
```

## What's new

- Animasi opt-in untuk UIGradient chip donation rank overhead (`#N ROBUX` / `#N RUPIAH`)
- Default **off** — place tanpa gradient di template tidak berubah

## Breaking

Tidak ada.

## Config changes

- Buyer (opsional): `Features.DonationRankGradientAnim = true`
- Engine default: `Overhead.ANIMATE_DONATION_RANK_GRADIENT = false`

## QA

- [ ] Kit 2.4.31
- [ ] Flag off → chip rank tampil normal, gradient static (atau tidak ada)
- [ ] Flag on + UIGradient di wrapper → sheen (Robux) / prism (Rupiah)
- [ ] Place tanpa UIGradient + flag on → tetap aman (no crash)
