# Port AFK rejoin dari inifixdulu — plan (2026-10-10)

Goal: menit 10 AFK → rejoin → mendarat di posisi lama → sync ke leader sebelumnya (kalau masih ada), else lead terbanyak, else dansa solo terakhir.

Keluhan yang dikejar: rejoin **terjadi**, tapi (a) balik ke spawn, atau (b) posisi benar tapi tidak ke-sync ulang. Deteksi + teleport tidak diubah kecuali angka menit.

## Akar masalah (dari perbandingan kode)

| | inifixdulu (works) | hazastudio (gagal) |
|---|---|---|
| Kapan restore | **Setelah** client lapor selesai loading | Pivot + sync di `CharacterAdded` (client masih loading) + 2 jalur cadangan |
| Kalau sinyal "loaded" telat | Timeout 60 dtk → **tetap pivot + sync** | Timeout 60 dtk → **menyerah**, tidak ngapa-ngapain |
| Jumlah jalur | 1 | 3 (spawn-time, native-respawn, finalize) saling tunggu lewat tabel pending |

Pivot saat loading ditimpa client/loading screen venue → spawn. CharacterAdded kedua menghapus `Syncing`. Cek ulang kita hanya lihat status server, bukan track yang benar-benar main.

## Perubahan (4 file, tidak sentuh buyer file / DataStore / Main.*)

### 1. `SessionCommandService.luau` — satu jalur mendarat
- Teleport arrival (AFK **dan** /rejoin manual, keduanya kasus yang sama) **tidak lagi** di-restore di `CharacterAdded`. Hapus `finalizeRejoinRestore`, cabang native-respawn untuk sync AFK, dan pemakaian `pendingJoinRestore`/`pendingAfkSyncRestore` di `restoreAfterCharacterAdded`.
- Respawn biasa di dalam server (`pendingRespawnRestore`) **tidak diubah**.
- Fungsi baru `restoreArrival(player, cframe, syncPayload)`, dipanggil sekali dari `applyJoinTeleportData`:
  1. Tunggu `ClientGameplayReady` (sudah dikirim `Main.client.enterGameplay`, sesudah hold loading screen venue). Timeout → **lanjut juga** (perilaku inifix).
  2. Tunggu karakter sekarang + HRP (≤10 dtk).
  3. `CharacterReady.pivotTo` ke posisi lama.
  4. `syncService:restoreAfterAfkRejoin(...)` (logika pilih leader yang sudah ada: leader lama → tunggu grace kalau leader lagi rejoin juga → lead terbanyak → solo).
  5. **Verifikasi +2 dtk dan +5 dtk**: posisi melenceng >8 stud → pivot ulang; dansa diharapkan tapi **track tidak benar-benar main** → reset sync player lalu restore ulang.
  6. Satu log `rejoin_arrival` berisi: ready/timeout, jarak akhir, hasil sync, berapa kali re-assert. Kalau masih gagal live, log ini langsung nunjuk tahap mana.
- Karakter diganti (CharacterAdded) **sebelum** langkah 5 selesai → ulang dari langkah 2 (maks 2×).

### 2. `SyncService.luau` — helper kecil
- `isDanceTrackPlaying(player)`: cek Animator server via `AnimatorUtils.getPlayingDanceTrack` yang sudah ada.
- Reset sebelum restore ulang lewat jalur UNSYNC yang ada (`handleSyncRequest(p, nil, false)`), karena memanggil sync ke leader yang sama malah **toggle off**.

### 3. `Config.luau` (konstanta engine, bukan config buyer)
- `REJOIN_LADDER`: 600 same / 690 same / 780 any / 870 any (dari 780/870/960/1050). `IDLE_THRESHOLD_SEC = 600`.
- `AUTO_REJOIN_RATE_WINDOW = 540` (harus < rung pertama supaya streak setelah rejoin di server yang sama dapat token).
- `RESTORE_CLIENT_READY_TIMEOUT = 120` (artinya sekarang: batas tunggu sebelum restore jalan juga, bukan batas menyerah).

### 4. Docs
`CHANGELOG.md [Unreleased]`, `UPGRADE_PROGRESS.md` (4 file Replace, tanpa buyer file).

## Bukti sebelum dianggap selesai

**Studio (solo, pakai `ServerStorage.ClubKitStudioRejoinProbe` yang sudah ada):**
- T1 posisi: berdiri jauh dari spawn → replay arrival dengan client "loading" → kirim ready → HRP ≤3 stud dari posisi lama.
- T2 dansa solo: joget → replay → track dansa main di Animator server.
- T3 ready tidak pernah datang → setelah timeout tetap pivot + dansa (timeout dipendekkan khusus tes).
- T4 dipaksa ke spawn 0,5 dtk setelah ready (meniru loading screen venue) → re-assert balikin.
- T5 sync dihapus paksa setelah restore → re-assert sync ulang.
- Wajib **merah dulu di kode lama** (T3, T4, T5), lalu hijau di kode baru.

**Live (satu-satunya cara uji teleport + leader; butuh 2 akun, server publik sepi):**
- Build tes di Experiment Area dengan rung pertama 150 dtk (bukan 10 menit), sisanya sama. Kembalikan ke 600 sesudahnya.
- Skenario: (L1) follower AFK, leader tetap joget → balik posisi + sync ke leader. (L2) leader AFK → balik joget sendiri, follower ke-bind ulang. (L3) follower AFK, leader keluar → sync ke lead terbanyak / solo. (L4) masing-masing 3× berturut-turut.
- Cek log `rejoin_arrival` di F9 server console tiap percobaan.

## Rollout
repo → Studio T1–T5 → sync ke Experiment Area → owner Ctrl+S + publish → live L1–L4 → baru sync ke place klien (cek `KitVersion` dulu).

## Di luar scope
Deteksi AFK (`Player.Idled`), rate limiter/ladder mechanics, logika pilih leader — semuanya tidak diubah.
