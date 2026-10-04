# Place-specific overrides — ATAS LANGIT

Folder ini menyimpan **snapshot source** dari file engine yang dipatch **langsung di place ATAS LANGIT** (placeId 92480461280758) dan **TIDAK** dimasukkan ke repo engine. Setiap file di sini adalah "apa yang saat ini ada di place" — bukan untuk di-sync dari repo.

> Tujuan: supaya perubahan place-spesifik bisa di-revert, di-diff, atau di-apply ulang tanpa harus buka Studio / buka Version History.

## Aturan main

- **Jangan bulk-push `src/` ke place ini.** ATAS LANGIT itu place-canonical — sama seperti PARKLAB / Zenith Aquatic / THE BASIC TEST. Sync engine → place hanya via plugin **Update Engine** dari Studio itu sendiri (atau via MCP `set_script_source` per file yang memang diminta).
- File di folder ini **bukan sumber kebenaran untuk buyer lain.** Buyer lain tetap pakai versi repo (`src/ReplicatedStorage/Hazastudio_ClubKit/...`).
- Setiap file override harus punya header `-- PLACE-LOCAL OVERRIDE (ATAS LANGIT)` di source-nya supaya gampang dideteksi waktu buka di Studio.
- Kalau engine update dari repo membawa perubahan ke file yang sama, **manual merge** — jangan biarkan Update Engine overwrite override tanpa review.

## Log perubahan place (terbaru dulu)

### 2026-10-04 — AvatarGuard OFF + Logger verbose OFF (session "oversize accessories")

Konteks: owner investigasi laporan "player dengan avatar gede kehilangan aksesoris 3D" + notifikasi Discord "detected oversize". Pelaku: **AvatarGuard** (`Server/Init/RuntimeGuard.luau`, ADR 0008 Layer 2c) — trim server-side aksesoris > 10 studs / karakter > 14×10 studs. Terbukti live: inject aksesoris 25-stud → destroyed < 2 s, log `Avatar trimmed | reason=oversized`.

Dua perubahan di place (via MCP `edit_script_lines`, editor-safe):

1. **AvatarGuard dimatikan untuk venue ini** — `ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig` (buyer config, TIDAK ikut engine sync): section baru `ClubKitConfig.AvatarGuard = { Enabled = false, ... }` di atas `return ClubKitConfig`. Avatar besar = dress code venue ini, jadi tidak ada trim / notif player / beacon Discord.
   - Landing di engine-nya butuh 2 file: `Shared/Config/ClubKitConfigSchema.luau` (defaults section) + `Shared/Config/ConfigBootstrap.luau` (proyeksi buyer → `Config.AvatarGuard`) — di-patch minimal (blok AvatarGuard saja, konten = repo) karena full sync akan menyeret perubahan 3.0 yang belum rilis.
   - Repo sudah punya fitur lengkapnya (schema + template + ConfigBootstrap) — place hanya menerima potongan kecil.
2. **Logger verbose override dihapus (revert)** — `ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger` kembali **byte-identical dengan repo** (2479 chars, verified). Place sebelumnya memaksa `MIN_LEVEL = LEVELS.DEBUG` di semua environment supaya log kelihatan di console live; owner minta matiin lagi. Sekarang: Studio tetap verbose, live production hanya ERROR merah.

Verifikasi (solo playtest, place tidak berubah): `Config.AvatarGuard.ENABLED=false` di VM runtime; aksesoris 25-stud **selamat** (sebelumnya hancur); log `AvatarGuard armed` hilang; DEBUG/INFO/WARN McpVerify test 3/3 tetap keluar di Studio; `loadstring` parse OK semua file.

⚠️ **Update Engine di place ini akan menimpa** schema + bootstrap patch (mereka engine files) — tapi tidak bahaya: section `AvatarGuard` di buyer config tetap dibaca ConfigBootstrap versi baru (fitur sudah di repo), jadi guard tetap off. Yang hilang cuma kalau engine di-place di-update ke versi yang LEBIH TUA dari repo sekarang — tidak mungkin (updater hanya maju).
- Buyer config ATAS LANGIT lebih tua dari template repo (621 vs 969 baris; belum punya AntiTamper/Telemetry/Overhead/Graphics/DailyQuest section) — **jangan pernah wholesale-replace** buyer config place ini; fill-forward plugin akan handle key baru.

## Daftar override aktif

> **⚠️ 2026-10-04: snapshot file belum ditarik** — Studio terputus sebelum snapshot full-file sempat dibuat (bridge UP, instance kosong). Semua patch hari ini sudah diverifikasi live via playtest **sebelum** disconnect (AvatarGuard off + Logger revert). Konten patch yang di-push terdokumentasi: blok `AvatarGuard` di [`ClubKitConfigSchema.luau`](../../src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau) + [`ConfigBootstrap.luau`](../../src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau) repo (identik dengan yang di-push) dan section `AvatarGuard` di tail buyer config place. Tarik ulang saat Studio terbuka (lihat prosedur di bawah).

| File (path di place) | File snapshot | Apa yang diubah | Kenapa | Cara revert |
|---|---|---|---|---|
| `ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig` (buyer config — bukan engine) | *(pending pull)* | Section `AvatarGuard` baru: `Enabled = false` (+ limits default), ditanam di atas `return ClubKitConfig`. | Avatar besar = dress code venue; trim AvatarGuard menghapus aksesoris sah. | Hapus section `AvatarGuard`, atau set `Enabled = true` untuk jalan tengah (mis. `MaxAccessoryStuds = 30`). |
| `ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.ClubKitConfigSchema` | *(pending pull)* | Patch minimal (blok `AvatarGuard` defaults saja; konten = repo). Place engine ±60–120 baris di belakang repo — jangan dianggap snapshot versi repo. | Dukung section buyer baru agar `Enabled=false` terbaca runtime. | Update Engine normal akan menimpa dengan versi repo penuh (aman — fitur sudah di repo). |
| `ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.ConfigBootstrap` | *(pending pull)* | Patch minimal (blok proyeksi `AvatarGuard` saja; konten = repo). Sama seperti di atas — versi place lebih tua dari repo. | Proyeksi buyer → engine `Config.AvatarGuard`. | Update Engine normal akan menimpa dengan versi repo penuh (aman — fitur sudah di repo). |

(Tidak ada lagi engine override aktif — Logger sudah di-revert ke repo, byte-identical. Snapshot `Logger.luau` versi verbose dipindah ke arsip di bawah.)

## Arsip override (sudah tidak aktif)

| File (path di place) | File snapshot | Apa yang pernah diubah | Kapan di-revert |
|---|---|---|---|
| `ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger` | [`archive/Logger-verbose.luau`](./archive/Logger-verbose.luau) | `MIN_LEVEL = LEVELS.DEBUG` always (log keluar di console live production). | 2026-10-04 — owner request; kini byte-identical repo, live hanya ERROR. |

## Cara apply override ke place (via MCP)

```powershell
# Asumsi MCP server UP dan instance ATAS LANGIT sudah connect.
# Contoh: apply Logger override
python -c "import json; code=open('places/atas-langit/Logger.luau','r',encoding='utf-8').read(); json.dump({'instancePath':'ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger','source':code,'instance_id':'<INSTANCE_ID>'}, open('.tmp/mcp-apply.json','w',encoding='utf-8'))"
.\.tmp\mcp-call.ps1 -Tool set_script_source -ArgsFile .tmp\mcp-apply.json
```

Setelah apply: **Ctrl+S** di Studio supaya place tersimpan (UpdateSourceAsync dirty-flag, tapi tetap manual save), lalu **File → Publish** supaya live server pakai source baru.

## Cara revert override (balik ke versi repo)

```powershell
# Ambil versi repo, push via MCP ke path yang sama
python -c "import json; code=open('src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/Logger.luau','r',encoding='utf-8').read(); json.dump({'instancePath':'ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger','source':code,'instance_id':'<INSTANCE_ID>'}, open('.tmp/mcp-revert.json','w',encoding='utf-8'))"
.\.tmp\mcp-call.ps1 -Tool set_script_source -ArgsFile .tmp\mcp-revert.json
```

## Tarik snapshot ulang (Studio ATAS LANGIT terbuka + connect)

Tarik `.Source` tiga instance di tabel atas via `execute_luau` target `edit` (bridge UP + `get_connected_instances` menunjukkan place 92480461280758), simpan sebagai `ClubKitConfig.luau` / `ClubKitConfigSchema.luau` / `ConfigBootstrap.luau` di folder ini (UTF-8, LF), lalu hapus tanda *(pending pull)* dan blok peringatan di tabel atas. Verifikasi cepat: `ClubKitConfig.luau` berisi `AvatarGuard` dengan `Enabled = false`; dua file lainnya berisi blok `AvatarGuard` identik dengan repo.
