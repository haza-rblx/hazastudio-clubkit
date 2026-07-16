# Upgrade v2.4.47 → v2.4.48

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place

Patch Luau only — tidak perlu ubah `ClubKitConfig` / `Secrets`.

## What's new

### Fixed
- **Chat bubble terlalu tinggi** — offset memakai pusat billboard + tinggi penuh stack (double-count). Sekarang `center + tinggi×0.5 + pad kecil`. Tuning: `Config.ChatBubble.HEIGHT_FACTOR` / `EXTRA_STUDS`.

## Config changes

Tidak ada field buyer config baru. Konstanta engine `Config.ChatBubble` di-tune (HEIGHT_FACTOR, EXTRA_STUDS).

## QA setelah upgrade

- [ ] Bubble nempel di atas chip/rank teratas overhead (bukan mengambang jauh)
- [ ] Guest pendek vs Owner+badges+donation: gap kecil konsisten
- [ ] Toggle layer overhead → bubble ikut naik/turun
