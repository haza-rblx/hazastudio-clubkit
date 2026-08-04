# Upgrade v2.4.68 → v2.4.69

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place (lihat status Config merge — harus menambah Features key baru jika belum ada)
3. **Rebuild/reinstall Studio plugin** dari `tools/ClubKitPackagerPlugin` (panel motion + louder Config merge)
4. QA checklist di bawah

`ClubKitConfig` / `Secrets` tidak di-replace utuh. Update Engine **merge additive** key Features yang hilang (value lama aman).

## What's new
- **`Features.DonationWorldEffects`** — default `true`. Set `false` untuk map tanpa Nuke/Smite/BlackHole; Settings “World Effects” ikut hilang. Aura/announce/highlight tetap
- **`/drone start|stop`** — shared freecam staff (satu pilot, spectator lock)
- **`/crowd <text>`** — bubble chat sama di semua player (filtered)
- **SociaBuzz** — `Donation.Provider = "sociabuzz"` + webhook Worker `/webhook/sociabuzz/...` (deploy Worker/admin terpisah jika belum)
- **Plugin** — panel motion (progress, confetti Done, springs) + Config merge fail lebih jelas

## Config changes
| Field | Default | Notes |
|-------|---------|--------|
| `Features.DonationWorldEffects` | `true` | Fill-forward / Update Engine insert jika belum ada |

Optional Sociabuzz: set provider + Worker env (lihat `CLUB_KIT_SETUP.md`).

## Breaking
Tidak ada. Default world effects tetap **on**.

## QA setelah upgrade
- [ ] F9 / KitVersion **2.4.69**
- [ ] `ClubKitConfig.Features` punya `DonationWorldEffects` (atau runtime default on)
- [ ] Flag `false` → fakecash/cash donate **tanpa** world VFX; Settings tanpa row World Effects; aura masih ada
- [ ] Flag `true` (default) → Nuke/Smite tetap
- [ ] Admin `/drone start` → freecam shared; `/drone stop` clear
- [ ] Admin `/crowd hello` → bubble di semua player
- [ ] Provider sociabuzz (jika dipakai): cash tab branding + webhook OK
- [ ] Update Engine selesai: status Config merge OK / atau **CONFIG MERGE FAILED** di Output jika Features block rusak
- [ ] Plugin reload: animasi panel + progress bar saat update
