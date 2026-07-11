# Upgrade v2.1.0 → v2.2.0

**Tanggal:** 2026-07-11

## Langkah cepat (Luau only — source sync)

1. Backup `ClubKitConfig` + `Secrets` (plugin tidak menimpa, tapi aman)
2. Studio → Club Kit Packager → **Check Update** → **Update Engine**
3. **Save** place → publish

## What's new

- **Gravity / Ungravity** — Shift+G float, Shift+U restore, `/gravity 0-10`, `/ungravity`
- **Music topbar fix** — logo music muncul lagi di mode global (audio sudah jalan sebelumnya)
- Packager plugin folder layout (`plugin/` + `plugin-build/`)

## Config changes

Opsional di `ClubKitConfig.Features`:

```lua
Gravity = true, -- default on di Config.FeatureFlags jika field belum ada
```

`ClubKitConfig` / `Secrets` **jangan** di-replace dari RBXM.

## Breaking

Tidak.

## QA setelah upgrade

- [ ] Logo music muncul di **kiri** topbar; klik buka panel
- [ ] Shift+G float, Shift+U restore; `/gravity 3` lalu `/gravity 0`
- [ ] Config buyer tidak berubah
- [ ] Check Update menampilkan `2.2.0`
