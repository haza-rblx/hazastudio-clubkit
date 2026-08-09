# Spoof Kit → hazatargz

Tujuan: semua asset kit punya **hazatargz**.  
Skip Tools / WorldEffects.

---

## 1. Re-upload (8) → catat ID baru

Upload ke hazatargz, isi kolom ID baru:

| # | ID lama | Jenis | Nama singkat | ID baru |
|---|---------|-------|--------------|---------|
| 1 | `71634976881165` | Image | NUWA donation art | |
| 2 | `101268994273611` | Image | NUWA broadcast | |
| 3 | `74687624322129` | Audio | NUWA enter sound | |
| 4 | `131545412033411` | Image | LVL camera | |
| 5 | `101906294438076` | Image | TopbarPlus caret | |
| 6 | `124920646932671` | Image | TopbarPlus shadow | |
| 7 | `947384308` | Audio | Firework | |
| 8 | `78416657618448` | Anim | Cinematic dance | |

---

## 2. Ganti ID di code

Setelah tabel di atas penuh:

- [ ] `DonationProviderDomain.luau` ← #1  
- [ ] `Config.luau` ← #2, #3, #4 (+ Broadcast / TOPBAR / ENTER / Camera)  
- [ ] `Icon/Elements/Caption.luau` (+ copy `ReplicatedStorage/Icon/...`) ← #5, #6  
- [ ] `SpawnFireworks.client.luau` ← #7  
- [ ] `Config.luau` + `ClubKitConfigSchema.luau` + template `ClubKitConfig.luau` ← #8  

---

## 3. Permission

Di Creator Dashboard (hazatargz): buka permission buat **8 ID baru** + semua icon/SFX kit yang sudah punya kamu.

---

## 4. Tes cepat

- [ ] Topbar icons (termasuk camera + broadcast)  
- [ ] Enter sound  
- [ ] Menu caret  
- [ ] Nuke firework  
- [ ] Cinematic dance  

---

Done = 8 re-upload + ganti ID + permission + tes.
