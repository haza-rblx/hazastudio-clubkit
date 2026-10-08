# Place-specific overrides — PARKLAB

Folder ini menyimpan **snapshot / catatan kode yang hanya ada di place PARKLAB** (placeId 80098131973647) dan **tidak** ada di repo engine. Format sama dengan [`places/atas-langit/`](../atas-langit/README.md).

## Aturan main

- **Jangan bulk-push `src/` ke place ini tanpa review folder ini dulu.** PARKLAB itu place-canonical: owner sering membangun/menyesuaikan langsung di Studio (GUI addon, admin panel v3, menu HP), dan sebagian edit engine-nya belum pernah masuk repo.
- Sebelum Update Engine / sync ke PARKLAB: baca **Daftar override aktif** di bawah dan putuskan per baris — port ke repo dulu, set config pengganti, atau terima hilang.
- PARKLAB juga sumber GUI addon untuk delivery pack (`1000-01-CT-ADDON`, `IconGroup.ADDON-FreeTitleEventTrigger`, `99-NotificationCenterV2` — lihat UPGRADE_PROGRESS "2.12.0 delivery pack").

## Log (terbaru dulu)

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
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Main` | [bagian 1 + 3](./Main-client-freetitle-topbar-and-phone-menu.luau) | Ikon topbar Free Title + tunggu payload | Digantikan (`Trigger = "Topbar"`) | **Tambahkan `Trigger = "Topbar"` ke `ClubKitConfig.FreeTitleEvent` PARKLAB**, kalau tidak PARKLAB balik ke kartu overlay. |
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Main` | [bagian 2](./Main-client-freetitle-topbar-and-phone-menu.luau) | Menu "..." HP (Admin / Command Center / Freecam / Auto Dance / Free Title) | **Tidak ada** | Port ke repo dulu, atau owner terima menu HP hilang. |
| `StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Client.UI.MenuShellUI` | — (1 baris: `if true then return end` di `_wireFreeTitleEvent`) | Kartu overlay dimatikan | Digantikan (gate Trigger) | Sama dengan baris pertama (`Trigger = "Topbar"`). |

## Catatan lain

- Engine PARKLAB secara umum di belakang/berbeda dari repo (lihat UPGRADE_PROGRESS "PARKLAB full engine sync — 2026-09-10" dan backlog "PARKLAB's engine is broadly behind the repo"). Hash `Main`/`MenuShellUI`/`Config` PARKLAB ≠ ATAS LANGIT ≠ repo per 2026-10-06, walau ketiganya KitVersion 2.12.0.
- `ServerStorage.1000-01-CT-ADDON_BACKUP_2026-09-09` = backup GUI Custom Title lama milik owner; jangan dihapus tanpa tanya.
