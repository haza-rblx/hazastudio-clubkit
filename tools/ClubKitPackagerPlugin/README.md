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

### Opsi A — Copy folder (dev)

1. Copy folder `tools/ClubKitPackagerPlugin/` ke:
   ```
   %LOCALAPPDATA%\Roblox\Plugins\HazastudioClubKitPackager\
   ```
2. Restart Roblox Studio.

### Opsi B — Rojo sync (dev)

```bash
rojo serve tools/ClubKitPackagerPlugin/default.project.json
```

Lalu connect dari Studio plugin Rojo ke folder Plugins.

### Opsi C — Simpan sebagai `.rbxm` (distribusi ke buyer)

1. Install plugin di Studio (Opsi A).
2. Buat place kosong → insert plugin folder sebagai model sementara **atau** jalankan dari dev Plugins folder.
3. Klik kanan folder plugin → **Save to File** → `HazastudioClubKitPackager.rbxm`.
4. Buyer: drag `.rbxm` ke `%LOCALAPPDATA%\Roblox\Plugins\`.

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
