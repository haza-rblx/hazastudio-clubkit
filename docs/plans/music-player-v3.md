# Music Player v3 — rencana implementasi

**Status:** disetujui owner 2026-09-13. **Stage A selesai 2026-09-13** (unreleased, terverifikasi di place template — detail di `UPGRADE_PROGRESS.md`). Stage B–F belum dimulai. Keputusan produk ada di `CONTEXT.md` (§ Music roles & tiers, § Music player GUI v3) dan ADR 0010.
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

> **Hambatan (2026-09-13):** git tidak terpasang di mesin ini (folder `.git` ada, executable tidak ada), jadi cabang `music-v3` belum bisa dibuat. Alternatif tanpa git: modul v3 ditulis di `main` sebagai file baru di `Client/UI/Music/` yang **tidak di-require** oleh v2 sampai Stage F — v2 tidak tersentuh, register budget binder lama tidak bertambah. Keputusan owner.

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

---

## Stage D — Isi tampilan (`music-v3`)

Urutan: **Now Playing (tanpa transport) → Library → DJ.** Tiap satu selesai, playtest 2 pemain (`multiplayer_playtest`: satu DJ, satu biasa).

- Now Playing: hero + DJ-on-stage toggle dari `isDjMode`; queue + Remove (requester boleh hapus miliknya, `musicControl` boleh semua); Vote Skip; `ClearQueueButton` dan transport row **disembunyikan** sampai Stage E.
- Library: 6 template playlist; detail page; Like; Add sets / Shuffle memanggil `requestMany` (Stage E — sebelum itu tombol dinonaktifkan); PrivateWall; Request From ID (kode lama, frame cocok).
- DJ: port.

**Gerbang D:** semua yang v2 bisa (kecuali Manage) v3 bisa; zero error dua boot berturut-turut; instance `PlayerGui` musik saat Library terbuka dengan 60 baris ≤ 800.

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

**Gerbang E:** pemain biasa yang menembak remote gate langsung ditolak server (uji dengan `eval_client_runtime`); pause 5 menit lalu resume → posisi tepat, tidak ada auto-advance; seek bolak-balik 20× tanpa klik audio; dua client posisinya selisih < 1 s.

---

## Stage F — Potong rilis 3.0 (merge `music-v3` → `main`)

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
- A: config fill-forward aditif — tidak ada yang hilang. B: `MusicWebLibrary=false`. C–E: cabang belum di-merge. F: RBXM v2 di `docs/releases/3.0.0/`, config lama tetap valid.
