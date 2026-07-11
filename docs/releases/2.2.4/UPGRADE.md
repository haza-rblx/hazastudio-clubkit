# Upgrade v2.2.3 → v2.2.4

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place

## What's new

- Dance favorites payload limit **1KB → 32KB** (rate limit 15/5s)
- Donation burst poll + smarter notif queue + leaner cash LB refresh
- Studio-only: `/removecash me` / `/removerobux me` clear data donasi sendiri

## Breaking

Tidak.

## Config

- `Config.Favorites.MAX_PAYLOAD_BYTES` = 32KB (baru)
- `Config.SyncRateLimit.FAVORITES_UPDATE` = 15/5s

## Buyer-owned

`ClubKitConfig` / `Secrets` — jangan replace.

## QA

- [ ] Favorite >54 dance → persist setelah rejoin
- [ ] Spam star favorites tidak rate-limit ketat
- [ ] Studio: `/removerobux me` / `/removecash me` clear self
- [ ] Live: `me` ditolak; owner masih bisa remove by username
- [ ] Burst donation notif tetap responsif
