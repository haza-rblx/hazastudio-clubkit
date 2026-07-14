# Upgrade v2.4.32 → v2.4.33

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- `/removerobux` boleh clear Robux leaderboard **live** dari Studio Play saat `USE_STUDIO_DATASTORE_ISOLATION=false`
- `/setrobux` tetap diblok di mode live Studio (aman dari isi production tanpa sengaja)
- Warn log di Output saat remove live dari Studio

## Breaking

Tidak ada.

## Config changes

Tidak ada field baru. Pesan error `MSG_STUDIO_LIVE_DATASTORE_BLOCKED` diperjelas (engine Config saja).

## QA

- [ ] Kit 2.4.33
- [ ] Studio Play + isolation false: `/removerobux me` → total Robux 0, rank hilang
- [ ] Studio Play: `/setrobux …` masih error (blocked)
- [ ] Output ada warn Studio → live saat remove
