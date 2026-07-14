# Upgrade v2.4.26 → v2.4.27

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Hotfix: cash donation notifications no longer flood chat with historical donations on every server boot

## Breaking

Tidak ada.

## Config changes

Tidak ada.

## QA

- [ ] Kit 2.4.27 (`coldStartCursorSeeded=true` di log DonationService init)
- [ ] Boot tanpa banjir `[DONASI] DONASI MASUK` dari history
- [ ] Donasi cash baru setelah boot tetap muncul di chat/notif
