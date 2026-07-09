# AGENTS — Hazastudio Club Kit

Panduan untuk AI agent (Cursor) saat bekerja di repo ini.

## Produk

- **Nama:** Hazastudio Club Kit (Basic Club Kit)
- **Versi aktif:** baca [`VERSION`](VERSION)
- **Source:** `src/` (Rojo) → deploy buyer pakai `.rbxm` (Club Kit Packager)
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
   - `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` → `KIT_VERSION`
6. **Reset** `UPGRADE_PROGRESS.md` (kosongkan unreleased, pertahankan template checklist).
7. **Ringkas ke user:** versi baru, highlight breaking changes, file buyer yang perlu dicek manual.

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

## Area sensitif

- `Config.luau` — shared constants; buyer biasanya pakai `ClubKitConfig.luau`
- `Secrets.luau` — jangan expose ke client
- DataStore keys versioned — hati-hati breaking migration
