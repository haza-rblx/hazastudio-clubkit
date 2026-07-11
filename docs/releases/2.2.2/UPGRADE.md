# Upgrade v2.2.1 → v2.2.2

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place

## What's new

- Studio Play memakai DataStore key **sama** dengan live (tidak ada prefix `Studio_*` lagi)
- PlayerList: TeamColor auto-unique — role dengan warna config bentrok tidak membuat player nyasar team

## Breaking / hati-hati

- **Studio menulis data production.** Testing `/setrobux`, settings, overhead, music library, dll. di Studio mengubah data live.
- Data lama di key `Studio_*` tidak ikut pindah (orphan).

## Config

Tidak ada field ClubKitConfig baru.

## QA

- [ ] Boot log: `DataStore scope: production keys (Studio = live)` (bukan `Studio_…`)
- [ ] Role dengan teamColor bentrok: player tetap di team label yang benar
- [ ] Overhead / settings / donation load dari data live
