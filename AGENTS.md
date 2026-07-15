# AGENTS — Hazastudio Club Kit

Panduan untuk AI agent (Cursor) saat bekerja di repo ini.

## Produk

- **Nama:** Hazastudio Club Kit (Basic Club Kit)
- **Versi aktif:** baca [`VERSION`](VERSION)
- **Source:** `src/` (Rojo) → deploy buyer via **Studio plugin source sync** (git tag) atau `.rbxm` manual (Packager)
- **Buyer config (jangan replace saat update):**
  - `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
  - `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
- **Engine (replace saat update):** folder `Hazastudio_ClubKit` di ReplicatedFirst, ReplicatedStorage, ServerScriptService, StarterPlayerScripts + StarterGui terkait

## Git (version control)

Git portable ada di `.tools/git/` (tanpa install system-wide).

```powershell
# Dari root project:
.\git.ps1 status
.\git.ps1 log --oneline -10
.\git.ps1 diff
.\git.ps1 diff v1.3.0..HEAD --name-only   # setelah ada tag
```

Saat rilis, agent bisa pakai `git diff` / `git log` untuk generate `CHANGED_FILES.md` otomatis.

**Branch default:** `main`  
**Jangan commit** `Secrets.luau` isi production — sudah di `.gitignore` pattern untuk `.local` only; file Secrets template boleh masuk repo jika kosong.

---

| File | Fungsi |
|------|--------|
| [`CHANGELOG.md`](CHANGELOG.md) | Changelog user-facing (Keep a Changelog) |
| [`UPGRADE_PROGRESS.md`](UPGRADE_PROGRESS.md) | Progress development sebelum rilis |
| [`HANDOVER.md`](HANDOVER.md) | Audit history v1.3 |
| [`CLUB_KIT_SETUP.md`](CLUB_KIT_SETUP.md) | Setup buyer |
| [`docs/releases/`](docs/releases/) | Upgrade guide per versi |

---

## Workflow: user bilang "oke ini update X.Y"

Contoh trigger: *"oke ini update 2.1"*, *"rilis versi 1.3.1"*, *"buat changelog untuk update ini"*.

### Langkah wajib agent

1. **Baca versi lama** dari `VERSION` (dan `ClubKitManifest.KIT_VERSION` jika ada).
2. **Kumpulkan perubahan** dari:
   - [`UPGRADE_PROGRESS.md`](UPGRADE_PROGRESS.md)
   - Percakapan / task terbaru
   - Scan file yang dimodifikasi di session (jika git tidak ada, andalkan tabel di UPGRADE_PROGRESS + eksplorasi)
3. **Tulis changelog** — pindahkan isi `[Unreleased]` di `CHANGELOG.md` ke section `[X.Y.Z]` + tanggal hari ini.
4. **Buat release folder:** `docs/releases/<X.Y.Z>/`
   - `UPGRADE.md` — panduan buyer: apa yang diganti, apa yang dipertahankan, langkah deploy
   - `CHANGED_FILES.md` — daftar file berubah vs versi sebelumnya, dikelompokkan:
     - **Replace** (core kit)
     - **Buyer edit sendiri** (config/secrets — jangan timpa)
     - **Opsional** (StarterGui, tools, docs)
5. **Update versi** di:
   - `VERSION`
   - `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` → `KitVersion`
   - `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` → `KIT_VERSION`
6. **Reset** `UPGRADE_PROGRESS.md` (kosongkan unreleased, pertahankan template checklist).
7. **Ringkas ke user:** versi baru, highlight breaking changes, file buyer yang perlu dicek manual.

### Rilis harian — source sync (tanpa RBXM)

Untuk update Luau engine saja (workflow utama):

```powershell
# Dari root project — validasi + tag + push:
.\tools\release.ps1              # dry-run: cek VERSION / KitProduct / Manifest sinkron
.\tools\release.ps1 -Execute     # commit (jika ada perubahan), tag vX.Y.Z, push main + tag
.\tools\release.ps1 -Execute -GhRelease   # opsional: gh release create (notes-only, no assets)
```

Atau manual:

```powershell
.\git.ps1 add -A
.\git.ps1 commit -m "release: v2.1.0"
.\git.ps1 tag v2.1.0
.\git.ps1 push origin main
.\git.ps1 push origin v2.1.0
```

**Buyer / dev di Studio:** Plugin → **Check Update** → **Update Engine** → Save place.

Plugin fetch dari **public GitHub repo** (`ClubKitManifest.UPDATER.githubOwner` / `githubRepo`). Config `ClubKitConfig` dan `Secrets` tidak pernah disentuh. StarterGui, Workspace boards, ServerStorage assets **tidak** ikut source sync — deploy manual / RBXM jika berubah.

Set `UPDATER.githubOwner` / `githubRepo` di `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` sebelum publish repo.

### Rilis penuh — RBXM (jarang)

Untuk fresh install atau kirim GUI/board/models ke buyer tanpa Rojo: Studio → **Export RBXM** → kirim file ke buyer → **Unpack RBXM**.

---

### Format `CHANGED_FILES.md`

```markdown
# Changed Files — v1.3.0 → vX.Y.Z

## Summary
- X files changed
- Breaking: yes/no

## Core — replace via RBXM
| Path | Change |
|------|--------|

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|

## Tools / docs only
| Path | Change |
|------|--------|
```

### Format `UPGRADE.md` (buyer)

```markdown
# Upgrade vOLD → vNEW

## Quick steps
1. Backup ClubKitConfig + Secrets
2. Hapus folder Hazastudio_ClubKit lama
3. Insert RBXM baru
4. Restore / merge config jika perlu

## What's new
(bullet dari changelog)

## Config changes
(field Config baru / berubah — jika ada)

## QA setelah upgrade
(checklist singkat)
```

### Saat development (bukan rilis)

- Tambah entry di `[Unreleased]` di `CHANGELOG.md` (Fixed/Added/Changed)
- Update tabel file di `UPGRADE_PROGRESS.md`
- **Jangan** bump `VERSION` sampai user konfirmasi rilis

---

## Konvensi kode

- Luau `--!strict` di file baru
- Minimize scope — jangan refactor tidak diminta
- Match style file sekitar
- Jangan commit kecuali user minta

### Luau local-register budget (~200)

Luau crashes with `Out of local registers` if a function/chunk exceeds ~200 locals. **Main.server / Main.client** and fat UI binders are hottest.

- Prefer `Client/Init/*` or `Server/Init/*` bags (one `require` → table of modules) over adding more top-level `local X = require(...)` to Main.
- Do **not** unpack bag fields back into many top-level `local`s — that defeats the point.
- Treat ≥170 top-level `^local` as freeze; ≥185 as treat-as-blocker before merge.
- Check: `.\tools\count-locals.ps1` (optional `-FailAt 185`).

## Area sensitif

- `Config.luau` — shared constants; buyer biasanya pakai `ClubKitConfig.luau`
- `Secrets.luau` — jangan expose ke client
- DataStore keys versioned — hati-hati breaking migration
