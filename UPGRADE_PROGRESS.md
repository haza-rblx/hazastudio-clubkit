# Upgrade Progress - Club Kit

Scratch pad internal untuk track pekerjaan **sebelum** versi dirilis.

**Versi saat ini:** `2.4.68` (lihat [`VERSION`](VERSION))  
**Target rilis berikutnya:** _(belum ditetapkan)_

---

## Status ringkas

| Area | Status |
|------|--------|
| Plugin panel v2 (Engine/Tools UI) | WIP — ship rebuild nanti |

---

## Perubahan file (unreleased)

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/UpdaterPanel.luau` | Panel v2 UI (Engine/Tools) |
| `tools/ClubKitPackagerPlugin/plugin/DovetailTheme.luau` | AMOLED tokens |
| `tools/ClubKitPackagerPlugin/plugin/HazastudioClubKit.plugin.luau` | Wire Gen Tools / Carry fix callbacks |
| `tools/ClubKitPackagerPlugin/prototypes/plugin-panel-v2.html` | Design iterations |
| `tools/ClubKitPackagerPlugin/plugin-build/**` | Synced copies (panel v2) |

---

## Saat rilis - checklist agent

1. [ ] User konfirmasi nomor versi
2. [ ] Pindahkan `[Unreleased]` di `CHANGELOG.md` ke section versi baru + tanggal
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset tabel unreleased di file ini
7. [ ] Tag git: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** dari `tools/ClubKitPackagerPlugin` (plugin-build sync saja tidak cukup jika place Tool pakai binary lama)
