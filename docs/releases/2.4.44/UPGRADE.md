# Upgrade v2.4.43 → v2.4.44

**Tanggal:** 2026-07-16

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets`.
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Rejoin → F9 banner **2.4.44**.

## What's new

- **Dance click reliability** — no more client predictive `Play` on click (fixes double-weight, stale row jumps, toggle race, sync fights). Row UI still optimistic; server owns playback; click still warms via `PreloadAsync`.

## Breaking changes

Tidak ada. Soft: gerak self kembali nunggu server replication (bukan instant local play) — UI tetap instant.

## Config

Tidak ada field buyer baru. Engine-only SyncController behavior.

## QA setelah upgrade

- [ ] Banner **2.4.44**
- [ ] Spam ganti dance → tidak goyang dobel, row tidak loncat ke dance lama
- [ ] Toggle off dance (klik ulang) saat preparing / playing
- [ ] Sync follow / unsync bersih
- [ ] ClubKitConfig + Secrets utuh
