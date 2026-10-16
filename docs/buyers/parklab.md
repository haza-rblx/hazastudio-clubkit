# PARKLAB (`parklab`)

Catatan konfigurasi dan kustomisasi place-spesifik untuk **PARKLAB** ("[8 BIT EVENT] PARKLAB").
*Diperbarui: 2026-10-16*

- PlaceId: `80098131973647`
- Owner: Group `347553422` ("LABS Project") — semua animasi yang dipakai place ini harus milik group ini, kalau tidak gagal load (kaku) di live game.
- Buyer / pelapor: Rezz (Discord `#ticket-0003`).

---

## 1. Konfigurasi Place-Spesifik

| File | Key | Nilai | Catatan |
|---|---|---|---|
| `Shared/Constants/Config.luau` (engine) | `Loading.STYLE` | `"cinematic"` | Satu-satunya beda dari repo (repo: `"classic"`). Jaga saat sync Config. |
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` (buyer-owned) | `Features.ImageCustomTitle` | `true` | Dinyalakan 2026-10-16 (tab title gambar di admin panel v3). |
| `Adonis_Loader.Config.Settings.General` | `HelpButton` | `false` | Tombol "?" Adonis dimatikan 2026-10-16. Adonis `DataStoreEnabled = true`: setting dari in-game editor bisa menimpa file ini. |

---

## 2. Perubahan GUI / Aset Place-Owned (tidak ada di repo)

| Instance | Perubahan | Backup |
|---|---|---|
| `StarterGui.15-TopMenuGUI.TopBarMenu` | Frame → ScrollingFrame (menu desktop bisa scroll, tinggi dibatasi layar oleh `TopMenuController`) | `ServerStorage._Backup_TopBarMenu_2026-10-16` |
| `StarterGui.IconGroup.DancePanelGUIWrapperv3…MainContent` | `FavoritedState` dobel dihapus (muncul sebagai row "Starred") | `ServerStorage._Backup_DanceFavoritedStateDup_2026-10-16` |
| `ReplicatedStorage.WorldEffects.Smite3/Smite4.Animations.Giant_MainAnimation` | AnimationId → `113015250242386` (milik group). Lama: `107761545784496` (milik user `aurfavb0y`, kaku di live) | Attribute `_PrevAnimationId` di tiap Animation |
| `StarterGui.15-TopMenuGUI.TopBarMenuPhone` | Eksperimen 2026-10-09: isi section desktop | `ServerStorage._Backup_TopBarMenuPhone_2026-10-09` |

Backup script yang di-sync 2026-10-16 (versi sebelum fix): `ServerStorage._Backup_Scripts_2026-10-16` (MusicSession, MusicService, ProfileTabBinder, MusicDomain, SessionCommandService, Config, MenuSettingsCore, ClubKitConfig, Adonis_Settings_General), plus 4 `*_preAssetProbe` (lihat §5).

---

## 3. Status Sync Engine

- 2026-10-16: semua script engine PARKLAB = repo (cek checksum 522 script), kecuali `Config` (`Loading.STYLE`).
- Fix tiket di-commit di repo: `8b61a3e` (top menu scroll), `d9ca475` (Dance template dobel), `21e8558` (music/AFK/scroll HP).
- Server brm-api (VPS) ikut di-fix 2026-10-16: placeholder `partDurations` (< 5 s) tidak dikirim lagi.

---

## 4. Ticket #0003 (Rezz) — status 2026-10-16

✅ Menu scroll / Settings
✅ Private autoplay
✅ WIB length
✅ Image title tab
✅ AFK rejoin
✅ Profile and slider scrolling on phone
✅ Starred row in the Dance panel
✅ Dance missing
✅ Hammer animation
✅ Missing panel
✅ Adonis "?" button turned off
✅ Discord link

Dibiarkan: menu terlalu ramai (feedback desain).

**Catatan teknis:**
- AFK rejoin ke server lain tidak bisa sync dance kalau leader tidak di sana (batasan sistem).
- Web library: ±222 dari 641 track masih `totalDuration = 0` dari brm-api; server pakai fallback ±4,5 menit sampai client melapor panjang asli.

---

## 5. Auto-skip audio rusak / ke-revoke (2026-10-16)

Server mengecek sendiri apakah audio tiap track bisa di-load (`MusicAssetProbe`), lalu track yang `Failure` (revoke, private belum di-share, 404, bukan audio) di-skip otomatis. Jaringan player tidak ikut menentukan. Engine: commit `ab9a2d3` di repo, isinya identik dengan place (hash `MusicAssetProbe` cocok, dicek ulang setelah Ctrl+Z tidak sengaja).

| Script di place | Perubahan | Backup |
|---|---|---|
| `Server.Services.MusicAssetProbe` | **Baru** | — |
| `Server.Services.MusicSession` | Skip cache Failure, watcher track yang jalan, prefetch 2 track berikutnya + setiap request | `MusicSession_preAssetProbe` |
| `Server.Services.MusicService` | Request From ID ditolak `asset_unavailable` | `MusicService_preAssetProbe` |
| `Client.Controllers.MusicPlayerController` | Pesan "This audio can't be played (private or removed)." | `MusicPlayerController_preAssetProbe` |
| `Server.Init.RuntimeGuard` | `__MusicAssetProbe` di `KIT_ROOT_NAMES` | `RuntimeGuard_preAssetProbe` |

Backup ada di `ServerStorage._Backup_Scripts_2026-10-16`.

**Track rusak di library PARKLAB** (sekarang di-skip, tapi sebaiknya diganti/dihapus di web library):
| Track | trackId | Asset | Masalah |
|---|---|---|---|
| Trance | `3f0b49bb-340a-4847-8887-afca1e902d00` | `125021736394780` | 404 (aset tidak ada) |
| SOEGI BORNEAN - ASMALIBRASI AMAPIANO | `track-3d8fe05c-0322-41ca-a1c0-e9ac20f7f21f` | `123789` | Ini ID Place, bukan audio |

Scan 2026-10-16: 641 track, 26 part milik creator lain (bukan group `347553422`). Semuanya sudah di-share ke experience dan bisa diputar.

**ID buat tes ulang** (playtest, datamodel Server, bukan Edit):
- Private belum di-share: `130776150` → Failure
- 404: `125021736394780`, HTTP 400: `186755541`, `145138004` → Failure
- Bagus: `105958496375506`, foreign yang sudah di-share: `101701249998517` → Success
- Edit mode tidak bisa dipakai buat tes: ID 404 pun hasilnya Success.

**Batasan:** status fetch di-cache engine per ID. Audio yang di-revoke setelah server sempat memutarnya baru ketahuan di server baru.

---

## 6. Wajib setelah edit

Ctrl+S lalu Publish PARKLAB — semua perubahan di atas baru sampai ke buyer setelah publish.
