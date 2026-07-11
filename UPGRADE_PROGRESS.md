# Upgrade Progress — Club Kit

Scratch pad internal untuk track pekerjaan **sebelum** versi dirilis.

**Versi saat ini:** `2.1.0` (lihat [`VERSION`](VERSION))  
**Target rilis berikutnya:** _(belum ditetapkan)_

---

## Status ringkas

| Area | Status |
|------|--------|
| v2.1.0 source-sync updater | ✅ Released |
| Gravity / Ungravity feature | 🚧 In progress |

---

## Perubahan file (unreleased)

| Path | Change |
|------|--------|
| `src/ServerScriptService/.../Services/GravityService.luau` | Added — server float physics |
| `src/ServerScriptService/.../Controllers/GravityController.luau` | Added — remote + chat commands |
| `src/StarterPlayerScripts/.../Controllers/GravityController.luau` | Added — Shift+G / Shift+U keybinds |
| `src/ReplicatedStorage/.../Constants/Config.luau` | Added `Config.Gravity`, `GravityEnabled` flag |
| `src/ReplicatedStorage/.../Config/ConfigBootstrap.luau` | Gravity feature flag mapping |
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | `Features.Gravity` |
| `src/ServerScriptService/.../Init/EarlyRemotes.luau` | Gravity remotes |
| `src/ServerScriptService/.../Main.server.luau` | Wire GravityService + controller |
| `src/StarterPlayerScripts/.../Main.client.luau` | Wire client GravityController |
| `src/ReplicatedStorage/.../Domain/CommandLibraryDomain.luau` | `/gravity`, `/ungravity` entries |

---

## Saat rilis — checklist agent

1. [ ] User konfirmasi nomor versi
2. [ ] Pindahkan `[Unreleased]` di `CHANGELOG.md` ke section versi baru + tanggal
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset tabel unreleased di file ini
7. [ ] Tag git: `git tag vX.Y.Z`
