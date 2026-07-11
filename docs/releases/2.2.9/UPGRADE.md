# Upgrade v2.2.8 → v2.2.9

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place

## What's new

- Music topbar di kanan, paling kiri sebelah Command
- Donasi Robux credit community leaderboard dari `/setcommun` **atau** primary Roblox group (sama seperti badge)

## Breaking

Tidak. `ClubKitConfig` / `Secrets` tidak diganti.

## QA

- [ ] Topbar kanan: Music → Command → Admin → Menu
- [ ] Donate tanpa `/setcommun` tapi punya primary group → community board naik
- [ ] Setelah `/clearcommun` → donasi tidak credit community board
- [ ] Setelah `/setcommun` → credit ke community yang dipilih
