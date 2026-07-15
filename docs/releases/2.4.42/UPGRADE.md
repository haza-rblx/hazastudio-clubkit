# Upgrade v2.4.41 → v2.4.42

**Tanggal:** 2026-07-15

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Rejoin → F9 banner **2.4.42**.

## What's new

- **Join DataStore storm fix** — kurangi `budget_exhausted` / FailedCount saat banyak player join (secondary loads ditunda; retry tidak menahan slot scheduler).
- **ClubKitConfig fill-forward** — key config yang hilang diisi dari schema (nilai buyer yang sudah ada tetap).
- **Update Engine** — patch Source config additive + UI dock UpdatePluginGUI; toolbar selalu buka panel.
- **ClubKitShowcase** — dipindah ke `tools/dev/` (tidak ikut engine sync).

## Breaking changes

Tidak ada hard break. Soft:

- Settings / sticker / music favorites / likes bisa tampil **~4 detik** setelah join (nametag overhead tetap cepat).
- Showcase tidak lagi di tree engine — inject manual jika butuh demo.

## Config

| Field | Notes |
|-------|--------|
| Engine `DataStore.JOIN_READ_RETRY_ATTEMPTS` | Default `1` (A/B: `3` = perilaku lama) |
| Engine `ProfileLoader.SECONDARY_JOIN_DELAY_SEC` | Default `4` |
| Buyer `ClubKitConfig` / `Secrets` | Tidak diganti utuh; fill-forward additive saja |

## QA setelah upgrade

- [ ] Banner **2.4.42**
- [ ] Join 15–25 CCU staggered: DataStore FailedCount & `budget_exhausted` jauh lebih jarang
- [ ] Overhead nametag cepat; settings/sticker OK setelah delay singkat
- [ ] Update Engine → status config patch OK; ClubKitConfig nilai buyer utuh
- [ ] ClubKitConfig + Secrets tetap nilai buyer
