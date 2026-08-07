# SyncBhms — place-specific pack (bukan engine Club Kit)

Pack dance/sync BHMS legacy untuk **satu owner place**. Tidak ikut Rojo `default.project.json`, tidak ikut Update Engine, dan **tidak** masuk changelog buyer.

Ketika aktif: Club Kit **tidak** menjalankan dance panel / `SyncService` / `SyncRemotes`. Tombol **Sync Dance** di Avatar Context Menu (ACM) diarahkan ke `Remotes2.startSync` BHMS.

## Isi folder

| Path | Fungsi |
|------|--------|
| `SyncBhms.rbxm` | Export `Workspace.SyncBhms` (Dance / SyncServer / SyncSettings / DanceGui) |
| `bridge/SyncBhmsAcmBridge.luau` | Module ACM → BHMS (`ReplicatedStorage.SyncBhmsAcmBridge`) |
| `bridge/SyncBhmsRemotes.server.luau` | Provision `Remotes2` + `StoredAnimations` |
| `README.md` | Panduan ini |

## Setup di Studio (place owner)

1. **Config** — di `ClubKitConfig.Features`:
   ```lua
   SyncDance = true,          -- ACM Sync Dance button tetap ada
   LegacySyncBhms = true,     -- matikan engine sync + dance panel Club Kit
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
   - `SyncBhmsRemotes.server.luau` → Script di `ServerScriptService` (nama bebas, jalan lebih awal dari Main1).
   - `SyncBhmsAcmBridge.luau` → ModuleScript `ReplicatedStorage.SyncBhmsAcmBridge`.
5. Pastikan **TopbarPlus** `ReplicatedStorage.Icon` ada jika `TopbarDance` memakainya.
6. Playtest: buka ACM → Sync Dance → attribute `Syncing` + anim follower ikut BHMS. Dance panel Club Kit tidak boleh tampil/bind.

## Mutually exclusive

- `LegacySyncBhms = true` → kit **tidak** boot `SyncController` / `DancePanelUIBinder` / server `SyncService`.
- Jangan biarkan kedua backend sync hidup di place yang sama.

## Maintenance

- Pack ini **custom**; bug BHMS bukan bug kit universal.
- Update catalog dance = edit `SyncSettings.danceModule` di place, bukan `src/`.
- Engine hanya menyentuh flag + hook ACM require bridge.
