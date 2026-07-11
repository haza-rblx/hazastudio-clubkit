# Upgrade v2.2.4 → v2.2.5

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. (Opsional) Tambah di `ClubKitConfig.Branding`:
   ```lua
   LogoImage = "rbxassetid://YOUR_ID",
   ```
   Place lama tanpa field ini tetap pakai logo bawaan kit.

## What's new

- Satu field `Branding.LogoImage` untuk ganti logo di loading, poster, dan leaderboard (ImageLabel yang masih ID bawaan kit)

## Breaking

Tidak. `ClubKitConfig` / `Secrets` jangan di-replace.

## QA

- [ ] Default (tanpa ganti LogoImage) → logo tetap sama
- [ ] Ganti `LogoImage` → loading + board ikut setelah Play/rejo
- [ ] Icon Robux / VFX lain tidak ikut berubah
