# Place-specific overrides — PARKLAB

Folder ini menyimpan **snapshot / catatan kode yang hanya ada di place PARKLAB** (placeId 80098131973647) dan **tidak** ada di repo engine. Format sama dengan [`places/atas-langit/`](../atas-langit/README.md).

## Aturan main

- **Jangan bulk-push `src/` ke place ini tanpa review folder ini dulu.** PARKLAB itu place-canonical: owner sering membangun/menyesuaikan langsung di Studio (GUI addon, admin panel v3, menu HP), dan sebagian edit engine-nya belum pernah masuk repo.
- Sebelum Update Engine / sync ke PARKLAB: baca **Daftar override aktif** di bawah dan putuskan per baris — port ke repo dulu, set config pengganti, atau terima hilang.
- PARKLAB juga sumber GUI addon untuk delivery pack (`1000-01-CT-ADDON`, `IconGroup.ADDON-FreeTitleEventTrigger`, `99-NotificationCenterV2` — lihat UPGRADE_PROGRESS "2.12.0 delivery pack").

## Log (terbaru dulu)

### 2026-10-12 — Fix UI HP: hotbar ACM + fokus panel (belum Ctrl+S)

- **Masalah:** (1) setelah menu avatar (ACM) ditutup, hotbar tetap hilang — watcher lama mem-bind `AvatarContextMenu.MainWrapper` sekali, padahal `AvatarContextLook.prepareWrapper` mengganti CanvasGroup itu dengan Frame baru saat panel boot, jadi koneksi mati dan hide terkunci (repro 1 dari 3 boot). (2) panel yang ditutup lewat tombol X/click-outside-nya sendiri tidak men-deselect icon topbar, jadi `MobilePanelManager.close` tidak pernah jalan dan semua GUI lain tetap `Enabled=false`.
- **Perubahan di place (via MCP, engine-only):**
  - `Client.Services.MobilePanelManager` — whole-file replace dari repo (bawa watchdog + nested-open close-previous). Live sebelumnya hanya beda oleh `notifyDancePanel`, yang tetap ada.
  - `Client.Services.InventoryChromeAnimator` — **surgical**, bukan replace: place masih punya `STICKER_WRAPPER_NAME`/`StickerButtonWrapper` yang sudah dihapus dari repo. Ditambah `_acmHiddenAt`/`ACM_RELEASE_GRACE`, timestamp di `notifyHide`, dan `setupAcmWatcher` versi baru (re-bind via ChildAdded/ChildRemoved + re-lookup tiap grace tick).
  - `Client.Controllers.AvatarContextController` — deps `notifyAcmOpen`/`notifyAcmClose`; `openPanel` meng-hide hotbar, `closePanel` me-release.
  - `Client.UI.AvatarContextUI` — `ui:open(delaySeconds)`; `setBeforeOpenCallback` dihapus.
  - `Main` — dua dep notify diteruskan ke factory controller; blok `setBeforeOpenCallback` dihapus. **Bukan replace** (place-only: menu HP sudah dibuang).
  - `Client.Controllers.CoupleController`, `Client.UI.MenuShellUI`, `Client.Controllers.AdminController` — jalur tutup men-deselect icon (requestClose / close callback / role-revocation).
- **Catatan en-dash:** `set_script_source` menormalkan U+2014 jadi `-` (emoji/em-dash place memang sudah mojibake sebelumnya). Komentar baru ditulis ASCII supaya push verifikasi bersih.
- **Verifikasi (solo playtest `mode=play`, iphone_13, client-1; semua runtime-only):** 5/5 boot ACM hide→release dengan `MainWrapper` sudah `Frame`. Nested open `couple`→`shop`: panel lama benar-benar tertutup (`couple=false`), setelah `close("shop")` drift 0 GUI. Shell nyata (`makeShell({})`): `hide()` memicu close callback tepat 1×. Desktop: `notifyAcmOpen()` = 0 dan hotbar tidak pernah hide. Log 200 entri terakhir: tanpa error kit, tanpa release watchdog.
- Detail: `.tmp/fixverify/RESULTS.md`.
- **Belum Ctrl+S.** Simulasi klik via `simulate_mouse_input` tidak sampai ke client playtest di sesi ini (widget topbar `AbsolutePosition.Y = -36`, `Visible = false` walau selected), jadi jalur tap X/click-outside diuji lewat fungsi yang dipanggil handler-nya, bukan tap piksel.

### 2026-10-09 — Overflow topbar jadi tiga titik + dropdown, Menu tetap di luar (belum Ctrl+S)

- Penyebab sebelumnya: yang berjalan di PARKLAB adalah `ReplicatedStorage.TopbarPlus.Icon` (TopbarPlus asli, dimuat pertama; `TopbarPlusReference` memakai salinan yang pertama). Overflow-nya strip horizontal yang terbuka sendiri dan titik tiganya tersembunyi. Edit saya sebelumnya hanya ke salinan kit, jadi tidak berpengaruh di sini (entri lama "terbuka sendiri sudah diperbaiki" salah).
- Sekarang: `Features/Overflow` yang sama (versi repo) dipasang di lima tempat di place: `RS.Icon`, `RS.Hazastudio_ClubKit.Icon`, dan dua folder `RS.TopbarPlus` (place-only, perlu diulang kalau folder itu diganti). `Main` mendapat satu baris `menuIcon.keepOutsideOverflow = true`.
- Playtest iPhone 7 (667 px) dari boot baru: kiri ⋯ (5 ikon), kanan `[Menu][⋯]` (2 ikon), dua-duanya tertutup; dropdown turun ke bawah. Belum dicek: layar yang melebar lalu menyempit lagi, dan ketukan nyata di HP.
- Lanjutan hari yang sama: ikon self custom title (Aa) juga selalu di luar, Menu paling kanan (⋯ di kirinya), baris dropdown dirapikan ala menu Roblox (44 px, ikon + label rata kiri). Label baris ikon-saja: Music/Freecam/Command Library dari `Main`; "Servers" dari satu baris `icon.overflowLabel = "Servers"` di `StarterPlayerScripts.SERVERLIST CLIENT` (script non-kit, place-only). Dicek di playtest iPhone 7 dari boot baru.
- Baris musik di dropdown = "Reload Music" (`MusicTopbarIcon` set `overflowLabel` + `overflowAction`), tombol ⋯ berubah jadi X saat terbuka (ukuran 3/4). Dicek: ketuk baris → toast "Track loaded.", dropdown menutup, baris tetap di dalam dropdown.
- Tidak tersentuh: `Model.S9_AttendanceTopbar.Icon` (salinan lain, tidak termuat).

### 2026-10-09 — Panel dance v3 dan menu HP (belum Ctrl+S)

- Panel `DancePanelGUIWrapperv3` di HP: skala 0.55, X 64, Y offset 43 (`Config.Sync.DANCE_PANEL_V3_*`). Di repo dan di place. Playtest iPhone 14 landscape: panel 121×313 di `(64,23)`, tidak menimpa hotbar (mulai x=187) atau tombol trigger. `MobileScaleService` dan `DancePanelUIBinder` disinkron dari repo.
- Menu HP `15-TopMenuGUI.TopBarMenuPhone`: tombol diberi `UICorner` dan `UIPadding` seperti desktop (template GUI, di place saja). Gradasi disc tetap dari twin HP, sesuai desain.
- Belum dicek visual: panel dance terbuka dan menu HP terbuka. Trigger tidak membuka panel saat di-tap dari script (state sync server).
- Onboarding tetap nonaktif di PARKLAB: `Config.Onboarding.ENABLED = false` dan sketch `17-OnboardingGUI` tidak ada.

### 2026-10-09 — Sync engine v3.0.0 + loading cinematic di PARKLAB (belum Ctrl+S)

- Engine (519 file) = repo 3.0.0, KitVersion 3.0.0. Menu HP "..." dibuang dari place atas keputusan owner (terima hilang); kode lama di `.tmp/parklab-presync-2026-10-09/engine-StarterPlayerScripts.rbxm`.
- `Trigger = "Topbar"` ditambahkan ke `ClubKitConfig.FreeTitleEvent`. Fill-forward menambah `Features.AutoDance`, `DonationSaweria`, `LeadDanceTopbar` (default ON) dan `ImageCustomTitle`, `HierapolisCustom` (default OFF).
- GUI kit diganti dari experiment (signature identik): 01, 02, 04-AdminHub, 04-AdminPanelv3, 06, 07, 09, 15-TopMenuGUI, IconGroup; ditambah 18-EventQuestPopup dan 19-EventReminders. RS: CoupleBoard, OverheadGUIMainTemplateV6, WorldEffects. GUI anak papan diganti, posisi dan ukuran papan PARKLAB tetap. Papan V3 (LevelDonationBoard, StreakBoard, CoupleBoard) belum dipasang.
- Dihapus: 19 modul engine yang tidak ada di v3, `_ClubKitManifest` ×2 (packager v2.5.2), `_ClubKitPackagerRunner` (v2.5.2), `RS.Carry` (tidak direferensikan).
- Dipertahankan: `ClubKitConfig`, `Secrets` (hash sama), `MusicCatalog`, Emotes (300), `RS.TopbarPlus` dan `RS.FOVState` (dipakai script non-kit), `ServerStorage.Tools`, map, Lighting, sistem non-kit.
- Loading: `Config.Loading.STYLE = "cinematic"` di `Shared/Constants/Config` PARKLAB saja (repo tetap `"classic"`). Verifikasi: config require OK, modul cinematic ada, solo playtest tanpa error kit. Belum ada `ClubKitConfig.Loading.ArtworkVideo/ArtworkImage` (bagian 1 pakai thumbnail experience) dan `Workspace.ClubKitCameraShots` (kamera otomatis). **Sync berikutnya mengembalikan ke classic.**
- Gradient papan memakai aset `115016970131979` yang belum di-share ke universe PARKLAB (log: "no access permission").
- Ketajaman papan: `PixelsPerStud` semua 18 SurfaceGui papan dinaikkan ×1,5 di Edit (Top 63/64→95/96, RobuxDonation/Community/Likes/Saweria 52→78, DailyDonations 32→48, LiveChat 26→39). Layout Scale, susunan tidak berubah. Re-import GUI dari experiment akan mengembalikannya.
- Poster Top Robux (Top1–3Robux): root `Frame` dari GUI experiment diganti `CanvasGroup`, karena `POSTER_FIELDS_V2` hanya membaca `CanvasGroup`. Sebelumnya renderer diam dan sampel "haza 230.000 / TOP #1" tetap tampil. Setelah refresh leaderboard, poster menampilkan data live (26.000 / 21.000 / 12.050). Re-import GUI dari experiment akan mengembalikan `Frame`.
- `DailyDonations` ada di Y=-275 (di bawah peta). Dengan StreamingEnabled part ini tidak sampai ke client, jadi log `DailyDonationsWrapper SurfaceGui not found` muncul. Posisi tidak saya ubah.

### 2026-10-06 — Ditemukan: ikon Free Title di topbar + menu titik-tiga HP = place-only

Ditemukan waktu memporting Free Title event ke ATAS LANGIT (lihat [`places/atas-langit/README.md`](../atas-langit/README.md) 2026-10-06). Tidak ada yang diubah di PARKLAB pada sesi ini — hanya dibaca dan diekspor (GUI addon via `export_rbxm`).

Yang ada di PARKLAB tapi tidak di repo (`git log -S freeTitleEventIcon` kosong):

1. **`Main` (client) — ikon topbar Free Title** (`freeTitleEventIcon`, gambar `Config.FreeTitleEvent.TOPBAR_ICON` = `rbxassetid://115281405771061`, order 8) + handler di `SettingsController.init` yang menunggu payload profil sampai 10 dtk lalu toast "Profile data belum siap". → **Sudah digantikan repo** oleh `ClubKitConfig.FreeTitleEvent.Trigger = "Topbar"` + `MenuShellUI:openCustomTitlePanelWhenReady` (unreleased, 2026-10-06).
2. **`Main` (client) — menu overflow "..." khusus HP**: di layout HP, ikon Admin / Command Center / Free Title dikeluarkan dari strip dan dipindah ke dropdown "..." (asset 6069276526) bersama Freecam dan Auto Dance (`phoneDropdownRegistry`). → **Belum ada di repo.** Owner: dibahas terpisah. Snapshot kode: [`Main-client-freetitle-topbar-and-phone-menu.luau`](./Main-client-freetitle-topbar-and-phone-menu.luau) (bagian 2). Assignment `phoneDropdownRegistry.freecam/.autoDance` di bagian bawah `Main` belum ikut disnapshot.
3. **`Client/UI/MenuShellUI` — `_wireFreeTitleEvent` dimatikan** dengan `if true then return end` (kartu overlay tidak pernah tampil). → **Digantikan repo** oleh gate `TitleEventDomain.showsOverlay(Config.FreeTitleEvent.TRIGGER)`.
4. `Shared/Constants/Config` — `FreeTitleEvent.TOPBAR_ICON` / `TOPBAR_ORDER` (sudah ada di repo sejak `b632198`).

Config buyer PARKLAB (dibaca 2026-10-06): `Features.SelfCustomTitle = true`; `CustomTitle = { MinLevel = 50, MaxChangesPerWindow = 5, WindowDays = 7, QuotaEnabled = false, FreeFirstTitle = true }`; `FreeTitleEvent = { Mode = "Any", RequiredLevel = 50, MinDonationRobux = 1000, MinDonationCash = 100000 }` — **belum punya `Trigger`**.

## Daftar override aktif

| File (path di place) | Snapshot | Apa | Status di repo | Sebelum sync berikutnya |
|---|---|---|---|---|
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Main` | [bagian 1 + 3](./Main-client-freetitle-topbar-and-phone-menu.luau) | Ikon topbar Free Title + tunggu payload | Digantikan (`Trigger = "Topbar"`) | Sudah ditambahkan ke config PARKLAB (2026-10-09). Cek lagi setiap sync. |
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Main` | [bagian 2](./Main-client-freetitle-topbar-and-phone-menu.luau) | Menu "..." HP (Admin / Command Center / Freecam / Auto Dance / Free Title) | **Tidak ada** | **Sudah dibuang dari place 2026-10-09** (owner: terima hilang). Port ke repo kalau mau dikembalikan. |
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Client.UI.MenuShellUI` | — (1 baris: `if true then return end` di `_wireFreeTitleEvent`) | Kartu overlay dimatikan | Digantikan (gate Trigger) | Sama dengan baris pertama (`Trigger = "Topbar"`). |
| `ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config` | — | `Config.Loading.STYLE = "cinematic"` (repo: `"classic"`) | **Tidak ada di repo** (eksperimen, flag off) | **Sync berikutnya reset ke `"classic"`.** Putuskan: port jadi buyer key (ADR 0001), atau terima kembali ke classic. |
| `Client.Services.InventoryChromeAnimator` | [`.tmp/live-fix/ICA.push.luau`](../../.tmp/live-fix/ICA.push.luau) | Masih menangani `STICKER_WRAPPER_NAME`/`StickerButtonWrapper` (repo sudah menghapusnya, instance-diet Phase 2) | **Beda dari repo** — sengaja | Jangan whole-file replace ICA saat sync engine. Kalau place akhirnya menghapus sticker, ambil versi repo dan buang patch 2026-10-12 yang sudah tidak relevan. |

## Catatan lain

- Engine PARKLAB secara umum di belakang/berbeda dari repo (lihat UPGRADE_PROGRESS "PARKLAB full engine sync — 2026-09-10" dan backlog "PARKLAB's engine is broadly behind the repo"). Hash `Main`/`MenuShellUI`/`Config` PARKLAB ≠ ATAS LANGIT ≠ repo per 2026-10-06, walau ketiganya KitVersion 2.12.0.
- `ServerStorage.1000-01-CT-ADDON_BACKUP_2026-09-09` = backup GUI Custom Title lama milik owner; jangan dihapus tanpa tanya.
