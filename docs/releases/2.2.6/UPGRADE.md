# Upgrade v2.2.5 → v2.2.6

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. Pastikan di `ClubKitConfig.Branding.LogoImage` ID **berbeda** dari bawaan kit (`79426970537296`)

## What's new

- Brand logo apply lebih andal: ImageButton + nama `LogoImage`/`ClubLogo`, re-apply setelah board paint
- Log Output: `targetLogo`, `mutated`, `sameAsDefault` — kalau `sameAsDefault=true`, config belum diganti

## Breaking

Tidak.

## QA

- [ ] Ganti `LogoImage` → Play → cek log `mutated > 0`
- [ ] Loading + poster/board ikut ganti
