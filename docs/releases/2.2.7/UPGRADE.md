# Upgrade v2.2.6 → v2.2.7

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place

## What's new

- Donation panel / overhead rank ikut hilang saat total donasi 0 (tidak nempel `#3` setelah clear)
- `/removerobux` refresh overhead rank cache segera

## Breaking

Tidak.

## QA

- [ ] `/removerobux me` → leaderstats 0, overhead tanpa `#N ROBUX`, donation panel rank kosong
- [ ] Donasi baru → rank muncul lagi bila masuk top board
