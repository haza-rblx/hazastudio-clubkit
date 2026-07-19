# Upgrade v2.4.61 → v2.4.62

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only. `ClubKitConfig` / `Secrets` tidak diganti.

## What's new
- **Name Tag Details / Badge Types = privacy punya kamu** — hide Couple / Role / Level / dll. hanya menyembunyikan overhead **kamu**; overhead orang lain tetap kelihatan kalau mereka tampilkan.
- **Top Rupiah / Top Robux** hide sekarang juga menghilangkan chip di `00-DonationLayers`.
- Sync Settings → Overhead public lebih aman (debounce + skip write kalau tidak berubah).

## Config changes
Tidak ada field buyer baru.

## Breaking
Tidak ada schema break. Behavior change: toggle yang dulu sempat jadi “filter mataku untuk semua orang” sekarang hanya privacy overhead sendiri.

## QA setelah upgrade
- [ ] Hide Couple: punya kamu hilang; couple player lain tetap kelihatan
- [ ] Hide Role / Level / badges: sama pola
- [ ] Top Rupiah / Top Robux chip ikut hide (punya kamu)
- [ ] Show Name Tags / Hide All GUI tetap local
- [ ] F9 banner KitVersion **2.4.62**
