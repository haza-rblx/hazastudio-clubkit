# Upgrade v2.4.35 → v2.4.36

**Tanggal:** 2026-07-15

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save + Publish
3. Jangan replace ClubKitConfig / Secrets
4. Rejoin → F9 ASCII **2.4.36**; server + client boot tanpa `Out of local registers`

## What's new

- **Register headroom** — Main.client / Main.server / MusicPlayerUIBinder stay safely under Luau’s ~200-local limit via Init bags + cover helpers (preventive; no player-facing behavior change).
- **Tooling** — `tools/count-locals.ps1` to watch register pressure during development.

## Breaking

Tidak ada.

## Config changes

Tidak ada.

## QA

- [ ] Kit 2.4.36 di F9 (client + server banner)
- [ ] Studio Play — **tidak** ada `Out of local registers` (server atau client)
- [ ] Music panel + cover list / queue OK
- [ ] Overhead + donate remotes OK (Persistence Fabric dari 2.4.34+ tetap aktif)
