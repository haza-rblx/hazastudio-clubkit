# Music Player v3 — rencana implementasi

**Status (diperbarui 2026-09-15):** disetujui owner 2026-09-13.
- **Di `main` (belum dirilis, `VERSION` masih 2.12.0):**
  - Stage A: `5cf781c`.
  - Stage B: `71bdaee`, rute VPS live sejak 2026-09-13.
- **Di `music-v3`:**
  - Stage C: `94383dc`.
  - Stage D+E: `c7c0b2f`.
  - Motion: `8cc1a10`.
  - Stage F: `622d23e`, belum di-push.
- **Di `ui-motion`:** ADR 0011, tiga commit, belum di-push. Branch ini dibangun di atas Stage F.
- **Belum di-commit:** cover dan private/public playlist, serta cover per track (§ 4b).

Sisa pekerjaan sebelum 3.0 dikumpulkan di `UPGRADE_PROGRESS.md` § "3.0 — what is left before release". Keputusan produk ada di `CONTEXT.md` (§ Music roles & tiers, § Music player GUI v3) dan ADR 0010.
**Basis:** kit 2.12.0. Target: v3 menggantikan v2 di **3.0**.

## Prinsip yang tidak boleh dilanggar

1. **Tiap stage bisa dirilis sendiri dan bisa dibatalkan sendiri.** Stage yang menyentuh `main` selalu di balik flag atau tidak mengubah perilaku v2.
2. **Ringan = jumlah instance, jumlah pekerjaan per frame, jumlah baris.** Angka acuan di § Gerbang.
3. **Tanpa glitch audio.** `Sound` yang sedang main tidak pernah dihancurkan/dibuat ulang; pause/resume/seek dilakukan di instance yang sama. `SoundEffect` dimutasi di tempat (aturan CLAUDE.md).
4. **Server mengirim state penuh, bukan delta.** Setiap setter di client wajib `return` lebih dulu kalau nilainya tidak berubah.
5. **VPS boleh mati kapan saja.** Musik harus tetap jalan dari cache. HTTP 403 dari kill switch (`maintenance_until`) diperlakukan sebagai *unreachable*, bukan *library kosong*.
6. **Register budget** (ADR 0002): tiap file baru ≤ 170 local top-level, dicek `.\tools\count-locals.ps1` sebelum tiap merge.

## Strategi cabang

- `main` — rilis harian tetap jalan. Menerima Stage A dan B (tidak tergantung GUI, berguna untuk v2 juga, dan mengurangi divergensi).
- `music-v3` — cabang dari `main`, menerima Stage C–E. Di-rebase ke `main` minimal tiap minggu. Merge sekali di Stage F.

Alasan: mendukung dua GUI dalam satu codebase memaksa `MusicPlayerUIBinder` (158/200 local) menampung dua jalur — pasti jebol.

> **Terselesaikan (2026-09-13):** git dipasang (winget). Cabang `music-v3` dibuat di `5cf781c` (commit Stage A) dan sudah di-push. Stage B tetap di `main`; Stage C–E di `music-v3`.

---

## Stage A — Fondasi (`main`, rilis 2.13)

### A1. Kebersihan GUI di Studio (mock `06-MusicPlayerGUIv3`)
Sudah: `CanvasGroup` 0, `UIShadow` 13 (semua di elemen tunggal, tidak ada di template baris).
Sisa:
- [x] Nama kembar antar-saudara → unik (11 instance): `PrivateWall.Title`/`Description`; `TrackListLeft.Wrapper.CoverImage`/`OwnerAvatar`/`BackdropFar`/`BackdropNear`; `QueueListTemplate.Wrapper.BackdropFar`/`BackdropNear`; header DJ `Title`/`Value` dan `Title`/`Description`. (`2-TrackCreator` ×2 sudah dibereskan owner sebelumnya.)
- [x] Buang atribut sisa konversi `Old__*` (15).
- [ ] ~~`Enabled = false` pada ScreenGui v3~~ — **ditunda**: owner masih mendesain di viewport; matikan sebelum playtest yang tidak menguji v3, atau di Stage F.
- [ ] ~~`Config.MobileScale.MUSIC_GUI` dihitung ulang~~ — **pindah ke Stage F**: mengubahnya di `main` sekarang ikut mengecilkan v2 milik buyer.

### A2. Privilege `musicControl` (ADR 0010, konsekuensi ke-5)
- `PermissionDomain`: tambah `musicControl`; `MusicService.isControlAllowed(player)`.
- `ClubKitConfigSchema` + template `ClubKitConfig.luau`: key baru di `RoleCategories`. **Jangan** edit file buyer.
- Fill-forward: kalau buyer belum punya `musicControl`, warisi nilai `musicManage`. Ditulis TDD (`tdd-luau`, harness di `.tmp/`), nilai harapan independen.
- Gate yang pindah ke `musicControl`: tab DJ, DJ mode/effects/speed/soundboard, admin skip, playlist private.
- **Sekalian tutup D1 (sweep DoS 2026-09-11):** `MusicDurationReport` hanya diterima dari client yang sedang memutar track itu dan hanya memperpendek/memperpanjang dalam batas wajar; tidak boleh memicu skip global.

**Gerbang A:** test fill-forward hijau; DJ di place test bisa buka private, pemain biasa tidak; v2 tidak berubah perilakunya untuk buyer yang config-nya belum di-update.

**Hasil A2 (2026-09-13):** spec `music-control-privilege` 20/20 dan `music-duration-policy` 33/33 (lune, red dulu); sync 11 file, parity 446/446; pewarisan terbukti dari config asli place untuk 7 role; `MusicDurationReport(totalDuration = 1)` dari client tidak mengganti lagu. Fill-forward tidak lewat patch teks config — lewat `RoleCategoryBuilder.build` saat boot. Satu perubahan perilaku disengaja: library read-only kini tetap punya kontrol live. Belum diuji live: akun tanpa kontrol (akun Studio = Staff).

---

## Stage B — Library dari web (clubkit-infra + kit, `main`, rilis 2.13–2.14)

Ini transport **(B)** ADR 0010. Belum ada di kedua sisi.

### B1. Sisi VPS (repo `clubkit-infra`)
- `clubkit-api`: `GET /game/:key/v3/music/library`. Auth = Bearer game secret yang sudah dipakai `LicenseService` (jalur yang sama, bukan infrastruktur baru). Loopback ke brm-api lewat `X-Internal-Token` (env), scope per `universe_id` (kolom `library_items.universe_id` sudah ada).
- Respons: `{ revision, playlists[], tracks[] }`. Tiap track membawa `durationSeconds`, `playbackSpeed` **eksplisit `1.0`** untuk track asset-ID (jangan `nil`), `visibility`, `creator`, cover, `parts`. Header `ETag = revision`; `If-None-Match` → **304** tanpa body. Poll dari game jadi murah.
- `POST /game/:key/v3/music/library/import` — hanya diterima selama web library universe itu kosong (migrasi satu kali, ADR 0010).
- Kill switch tetap 403 di jalur ini; kit yang menanganinya (B2).

### B2. Sisi kit
- `Features.MusicWebLibrary` di schema + template, **default `false`** di 2.13.
- `Server/Services/MusicLibraryProvider.luau`: urutan boot **cache dulu** (`MusicLibrary_v1`) → render → fetch web → kalau `revision` berubah: tulis cache, panggil `onLibraryReloaded`. Poll tiap 60 s dengan ETag. Gagal apa pun (timeout, 5xx, 403) → tetap pakai cache, log sekali per menit, bukan tiap poll.
- Reload di tengah lagu: `pruneDeletedTracks` sudah ada — hanya menyentuh antrean, **tidak pernah** track yang sedang main.
- Di mode web, `managePlaylist`/`manageTrack` menolak dengan pesan "edit di dashboard".
- Boot pertama di bawah flag dengan web kosong → ekspor DataStore ke `/import` (B1).

**Gerbang B:** place `thebasic` jalan 1 minggu dengan flag `true`: edit di dashboard muncul di game ≤ 60 s tanpa restart; VPS dimatikan → musik tetap jalan dari cache; `maintenance_until` diset lampau → musik tetap jalan; HTTP ≤ 2 req/menit/server saat idle.

---

## Stage C — Kerangka client v3 (`music-v3`)

### C1. Resolver
`Client/UI/Music/GuiRefs.luau` — satu nama satu elemen, `assert` kalau hilang, **tanpa** varian nama/fallback. Tipe `Refs` mengikuti pohon v3 (≈55 field, bukan 100+).

### C2. Pecah per tampilan (menyelesaikan register budget sekaligus)
```
Client/UI/Music/
  GuiRefs.luau          resolve sekali
  ListPool.luau         virtual list + row pool (diangkat dari binder v2, ~350 baris, dipakai 3 list)
  NowPlayingView.luau   hero, DJ-on-stage, progress, queue, transport row
  LibraryView.luau      playlist list, detail page, DJ Sets, PrivateWall, Request From ID
  DjView.luau           port dari v2 (CanvasGroup → Frame sudah dilakukan di mock)
  Transport.luau        pembungkus remote client (requestId, rate-limit lokal)
Client/Controllers/MusicPlayerController.luau   tinggal orkestrasi store ↔ views
```
Tiap view: `new(refs, store, config)`, `mount()`, `unmount()`, tidak tahu view lain.

### C3. Aturan render (dari audit v2)
- Refs anak template diselesaikan **sekali per baris pool** (`row.refs = {title, creator, length, cover, likeBtn, addBtn}`); bind hanya set teks/gambar. Tidak ada `FindFirstChild` di jalur panas.
- Diff sebelum sentuh instance: queue dibandingkan per `entryId`, hanya baris yang berubah di-rebind.
- Progress bar: teks detik hanya saat detiknya berganti; lebar bar boleh per frame (satu properti).
- Search debounce 150 ms; render ulang hanya daftar yang sedang tampil.
- Preload gambar hanya untuk jendela virtual yang terlihat (+buffer), bukan seluruh library.
- DJ Sets diturunkan **sekali** saat library masuk (`store.djSets`), dari library yang sudah difilter server → private tidak bocor.
- Transisi tab: `Visible` + pop `UIScale` yang sudah ada. Tidak ada tween `GroupTransparency` (tidak ada `CanvasGroup`).
- Liked Tracks = `favoriteTrackIds` yang sudah ada; hanya label yang berubah.

**Gerbang C:** panel v3 terbuka di playtest, tiga tab bisa dipilih, tidak ada error, `count-locals` tiap file ≤ 170.

**Hasil C (2026-09-13, `music-v3`, belum di-commit):** `Client/UI/Music/GuiRefs.luau` (101 baris, `need()` assert per elemen) + `Client/UI/Music/PanelShell.luau` (≈200 baris) menggantikan `MusicPlayerGuiRefs`/`MusicPlayerUIBinder` di `ClientModuleBag`; `Config.Music.GUI_NAME = "06-MusicPlayerGUIv3"` di cabang ini. `PanelShell` menyediakan seluruh permukaan binder yang dipanggil `MusicPlayerController` — method render/Manage sengaja no-op sampai Stage D/F — jadi mesin playback tidak disentuh. Diuji di THE BASIC TEST lewat menu topbar sungguhan: buka → Now Playing, DJ (drag panel mati), Library (drag hidup), tutup (blur dilepas); 0 error kit, 0 `CanvasGroup`, 682 instance. Bug yang ketemu dan sudah diperbaiki: `isControlAllowed` sudah `true` sebelum controller subscribe, jadi shell tidak pernah menerimanya dan klik DJ jatuh ke Now Playing — `bindAll` kini menerapkan nilai store saat bind. **Catatan desain untuk owner:** `Option3.LayoutOrder` sama dengan `Option2` (1); nama `PlaylistNonIMageTemplateNormal` (huruf M besar) dipakai apa adanya oleh resolver — kalau di-rename, ubah juga `GuiRefs`.

---

## Stage D — Isi tampilan (`music-v3`)

Urutan: **Now Playing (tanpa transport) → Library → DJ.** Tiap satu selesai, playtest 2 pemain (`multiplayer_playtest`: satu DJ, satu biasa).

- Now Playing: hero + DJ-on-stage toggle dari `isDjMode`; queue + Remove (requester boleh hapus miliknya, `musicControl` boleh semua); Vote Skip; `ClearQueueButton` dan transport row **disembunyikan** sampai Stage E.
- Library: 6 template playlist; detail page; Like; Add sets / Shuffle memanggil `requestMany` (Stage E — sebelum itu tombol dinonaktifkan); PrivateWall; Request From ID (kode lama, frame cocok).
- DJ: port.

**Gerbang D:** semua yang v2 bisa (kecuali Manage) v3 bisa; zero error dua boot berturut-turut; instance `PlayerGui` musik saat Library terbuka dengan 60 baris ≤ 800.

**Progres D (2026-09-13, `music-v3`, belum di-commit):**
- **Now Playing — selesai, diuji di THE BASIC TEST.** `Visuals` (setter idempoten: teks, visible, cover, headshot), `NowPlayingView` (hero ↔ DJ-on-stage dari `isDjMode`, progress 5 Hz dengan teks hanya saat detik berganti dan berhenti saat panel tertutup, antrean ber-pool yang di-rebind per entri), `VoteModalView` (port v2, bar 4 Hz). Transport row, Clear Queue, Remove disembunyikan sampai E. Terbukti dengan data asli: judul/kreator/playlist/requester, waktu jalan, baris antrean dari request remote ("Queued by : haza" + avatar), DJ-on-stage (nama, avatar 420, "controlled by"). Belum teruji: vote modal (butuh ≥2 pemain).
- **Library — dibangun, sebagian diuji.** `Shared/Domain/MusicLibraryModel` (urutan playlist/track, cari plain-text, DJ Sets per kreator tanpa placeholder "Unknown…"; spec lune 26/26, red dulu), `ListPool` (virtual list + spacer, redraw digabung per frame), `LibraryView` (Liked Tracks, New Drops berlabel bulan, playlist image/non-image, DJ Sets, detail set terpilih, like/add dengan jeda 1 dtk, cari debounce 150 ms, PrivateWall, Request From ID hanya bila Manage diizinkan). Controller memuat semua track sekali → `allTracks`/`djSets`; memilih DJ Set tidak memanggil server. **Server:** playlist private kini tetap dikirim sebagai kartu tanpa `trackIds` ke non-`musicControl`, dan track-nya dikeluarkan dari semua daftar (all/favorit/new drops) — sebelumnya "all tracks" membocorkannya. Terbukti: 9 track, 4 DJ Set, sorotan baris terpilih, detail New Drops. Belum teruji: klik like/add, cari, PrivateWall (butuh akun tanpa `musicControl` — uji 2 pemain oleh owner).
- **DJ — dibangun, diuji kering.** `DjView`: switch DJ mode (kembali sendiri bila server menolak), soundboard dari `Config.Music.DJ`, kecepatan (slider + 5 preset), efek suara per `EFFECTS` (toggle + slider per item). Semua slider berbagi satu pasang listener input global; perubahan yang ditolak controller (bukan DJ mode) kembali ke nilai lama karena `PanelShell._fire` kini meneruskan nilai balik callback. Aturan v2 ikut di-port: saat DJ mode aktif, pemain tanpa kontrol kehilangan tab Library dan Vote Skip. Uji kering di edit mode pada salinan GUI: semua ref ter-resolve, 4 soundboard, 6 efek / 18 slider, preset 1.5x tersorot, toggle Echo menyala, EQ Low "5db". Belum diuji di playtest (sesi owner sedang berjalan).
- **Belum:** uji 2 pemain (vote modal, PrivateWall, gating DJ mode) oleh owner; ukuran Gerbang D "≤ 800 instance dengan 60 baris" belum bisa diukur (library uji hanya 9 track).

---

## Stage E — Aksi transport (`music-v3`, server + client)

Semua remote baru: payload divalidasi, `requestId` idempoten, rate limiter, gate `musicControl` kecuali yang disebut. Sync ikut jalur state-sync yang ada, di-coalesce seperti `DJ_EFFECTS_SYNC_HZ`.

| Aksi | Server | Client | Catatan anti-glitch |
|---|---|---|---|
| **Pause / Resume** | state `isPaused`, `pausedElapsed`; resume: `startServerTime = now − pausedElapsed`, hitung ulang `expectedEnd` | `sound:Pause()` / `sound:Resume()` — instance sama | **Timer idle/auto-advance berhenti selama pause**, kalau tidak lagu lompat sendiri. Vote skip tetap boleh saat pause. |
| **Rewind −10 s / Seek +10 s** | geser `startServerTime`, clamp `[0, durasi−1]` | set `TimePosition` **hanya jika drift > 0,75 s** dari yang sudah main | Koreksi drift kecil dibiarkan; loncatan hanya saat pengguna memang minta. |
| **Previous** | `playedHistory` ring 20 id (sesi saja). Elapsed > 3 s → ulang dari 0; ≤ 3 s → pop history, track sekarang dikembalikan ke depan antrean | — | Semantik pemutar musik umum; antrean tidak berubah diam-diam. |
| **Next** | = `adminSkip` (ada) | — | — |
| **Clear queue** | hapus request pemain saja; auto-buffer sistem terisi lagi | tekan 2× dalam 3 s (tidak ada modal di v3) | Tidak menyentuh track yang sedang main. |
| **Remove from queue** | by `entryId`, bukan index | — | Index balapan dengan server. Requester boleh hapus miliknya (bukan gate). |
| **requestMany(trackIds, shuffle)** | cap 25, pakai `REQUEST_TRACK_RATE_*` | Add sets / Shuffle | Bukan gate — pemain biasa boleh, kena rate limit. |

**Keputusan implementasi E (2026-09-13):** satu remote `MusicTransport` dengan field `action` (bukan tujuh remote). Logika waktu murni di `Shared/Domain/MusicTransportPolicy` (spec lune 53/53): pause membekukan `pausedElapsed`, resume/seek menggeser `startServerTime`+`expectedEndServerTime` sehingga timer auto-advance, progress bar, dan posisi `Sound` membaca satu jam. **Menyimpang dari tabel di atas:** `requestMany` untuk pemain biasa dibatasi sisa slot `REQUEST_TRACK_MAX_PER_USER_QUEUE` (nilai engine saat ini **100**, bukan 3 seperti yang sempat tertulis di sini — dikoreksi 2026-09-14), bukan 25 — cap 25 (`REQUEST_MANY_MAX`) hanya untuk `musicControl`, supaya satu playlist tidak memborong antrean pemain lain. Ikon pause: desain hanya punya satu ikon; atribut `PauseImage` (opsional `PlayImage`) pada `PlayorPauseButton.ImageLabel` membuat tombol berganti ikon.

**Gerbang E:** pemain biasa yang menembak remote gate langsung ditolak server (uji dengan `eval_client_runtime`); pause 5 menit lalu resume → posisi tepat, tidak ada auto-advance; seek bolak-balik 20× tanpa klik audio; dua client posisinya selisih < 1 s.

---

## Stage F — Potong rilis 3.0 (merge `music-v3` → `main`)

**Keputusan owner 2026-09-14 (ronde 1):**
- **Q1 = a:** halaman Musik dibuka untuk semua venue di 3.0. `music_enabled` hanya menggate upload/YouTube (ADR 0010 addendum 2026-09-14). Ini butuh perubahan di clubkit-infra sebelum rollout.
- **Q2 = b:** Request From ID menjadi *play-once*: masuk antrean untuk satu kali putar, tidak ditulis ke library.
- **Q3:** `MusicCatalog.luau`, `MusicCatalogSeed`, dan `MusicReadOnlyLibrary` tidak lagi dibaca engine, schema menandainya pensiun, dan file milik buyer tidak disentuh.
- **Q4 (urutan):** rilis 2.13 dulu dari `main` (Stage A/B, daily like, fix ikon admin v3). Setelah itu merge `music-v3` → `main` dan kerjakan Stage F di sana.
- **Q5 (gerbang):**
  - Sebelum merge: uji otomatis + uji solo + uji 2 pemain oleh owner.
  - Sebelum rilis 3.0: instance ≤ 800, MicroProfiler (Reclass mati), emulator HP, VPS mati, `maintenance_until` lampau, join saat pause.
- **Q6:** sesuai rencana di bawah (rename GUI, RBXM wajib, RBXM v2 untuk rollback, `Enabled = false`, `MobileScale` dihitung ulang).

**Keputusan owner 2026-09-14 (ronde 2):**
- **Q7 = b:** Request From ID (putar sekali) terbuka untuk semua pemain, kena rate limit request dan jatah antrean per pemain. Owner menerima risiko moderasi audio. Server tetap menolak asset yang bukan Audio.
- **Q8 = c:** halaman Musik terbuka otomatis per venue begitu game-nya melapor kit ≥ 3.0 lewat heartbeat lisensi. Sebelum itu halaman menjelaskan bahwa update dulu.
- **Q9 = b:** rilis 2.13 ditunda. Isi tambahannya ditanyakan di ronde 3.

**Keputusan owner 2026-09-14 (ronde 3):**
- **Q10:** request putar sekali punya batas sendiri: maksimal 1 lagu menunggu per pemain dan 3 permintaan per 10 menit. Ditambah saklar buyer `Music.PlayOnceRequest` = `"everyone"` (default) / `"control"` / `"off"` lewat schema + template.
- **Q11:** 2.13 tidak menambah isi. Isinya tetap Stage A, Stage B (flag mati), daily like reset, dan fix ikon Admin Panel v3.

**Urutan eksekusi F:**
1. Rilis 2.13 dari `main` (menunggu "okay this is update 2.13"). **Status 2026-09-15:**
   - Belum dirilis.
   - Urutan ini perlu dikonfirmasi ulang oleh owner, karena pekerjaan sudah berlanjut di `ui-motion` di atas Stage F.
   - Lihat checklist 3.0 di `UPGRADE_PROGRESS.md`.
2. Merge `music-v3` → `main`. **Status 2026-09-15:** belum. `ui-motion` sudah memuat `music-v3`.
3. Kit:
   - Hapus kode Manage, binder v2, dan `MusicCatalogSeeder`. **Status 2026-09-14:** kode Manage + `MusicCatalogSeeder` terhapus (irisan 2–3); file binder v2 dihapus dari repo (owner, `git rm`); tiga ModuleScript-nya juga sudah dihapus dari place THE BASIC TEST lewat MCP. `MusicCatalog.luau` template dibiarkan (ADR 0010: pensiun, bukan dihapus).
   - Pensiunkan `MusicReadOnlyLibrary`/`MusicCatalogSeed` di schema.
   - ~~Default `MusicWebLibrary = true`.~~ **`MusicWebLibrary` ikut pensiun, web selalu nyala** (owner 2026-09-14; ADR 0010 addendum). Alasan: patch config 2.13 menulis `MusicWebLibrary = false` ke file buyer, jadi default baru tidak akan sampai.
   - Request From ID jadi putar sekali, dengan batas dan saklar di atas.
   - `count-locals`.
4. clubkit-infra: halaman Musik terbuka per venue saat `kit_version_sort` ≥ 3.0; upload/YouTube tetap digate `music_enabled`.
5. Place: rename GUI v3 → `06-MusicPlayerGUI`, hapus v2, `Enabled = false`, hitung ulang `MobileScale`, RBXM v2 untuk rollback. **Status 2026-09-14 (THE BASIC TEST):** selesai. RBXM v2 di `docs/releases/3.0.0/rollback/06-MusicPlayerGUI_v2.rbxm`, dicek lengkap sebelum v2 dihapus; `MUSIC_GUI` 0.56 (belum diukur di emulator HP). Ketemu dan dibetulkan: `get_state` tidak membawa `isPlayOnceAllowed`, jadi kotak Request From ID di v3 tersembunyi.
4b. **clubkit-infra: cover + private/public playlist (owner 2026-09-15, belum di-deploy).** Temuan: warna dashboard (hex `playlists.color`) tidak pernah sampai ke game, karena playlist tanpa gambar selalu terkirim sebagai gradien 1. Preview gambar di dashboard juga rusak (`assetdelivery` sekarang 403). `visibility` tidak ada di brm-api, dan import sekali jalan membuangnya. Keputusan dan perubahan:
   - Dashboard hanya menawarkan 8 gradien kit.
   - Cover gambar tetap berupa asset ID, divalidasi lewat `GET /library/cover-assets` (endpoint publik Roblox, tanpa key). Decal ditolak.
   - Cover hanya per playlist; override per track tidak dikerjakan.
   - Kolom `playlists.visibility` (migration `0014`, `NULL` = belum diset web) diterima POST/PATCH, dikirim di pull, dan dibawa import/merge.
   - Toggle Public/Private di dialog, gembok di kartu.
   - Kit tidak diubah.
   - Test brm-api 101 lulus / 1 skip; `tsc` brm-api + dashboard bersih.
   - Q6: riwayat versi `MusicLibrary_v1/Playlists` THE BASIC sejak 2026-07-20 tidak pernah punya playlist private, jadi tidak ada yang hilang.
   - **Deploy:** `bun src/db/migrate.ts` wajib dijalankan manual, karena unit systemd tidak menjalankan migration. **Live 2026-09-15** (brm-api + dashboard).
   - **Q3 dibalik owner di hari yang sama: cover gambar per track.**
     - brm-api menyimpan `payload_json.coverImageAssetId`. `PATCH /uploads/library/:id` menerimanya, dan nilai `""` mengosongkannya. Pull hanya mengirim `coverType = "image"` bila nilainya terisi. Import membawa override gambar dari game, sedangkan override gradien dibuang.
     - Dashboard: Edit track → Cover → Ikut playlist / Gambar sendiri. Cek Decal memakai komponen yang sama dengan dialog playlist.
     - Kit: `MusicRepository.cloneTrack` + `_serializeTracks` sebelumnya membuang cover track. Sudah dibetulkan, spec lune 9/9 (red dulu), dicatat di CHANGELOG `[Unreleased]`.
     - Test brm-api 109 lulus / 1 skip.
     - Belum di-deploy, dan fix kit belum di-sync ke place.
6. Gerbang sebelum merge (step 2): uji 2 pemain oleh owner. Gerbang sebelum rilis 3.0: angka performa.
7. `code-review` dua sumbu, dokumen rilis 3.0.0. Bump versi hanya setelah "okay this is update 3.0".

- Hapus kode Manage: `MusicPlayerUIBinderPart2` (~140 ref), `MusicPlayerUIBinder` (~56), `MusicPlayerController` (~78), `MusicController` (~35); `MusicCatalogSeeder`, `MusicCatalog.luau`; modal Track/Playlist.
- `Features.MusicWebLibrary` default `true`; `MusicReadOnlyLibrary` dipensiunkan (fill-forward abaikan).
- Ganti nama v3 → `06-MusicPlayerGUI`, v2 dihapus dari StarterGui; `Config.Music.GUI_NAME` tetap.
- `count-locals` semua file; `code-review` dua sumbu (Standards vs Spec).
- Dokumen rilis: `docs/releases/3.0.0/UPGRADE.md` (buyer: **wajib RBXM** untuk ScreenGui; config fill-forward menambah `musicControl` dan `MusicWebLibrary`; migrasi library otomatis boot pertama; RBXM v2 disimpan di folder rilis untuk rollback), `CHANGED_FILES.md`, CHANGELOG.
- Bump `VERSION`, `KitProduct.KitVersion`, `ClubKitManifest.KIT_VERSION` — **hanya setelah owner bilang "okay this is update 3.0"**.

---

## Gerbang lintas-stage (dicek tiap merge)

| Ukuran | v2 sekarang | Target v3 |
|---|---|---|
| Instance ScreenGui (Studio) | 1.301 | ≤ 700 |
| Instance saat runtime, Library terbuka 60 baris | — | ≤ 800 |
| `CanvasGroup` runtime | 14 (+17 dari slider clone) | 0 |
| Baris kode client musik | ~10.600 | ≤ 4.500 |
| Local top-level per file | 158 (binder) | ≤ 170 semua, tidak ada file > 1.500 baris |
| Frame UI saat scroll Library (MicroProfiler) | belum diukur | ≤ 2 ms |
| HTTP idle per server | 0 | ≤ 2 req/menit |

Cara ukur: `capture_micro_profiler` via MCP; **matikan plugin Reclass** dulu (makan ~50% CPU, semua angka bohong).

## Matriks QA per stage
Desktop; emulator Galaxy A16; `multiplayer_playtest` 2 pemain (DJ + biasa); VPS mati; `maintenance_until` lampau; boot dingin 2× berturut tanpa error; pemain join saat lagu jalan (sync posisi); pemain join saat pause.

## Rollback
- A: config fill-forward aditif — tidak ada yang hilang. B (2.13): `MusicWebLibrary=false`; mulai 3.0 flag itu pensiun, rollback = engine 2.x. C–E: cabang belum di-merge. F: RBXM v2 di `docs/releases/3.0.0/`, config lama tetap valid.
