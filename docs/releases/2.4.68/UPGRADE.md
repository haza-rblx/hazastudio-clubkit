# Upgrade v2.4.67 → v2.4.68

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. QA checklist di bawah

`ClubKitConfig` / `Secrets` tidak di-replace. Tidak ada field config baru.

## What's new
- **`/fakecash` / `/fakerobux`** — admin preview donasi palsu: `/fakecash [player] <amount> [message…]` (cash: notif + aura + world VFX; Robux: notif + aura). Tidak persist ke leaderboard
- **`/testcash` / `/testrobux` / `/testsaweria` / `/testdonate`** — tetap jalan sebagai alias deprecated → fakecash/fakerobux
- **Aura gray brick fix** — host Part aura yang cuma bawa particle dipaksa transparan; partikel tetap tampil

## Config changes
Tidak ada.

## Breaking
Tidak ada.

## QA setelah upgrade
- [ ] F9 / KitVersion **2.4.68**
- [ ] Admin `/fakecash 50000 hello` → notif + message, board **tidak** berubah
- [ ] Admin `/fakecash OtherPlayer 150000 boom` → efek di target
- [ ] Admin `/fakerobux 100` → aura saja, tanpa world VFX
- [ ] Non-admin `/fakecash 999` → ditolak
- [ ] `/testcash 500` masih jalan (alias)
- [ ] High-tier cash aura: **tidak** ada kotak abu di kaki karakter
