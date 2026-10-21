# PARKLAB (`parklab`)

Catatan konfigurasi dan kustomisasi place-spesifik untuk **PARKLAB** ("[8 BIT EVENT] PARKLAB").
*Diperbarui: 2026-10-21*

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

## 6. Giveaway / Auto Gacha + SZV6 DJ (live-only, 2026-10-21)

Semua di bawah ini dipasang langsung di place (bukan dari repo). Port repo-nya ada terpisah (uncommitted) dan **belum** punya putaran polish terakhir (lihat akhir bagian ini).

**Instance di place:**
- `ServerScriptService.AutoGachaServer` (Script) — jadwal draw, spin, history, payout.
- `StarterPlayerScripts.AutoGachaClient` (LocalScript) — HUD card, toast reel, sheet admin.
- `ReplicatedStorage.AutoGachaProto` (Folder) berisi `WinFx` (ModuleScript, 15 cinematic). Remotes (`State`, `Spin`, `AdminRequest`, `History`, `Notice`) dibuat server saat runtime.
- Sumber kerja: `.tmp/auto-gacha/*.luau` (diserve `127.0.0.1:8765`, dipasang lewat `ScriptEditorService:UpdateSourceAsync`).

**Perilaku:**
- Draw tiap Interval kalau pemain ≥ Min players; kalau timer habis di bawah threshold → nunggu, spin begitu tercapai. Admin bisa Spin now / Reset timer.
- Prize dalam **Robux** (bukan "R$"). Pay = Roblox **Transfers API** (`PromptRobuxTransferAsync`, receipt `RobuxTransferSender` → auto Paid). Sender wajib Roblox Plus; 10–500 per prompt; penerima dapat 90%. Gagal prompt → fallback "Mark paid" manual. Di Studio transfer "optimistically succeed".
- Persist: DataStore `Giveaway_v1` key `state` = `{ v=1, nextId, history, pending, config }` (config: IntervalSeconds, MinPlayers, Anchor, PrizeText, WinFxVariant, Enabled, SpinDuration). Save debounce 6 s + BindToClose.
- Admin gate: `PermissionDomain.canUseAdminPanel(player:GetAttribute("_LKG_Role"), userId)` (Studio = semua). **Jangan pakai** `isAdminUser`/`CreatorId`: owner place ini (`hazatargz`, rank 254 di group 347553422) tidak lolos keduanya; `OverheadDomain.resolveRole(254)` balik `Guest` — role asli ada di attribute `_LKG_Role = "Staff"`.
- Entry admin: tile **Giveaway** di Admin Hub lama (`04-AdminHub`, section donations), di-clone client saat runtime. `ClubKitConfig.AdminHub = true` di place ini.
- Setting terakhir: Prize 50, Interval 45 min, Min players 50, Spin 5.5 s, Winner cinematic 4 (Ascension Vortex), Card position Top right.

**UI (disetujui owner):** HUD card (Hero "Tiles", stepper "Combo"); toast reel tengah saat spin lalu naik pas landing; sheet draggable tanpa dim overlay, skala = UIScale `1000-01-CT-ADDON` di desktop (+3 px font ≤16), di HP skala 1 dan dipas antara topbar–hotbar; HUD card geser keluar layar saat `15-TopMenuGUI` / `07-MenuGUI` / `1000-01-CT-ADDON` menutupinya; setting pakai **Save/Discard bar** (Card position langsung); History: Back pill + Edit → Delete → Confirm (server `deleteEntry`). Cinematic: 2,4 s terakhir kamera settle ke dada (bukan overhead tag). Dicek di iPhone 7 (667×375).

**SZV6 DJ console (pihak ketiga, server script obfuscated + phone-home — owner terima risikonya):**
- Dipindah dari `Workspace.SZV6` ke service asli (`SSS.DJMusic`, `SPS.DJMusic`, `ServerStorage.{LicenseConfig,MusicConfig,MusicLibraryStore}`, `StarterGui.DJMusicConsole`). Backup utuh: `ServerStorage.SZV6_backup`.
- Client: TopbarPlus diganti `ReplicatedStorage.Hazastudio_ClubKit.Icon` (kit), pill gaya kit, `setOrder(20)` kiri setelah ABSEN.
- `MusicConfig.IsDJ`: admin kit (cek `_LKG_Role` seperti di atas, nunggu attribute ≤15 s) + group DJ lama `721052710` rank 202/254.
- Dropdown topbar musik kit: **Reload Music / Reload DJ Music** (baris "Music Player" dihapus atas permintaan owner; player tetap dibuka dari top menu). "Reload DJ Music" = MusicResync dari seller (DJControl `RequestSync` → tunggu DJBroadcast `StateSync` ≤5 s → Loaded!/Failed). Keduanya diubah di **engine copy place** `Client/UI/MusicTopbarIcon.luau` (setupMenu) — hilang kalau engine PARKLAB di-upgrade, pasang ulang. Script MusicResync terpisah dari seller **tidak** dipasang (butuh `Packages.TopbarPlus`).
- Belum: auto-mute musik kit saat deck SZV6 main.

**Progress (per 2026-10-21):**
- [x] Giveaway terpasang permanen di place (server + client + WinFx), DataStore `Giveaway_v1` bersih dari data mock.
- [x] Pay via Transfers API — alur lengkap teruji di Studio (Studio selalu sukses).
- [x] Responsive iPhone 7, hide-on-menu, Save bar, skala CT, Back/Edit/Delete, kamera settle — terpasang; **sebagian belum dicek visual** setelah perubahan terakhir (font +3, sheet 320×552, Back/Edit, kamera settle, label Robux, Reload DJ Music).
- [x] SZV6 dipindah ke service asli + tombol DJ di topbar kit (admin kit + rank 202/254 group `721052710`).
- [x] Dropdown musik: Reload Music / Reload DJ Music.
- [ ] Owner **Save + Publish** PARKLAB.
- [ ] Tes live: transfer Robux sungguhan (akun admin dengan Roblox Plus) + tombol DJ untuk admin vs non-admin.
- [ ] Auto-mute musik kit saat deck SZV6 main.
- [ ] Opsional: opsi "Mark paid" manual yang selalu ada (kalau dibayar di luar panel); matikan rank group DJ kalau mau admin-only.
- [ ] Sinkron polish terakhir ke port repo (daftar di bawah), lalu tes di place hasil sync repo.

**Belum masuk port repo:** hide-on-menu, Save bar, skala CT + font bump, sheet 320×552, Back/Edit/Delete, camera settle, label "Robux", fix canvas scroll saat UIScale. Repo pakai Admin Spotlight (bukan tile Admin Hub).

---

## 7. Wajib setelah edit

Ctrl+S lalu Publish PARKLAB — semua perubahan di atas baru sampai ke buyer setelah publish.
