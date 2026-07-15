# Upgrade v2.4.34 → v2.4.35

**Tanggal:** 2026-07-15

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save + Publish
3. Jangan replace ClubKitConfig / Secrets
4. Rejoin → F9 ASCII **2.4.35**; server harus boot penuh (tanpa `Out of local registers`)

## What's new

- **Fix:** Server `Main.server` crash saat Music ON — `Out of local registers … musicControllerErr` (batas Luau 200).
- Persistence Fabric tetap aktif; wiring dipindah ke `Init/PersistenceFabricHooks` + `Init/MusicBootstrap` (bukan dihapus).

## Breaking

Tidak ada.

## Config changes

Tidak ada.

## QA

- [ ] Kit 2.4.35 di F9 (client + server banner)
- [ ] Studio Play dengan Music enabled — **tidak** ada `Out of local registers`
- [ ] DonationEffect / nuke remote ada (bukan `DonationEffect remote not found`)
- [ ] Persistence: leave player tidak spam DS queue; no MessagingService OverheadInvalidate flood
