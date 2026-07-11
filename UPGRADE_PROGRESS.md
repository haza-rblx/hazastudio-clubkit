# Upgrade Progress — Club Kit

Scratch pad internal untuk track pekerjaan **sebelum** versi dirilis.

**Versi saat ini:** `2.2.8` (lihat [`VERSION`](VERSION))  
**Target rilis berikutnya:** _(belum ditetapkan)_

---

## Status ringkas

| Area | Status |
|------|--------|
| v2.2.8 donation rank / roles / volume / cinematic / carry template | ✅ Released |

---

## Perubahan file (unreleased)

| Path | Change |
|------|--------|
| _(kosong)_ | |

---

## Saat rilis — checklist agent

1. [ ] User konfirmasi nomor versi
2. [ ] Pindahkan `[Unreleased]` di `CHANGELOG.md` ke section versi baru + tanggal
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset tabel unreleased di file ini
7. [ ] Tag git: `git tag vX.Y.Z`
