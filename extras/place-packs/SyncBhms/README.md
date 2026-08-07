# SyncBhms — place-specific pack (bukan engine Club Kit)

Pack dance/sync BHMS legacy untuk **satu owner place**. Tidak ikut Rojo `default.project.json`, tidak ikut Update Engine, dan **tidak** masuk changelog buyer.

Ketika aktif: Club Kit **tidak** menjalankan dance panel / `SyncService` / `SyncRemotes`. Tombol **Sync Dance** di Avatar Context Menu (ACM) diarahkan ke `Remotes2.startSync` BHMS.

## Isi folder

| Path | Fungsi |
|------|--------|
| `SyncBhms.rbxm` | Export `Workspace.SyncBhms` (Dance / SyncServer / SyncSettings / DanceGui) |
| `bridge/SyncBhmsGate.luau` | Baca `Features.LegacySyncBhms` — pack no-op saat `false` |
| `bridge/SyncBhmsAcmBridge.luau` | Module ACM → BHMS (`ReplicatedStorage.SyncBhmsAcmBridge`) |
| `bridge/SyncBhmsRemotes.server.luau` | Provision `Remotes2` + `StoredAnimations` (gated) |
| `README.md` | Panduan ini |

## Setup di Studio (place owner)

1. **Config** — di `ClubKitConfig.Features`:
   ```lua
   SyncDance = true,          -- ACM Sync Dance button tetap ada
   LegacySyncBhms = true,     -- nyalakan pack BHMS; matikan dance panel Club Kit
   -- LegacySyncBhms = false  → semua script BHMS no-op (topbar Dance + DanceGui hilang)
   ```
2. Insert **`SyncBhms.rbxm`** (sementara boleh di Workspace, lalu susun ulang seperti di bawah).
3. Layout runtime (BHMS **tidak** jalan jika script tetap di Workspace):

   | Dari pack | Pindahkan ke |
   |-----------|----------------|
   | `SyncServer` (+ Modules, Main1 enabled, Main disabled) | `ServerScriptService` |
   | `Dance` LocalScripts (`danceDraging1`, `TopbarDance`, `BeatDanceClient`) | `StarterPlayer.StarterPlayerScripts` |
   | `DanceGui` | `StarterGui` (atau di-clone oleh client script seperti flow BHMS lama) |
   | `SyncSettings` (`danceModule`, `emoteModule`, `syncSettings`) | `ReplicatedStorage.SyncSettings` |

4. Paste bridge:
   - `SyncBhmsGate.luau` → ModuleScript `ReplicatedStorage.SyncBhmsGate` (**wajib** — semua script BHMS cek flag di sini).
   - `SyncBhmsRemotes.server.luau` → Script di `ServerScriptService` (nama bebas, jalan lebih awal dari Main1).
   - `SyncBhmsAcmBridge.luau` → ModuleScript `ReplicatedStorage.SyncBhmsAcmBridge`.
5. Pastikan **TopbarPlus** `ReplicatedStorage.Icon` ada jika `TopbarDance` memakainya.
6. Di tiap script BHMS (`TopbarDance`, `danceDraging1`, `BeatDanceClient`, `SyncServer.Main1`, `SyncBhmsRemotes`) tambah di paling atas:
   ```lua
   local SyncBhmsGate = require(ReplicatedStorage:WaitForChild("SyncBhmsGate"))
   if not SyncBhmsGate.isEnabled() then
   	return
   end
   ```
7. Playtest: `LegacySyncBhms = true` → ACM Sync Dance + topbar Dance BHMS. `= false` → hanya Club Kit dance / Lead Dance.

## Mutually exclusive

- `LegacySyncBhms = true` → kit **tidak** boot `SyncController` / `DancePanelUIBinder` / server `SyncService`; pack BHMS jalan.
- `LegacySyncBhms = false` → pack BHMS **no-op** via `SyncBhmsGate` (topbar Dance + panel ★ EMOTE tidak muncul); Club Kit dance hidup.
- Jangan biarkan kedua backend sync hidup di place yang sama tanpa gate.

## Maintenance

- Pack ini **custom**; bug BHMS bukan bug kit universal.
- Update catalog dance = edit `SyncSettings.danceModule` di place, bukan `src/`.
- Engine hanya menyentuh flag + hook ACM require bridge.
