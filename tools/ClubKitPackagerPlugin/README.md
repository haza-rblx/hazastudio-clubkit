# Hazastudio Club Kit Packager

Plugin Roblox Studio untuk **export** dan **unpack** seluruh aset Club Kit v1.3 dalam satu klik — termasuk script, GUI, leaderboard boards, tools, donation effects, dan WorldEffects.

## Yang di-pack otomatis

| Service | Isi |
|---------|-----|
| `ReplicatedFirst` | `Hazastudio_ClubKit` |
| `ReplicatedStorage` | `Hazastudio_ClubKit`, `Icon`, `WorldEffects`, opsional `Hazastudio_ClubKitConfig` |
| `ServerScriptService` | `Hazastudio_ClubKit`, opsional `Hazastudio_ClubKitSecrets` |
| `StarterPlayerScripts` | `Hazastudio_ClubKit` |
| `StarterGui` | GUI `01-` … `15-`, `IconGroup`, `HotbarGUI`, `CommandLibraryGUI`, dll. |
| `ServerStorage` | `Tools`, `DonationEffects`, `DonationSounds` |
| `Workspace` | Leaderboard boards, poster Top1–3, `LiveChatDonations`, `RunningText` |

## Install plugin

### Opsi A — Install `.rbxm` (disarankan)

Dari root repo:

```powershell
.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1
```

Restart Roblox Studio → toolbar **Hazastudio Club Kit** muncul di tab Plugins.

Buyer cukup **pasang RBXM sekali**. Setelah itu update dari dalam panel:
**Settings → Update plugin** (soft-update dari GitHub) → **Engine → Update engine**.
Place harus Enable HTTP Requests (sama seperti Update Engine).

### Soft-update plugin (in-app)

Plugin fetch `tools/ClubKitPackagerPlugin/plugin/*.luau` dari tag GitHub publik
(`ClubKitManifest.UPDATER`) lalu remount via `loadstring` — **tidak** menimpa file
`.rbxm` di folder Plugins. Bootstrap (`HazastudioClubKit.plugin.luau`) tetap dari install.
Kalau bootstrap sendiri berubah besar, sebar RBXM baru (jarang).

Urutan wajib: **Update plugin dulu**, baru **Update engine**.

### Opsi B — Copy folder (tidak cukup)

Copy folder saja **tidak** cukup — Roblox hanya load `.rbxm` / `.plugin.luau`, bukan folder `init.server.luau` biasa. Pakai Opsi A.

```bash
rojo serve tools/ClubKitPackagerPlugin/default.project.json
```

Lalu connect dari Studio plugin Rojo ke folder Plugins.

### Opsi C — Simpan sebagai `.rbxm` (distribusi ke buyer)

1. Install plugin di Studio (Opsi A).
2. Buat place kosong → insert plugin folder sebagai model sementara **atau** jalankan dari dev Plugins folder.
3. Klik kanan folder plugin → **Save to File** → `HazastudioClubKitPackager.rbxm`.
4. Buyer: drag `.rbxm` ke `%LOCALAPPDATA%\Roblox\Plugins\`.

## Dev hot-reload (tanpa restart Studio)

Iterasi UI/kode panel tanpa rebuild RBXM + restart:

```powershell
# 1. Sekali saja setelah RBXM berubah: rebuild + restart Studio
.\build-plugin-rbxm.ps1

# 2. Jalankan dev server (biarkan terbuka)
.\dev-serve.ps1          # serves plugin/*.luau di http://127.0.0.1:8798
```

3. Edit file `.luau` di `plugin/` → save.
4. Di Studio: toolbar **Hazastudio Club Kit** → **Reload Panel**
   (atau `reload_clubkit_panel()` dari command bar).

Panel di-destroy dan dibangun ulang dari source terbaru via `HttpService` +
`loadstring`. Kalau dev server mati, Reload jatuh ke modul bundled (tidak error).
Yang **tidak** ikut hot-reload: `HazastudioClubKit.plugin.luau` (bootstrap) dan
file modul baru yang belum ada di RBXM — itu tetap butuh rebuild + 1 restart.

## Cara pakai

### Export (dari place sumber / dev kit)

1. Buka place yang sudah punya **semua** aset kit (script Rojo + GUI/board/tools di Studio).
2. Toolbar **Hazastudio Club Kit** → **Export RBXM**.
3. Atur opsi di panel **Club Kit Packager** (config/secrets).
4. Pilih lokasi simpan → file `HazastudioClubKit_v1.3.rbxm`.

### Unpack (di target / buyer place)

1. Toolbar **Hazastudio Club Kit** → **Unpack RBXM**.
2. Pilih file `.rbxm` hasil export.
3. Plugin menempatkan instance ke service yang benar.
4. Default: **tidak menimpa** `ClubKitConfig` dan `Secrets` buyer jika sudah ada.

Alternatif: import `.rbxm` manual ke Explorer → pilih folder package → **Unpack Pilihan**.

## Setelah unpack (buyer)

1. Edit `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig`
2. Edit `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets`
3. Hapus `ClubKitShowcase` untuk mode live (opsional)
4. Publish

Panduan lengkap: [`CLUB_KIT_SETUP.md`](../../CLUB_KIT_SETUP.md)
