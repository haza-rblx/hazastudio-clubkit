# Upgrade v2.4.42 → v2.4.43

**Tanggal:** 2026-07-16

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Rejoin → F9 banner **2.4.43**.

## What's new

- **100 CCU / phone perf** — favorites tanpa Attribute leak; session flush race fix; donation VFX gated by graphics; phone boot Low.
- **Dance panel** — klik optimistic + predictive local play; full-catalog `PreloadAsync` (cache, bukan LoadAnimation); selection UI ringan.
- **Loading** — intro blank + logo + blur sebelum cinematic; dance tier1 warm selama loading.

## Breaking changes

Tidak ada hard break. Soft / perilaku:

- Favorites dance/music sync via owner remotes (bukan Player Attribute). Client lama + server baru: favorites UI bisa kosong sampai Update Engine.
- `DonationEffect` nuke remote = `UnreliableRemoteEvent` (cosmetic; boleh drop saat congest).
- Loading bisa sedikit lebih lama sampai dance tier1 ready (`HOLD_LOADING_FOR_DANCE_TIER1`).
- Full dance catalog preload memakai bandwidth idle join (kill switch: `DANCE_PRELOAD_FULL_CATALOG = false`).

## Config

| Field | Notes |
|-------|--------|
| `DataStore.FAVORITES_SAVE_DEBOUNCE_SEC` | Default `8` |
| `Sync.REMOTE_SYNC_FAVORITES` / `Music.REMOTE_FAVORITES_SYNC` | Owner-only favorites push |
| `Sync.DANCE_PRELOAD_FULL_CATALOG` | Default `true` |
| `Loading.INTRO_*` | Intro logo + blur |
| `ClientBoot.DANCE_WARMUP_DURING_LOADING` | Default `true` |
| `ClientBoot.HOLD_LOADING_FOR_DANCE_TIER1` | Default `true` |
| Buyer `ClubKitConfig` / `Secrets` | **Jangan replace** — logo intro dari `Branding.LogoImage` |

## QA setelah upgrade

- [ ] Banner **2.4.43**
- [ ] Loading: blank + logo + blur dulu, baru cinematic
- [ ] Dance panel: row kepencet instant; dance bawah tidak “seabad” setelah warm
- [ ] Favorites dance/music persist & sync ke owner saja
- [ ] Phone: graphics provisional Low; donation VFX respect hide/tier
- [ ] ClubKitConfig + Secrets tetap nilai buyer
