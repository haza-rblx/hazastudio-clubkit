# Upgrade v2.4.71 → v2.4.72

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place (no new Config keys this release — nothing to fill-forward)
3. QA checklist di bawah

`ClubKitConfig` / `Secrets` tidak di-replace utuh, seperti biasa.

## What's new
Patch hasil audit full-codebase — **tidak ada fitur baru buyer-facing**. Semua perubahan adalah bug fix atau pengetatan izin di aksi yang sudah privileged:

- **Data loss dicegah** — favorites (dance/music), koleksi sticker, dan XP level tidak lagi hilang kalau save gagal tepat saat player disconnect / DataStore lambat. Retry otomatis lewat pending-flush, mengikuti pola yang sudah ada di `SettingsService`.
- **Boot client lebih tahan banting** — kalau ada remote atau folder GUI yang hilang/telat, client dulu bisa menggantung selamanya (loading screen macet). Sekarang timeout lalu soft-disable fitur terkait saja (warn), gameplay tetap masuk.
- **Dance panel di HP** — kalau wrapper mobile (`DancePanelGUIWrapperv2Mobile`) hilang, panel dulu `error()` dan mematikan seluruh dance boot task. Sekarang fallback ke layout desktop.
- **HotbarInventoryService** — tidak lagi menumpuk koneksi `ChildAdded`/`ChildRemoved` tiap respawn.
- **3 celah abuse ditutup** (P1 dari audit):
  - Sticker **global pool** sekarang admin/Studio-only untuk tulis; sticker milik pemain biasa tetap tersimpan ke koleksi pribadinya.
  - `MusicService:resolveOrCreateTrackForAsset` (resolve ID jadi track + masuk playlist bersama) sekarang butuh izin DJ/admin (`isManageAllowed`) — dulu terbuka untuk semua pemain.
  - `CommandLibraryController` sekarang punya gate izin terpusat sebelum eksekusi command — command self-service (bio/status/gift/setrole/announce/dll) tetap jalan seperti biasa; command baru yang lupa pasang cek izin sendiri otomatis jatuh ke tier admin-panel, bukan terbuka ke semua orang.
- **Template config dibersihkan** — `ClubKitConfig.luau` template tidak lagi hardcode UserId developer kit sebagai `OwnerUserId` / isi `AdminUserIds`. Fresh install sekarang mulai dari `0` / kosong. **Place yang sudah jalan tidak terpengaruh** — buyer config tidak pernah ditimpa oleh engine sync.
- Perbaikan kecil: `LegacySyncBhms = false` sekarang benar-benar menyembunyikan topbar/GUI dance place-pack BHMS; log fill-forward `ConfigBootstrap` pindah ke `Logger` (tidak lagi `print` di server live); mojibake di `KitProduct.Support.Note` diperbaiki.

## Config changes
Tidak ada key baru. Semua perbaikan di atas berjalan otomatis setelah Update Engine — tidak ada field `ClubKitConfig` yang perlu diisi ulang.

## File buyer — jangan replace
- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## Breaking
Tidak ada. Tiga gate abuse di atas hanya mengetatkan aksi yang **seharusnya** sudah admin/DJ-only (tulis ke pool/playlist bersama); command self-service pemain biasa tidak berubah. Kalau ada staff non-admin yang sebelumnya mengandalkan `resolveOrCreateTrackForAsset` atau sticker global pool tanpa role musicManage/admin, minta owner tambahkan role tersebut di `ClubKitConfig` (lihat `SystemRoles`).

## QA setelah upgrade
- [ ] F9 / KitVersion **2.4.72**
- [ ] Favorites dance + music: ubah favorit, keluar saat DataStore throttle (atau langsung leave), join ulang → tidak hilang
- [ ] Sticker: koleksi lama tidak tertimpa kalau load gagal (simulasikan lewat Studio bila perlu)
- [ ] XP: dapat XP lalu langsung keluar server → tersimpan setelah rejoin
- [ ] Boot dengan `LoadingScreen` dimatikan + satu GUI/remote sengaja dihapus → gameplay tetap masuk, fitur terkait mati dengan warn (bukan macet)
- [ ] Dance panel di emulator HP tanpa wrapper mobile → fallback ke layout desktop, sync tidak mati
- [ ] Sticker/music sebagai pemain non-admin → tulis ke pool/playlist bersama ditolak; koleksi/permintaan pribadi tetap jalan
- [ ] Command Library sebagai pemain biasa → command self-service (bio/status/gift/setrole/dll) tetap normal; command admin-tier tetap ditolak
- [ ] `LegacySyncBhms = false` (default) → topbar/GUI dance BHMS place-pack tidak tampil
