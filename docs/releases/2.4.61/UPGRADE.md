# Upgrade v2.4.60 → v2.4.61

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only. `ClubKitConfig` / `Secrets` tidak diganti.

## What's new
- **`/re` keeps camera orbit** — sudut kamera (yaw/pitch/zoom) dipertahankan setelah `LoadCharacter`. Freecam / cinematic / first-person tidak diubah.

## Config changes
Tidak ada field buyer. Engine menambahkan attribute sementara `ClubKitPendingCharacterRefresh` saat `/re` (auto clear).

## Breaking
Tidak ada.

## QA setelah upgrade
- [ ] `/re` sambil lihat miring / zoom out → POV tetap, tidak reset ke belakang character
- [ ] Freecam / cinematic setelah `/re` tetap perilaku normal
- [ ] Posisi + overhead + dance restore masih OK
- [ ] F9 banner KitVersion **2.4.61**
