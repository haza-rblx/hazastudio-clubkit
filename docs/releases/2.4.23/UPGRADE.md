# Upgrade v2.4.22 → v2.4.23

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- Proximity interest radius tightened: enter **55** studs (was 80), leave **70** (55+15 hysteresis)
- Lower Recv / fewer overhead+sync subscribers at dense CCU
- Kill switch: set `Config.Interest.USE_LEGACY_VIEW_RANGE = true` if lobby feels names "pop late"

## Breaking / behavior changes

- Overhead / dance sync interest drops sooner past ~70 studs (Far settings still client-unlimited, but server only streams within radius)
- No ClubKitConfig / Secrets / DataStore key changes

## QA setelah upgrade

- [ ] Kit **2.4.23**; boot log `ProximityInterestService ... radius=55, buffer=15, leaveRadius=70`
- [ ] Walk toward / away from another player: nametag + sync appear ~55, stay to ~70, then drop (no flap)
- [ ] Dense floor: Recv should stay calmer vs 2.4.22
- [ ] Large open lobby: if names feel late, try legacy kill switch then report
- [ ] ClubKitConfig + Secrets unchanged
