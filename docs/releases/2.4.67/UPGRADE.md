# Upgrade v2.4.66 → v2.4.67

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. (Opsional bulk tracks) Pastikan ada `ReplicatedStorage/Hazastudio_ClubKitConfig/MusicCatalog.luau` — template ikut Rojo/fresh config; place lama yang belum punya modul: copy dari repo atau sync folder config sekali
4. Set `ClubKitConfig.Features.MusicCatalogSeed = true` (fill-forward menambah key jika belum ada)
5. QA checklist di bawah

`Secrets` tidak diganti. `ClubKitConfig` tidak di-replace utuh — key baru di-fill-forward.

## What's new
- **MusicCatalog script seed** — bulk add tracks via ModuleScript; merge additive ke DataStore on boot
- Default playlist **Legacy** (auto-create)
- Satu baris per track; `parts` multi hingga 9
- Manage UI tetap bisa edit / pindah playlist / hapus setelah seed
- Toggle: `Features.MusicCatalogSeed`

## Config changes
| Key | Default | Notes |
|-----|---------|-------|
| `Features.MusicCatalogSeed` | `true` | `false` = skip seed baru; library yang sudah ada tetap |
| Modul `MusicCatalog.luau` | template kosong | Buyer-owned; di luar engine sync |

## Breaking
Tidak ada.

## QA setelah upgrade
- [ ] F9 / KitVersion **2.4.67**
- [ ] `Features.MusicCatalogSeed` ada di ClubKitConfig (atau diisi fill-forward)
- [ ] Isi 1–2 track di `MusicCatalog` → Play → muncul di playlist **Legacy**
- [ ] Manage: pindah track ke playlist lain → restart → tetap di playlist baru
- [ ] Manage: hapus track → restart → tidak muncul lagi dari catalog
- [ ] `MusicCatalogSeed = false` → track baru di catalog tidak masuk
