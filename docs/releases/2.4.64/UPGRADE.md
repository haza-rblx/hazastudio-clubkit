# Upgrade v2.4.63 → v2.4.64

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. QA chat tags jauh + nearby (lihat checklist bawah)

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti — tidak ada schema/config buyer baru.

## What's new
- **ChatTag global sync** — tag chat tidak lagi bergantung proximity overhead; remote `ChatTagSync` + client `ChatTagStore`
- Distant players: tag benar (bukan invent `[GUEST]`); name + tag satu warna
- Sebelum tag authoritative: **name only** (bukan Guest palsu)
- Join admission: `inflight_saturated` vs `budget_low`; negative-cache hanya budget nyata; inflight **8**; join timeout **10s**
- Rank cache `{rank, ok}` + LKG — tidak lock Guest 10 menit saat GroupService flake

## Config changes
Tidak ada. Engine-only.

## Breaking
Tidak ada. Behavior: chat prefix mewarnai display name sendiri (tidak mengandalkan TeamColor untuk kebenaran tag).

## QA setelah upgrade
- [ ] Dua player jauh (luar View_Range): chat `[STAFF]`/tag nyata, bukan Guest; warna konsisten
- [ ] Nearby: overhead nametag + chat tag setuju
- [ ] Studio join storm: tidak flood false `budget_exhausted` dengan budget sehat
- [ ] `/re` + dance masih OK
- [ ] F9 banner KitVersion **2.4.64**
