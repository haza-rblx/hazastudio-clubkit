# Upgrade v2.0.0 → v2.1.0

**Tanggal:** 2026-07-10

## Langkah cepat (Luau only — one-click OK)

1. Install / update **Club Kit Packager plugin** di Studio (`tools/ClubKitPackagerPlugin/`)
2. Enable **HttpService** — Game Settings → Security → Allow HTTP Requests
3. Isi `githubOwner` / `githubRepo` di plugin manifest (jika belum)
4. Toolbar **Check Update** → **Update Engine**
5. **Save** place → publish

`ClubKitConfig` dan `Secrets` **tidak** di-timpa.

## Yang baru di v2.1.0

- Plugin source sync — pull engine `.luau` dari GitHub git tag
- Dovetail UI updater panel
- `release.ps1` untuk tag + push dari Cursor

## Manual assets

Tidak perlu — **Luau only**.

## QA setelah upgrade

- [ ] Check Update menampilkan versi lokal vs remote
- [ ] Update Engine selesai tanpa error
- [ ] Config buyer tidak berubah
