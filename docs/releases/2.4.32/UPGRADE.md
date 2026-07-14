# Upgrade v2.4.31 → v2.4.32

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Dance panel mengingat posisi scroll per tab (Dance / Pose / Favorites)
- Search tetap reset ke atas
- Tutup/buka panel menjaga posisi scroll terakhir

## Breaking

Tidak ada.

## Config changes

Tidak ada.

## QA

- [ ] Kit 2.4.32
- [ ] Scroll di tab Dance → ganti Pose → balik Dance = posisi sama
- [ ] Scroll di Pose / Favorites juga diingat
- [ ] Ketik search → list ke atas; ganti tab setelah search mulai dari atas
- [ ] Tutup panel lalu buka lagi → scroll tab aktif tetap
