# Upgrade v2.4.29 → v2.4.30

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Studio DataStore isolation default **off** (live keys in Studio Play)
- `ClubKitShowcase` no longer shipped via Update Engine / RBXM; removed from place on update if present (demo toggle stays available only in private repo/local)

## Breaking

Tidak ada formal, tapi:
- Studio Play menulis ke **production DataStore keys** — hati-hati saat test `/setrobux` dll.
- Place yang sebelumnya punya `ClubKitShowcase` akan kehilangan file itu setelah Update Engine → demo leaderboard off kecuali diaktifkan manual lagi secara lokal

## Config changes

- Engine: `USE_STUDIO_DATASTORE_ISOLATION = false`

## QA

- [ ] Kit 2.4.30
- [ ] Boot log: live DataStore scope (bukan Studio_ prefix), sesuai expectation
- [ ] `Shared/Config/ClubKitShowcase` tidak ada setelah Update Engine
- [ ] Showcase file tetap ada di repo lokal developer jika dibutuhkan
