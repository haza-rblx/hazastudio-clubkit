# Upgrade v2.4.45 → v2.4.46

## Quick steps

1. Backup `ClubKitConfig` + `Secrets` (tidak disentuh update ini, tapi selalu backup)
2. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
3. Save & publish place

Semua perubahan adalah Luau engine (server-side) — cukup source sync via plugin, tidak butuh RBXM.

## What's new

### Fixed
- **Couple accept → Taken** — setelah proposal diterima, `relationshipMode` kedua pemain dipaksa `Taken` (override Single / Fun sebelumnya) sehingga overhead menampilkan Taken + nama pasangan. Profile menu sync untuk pemain online.
- **Couple breakup not persisting** — session write-behind di-flush sebelum `invalidateCache` pada accept/breakup/open panel (sebelumnya cache clear membuang perubahan breakup sebelum tersimpan ke DataStore — rejoin masih coupled). `breakupBoth` sekarang return error jika save gagal atau pemain tidak sedang coupled.
- **Music queue wipe on long-run poll** — library reload (poll 30s) tidak lagi menghapus semua lagu di queue saat DataStore read gagal/kosong sementara. Delete track/playlist oleh admin tetap menghapus entry queue terkait.

## Config changes

Tidak ada field config baru.

## QA setelah upgrade

- [ ] Couple: accept proposal → overhead kedua pemain langsung Taken + nama pasangan
- [ ] Couple: breakup → overhead & couple page clear; rejoin tetap tidak coupled
- [ ] Music: queue beberapa lagu, tunggu >2 menit (beberapa siklus poll) → Next up tidak hilang
- [ ] Music: admin delete track yang sedang di-queue → hanya track itu hilang dari queue
- [ ] Music: biarkan queue habis natural → auto playlist tetap mengambil alih
