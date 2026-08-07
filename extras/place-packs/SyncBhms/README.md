# SyncBhms — place-specific pack (not Club Kit engine)

Legacy BHMS dance/sync pack for **one place owner**. Not part of Rojo `default.project.json`, not part of Update Engine, and **not** included in buyer changelog.

When active: Club Kit **does not** run the dance panel / `SyncService` / `SyncRemotes`. The **Sync Dance** button in the Avatar Context Menu (ACM) routes to BHMS `Remotes2.startSync`.

## Folder contents

| Path | Purpose |
|------|---------|
| `SyncBhms.rbxm` | Export of `Workspace.SyncBhms` (Dance / SyncServer / SyncSettings / DanceGui) |
| `bridge/SyncBhmsGate.luau` | Reads `Features.LegacySyncBhms` — pack no-ops when `false` |
| `bridge/SyncBhmsAcmBridge.luau` | ACM module → BHMS (`ReplicatedStorage.SyncBhmsAcmBridge`) |
| `bridge/SyncBhmsRemotes.server.luau` | Provisions `Remotes2` + `StoredAnimations` (gated) |
| `README.md` | This guide |

## Studio setup (place owner)

1. **Config** — in `ClubKitConfig.Features`:
   ```lua
   SyncDance = true,          -- ACM Sync Dance button remains
   LegacySyncBhms = true,     -- enable BHMS pack; disable Club Kit dance panel
   -- LegacySyncBhms = false  → all BHMS scripts no-op (topbar Dance + DanceGui hidden)
   ```
2. Insert **`SyncBhms.rbxm`** (temporarily in Workspace is fine; rearrange as below).
3. Runtime layout (BHMS **does not** run if scripts stay in Workspace):

   | From pack | Move to |
   |-----------|---------|
   | `SyncServer` (+ Modules, Main1 enabled, Main disabled) | `ServerScriptService` |
   | `Dance` LocalScripts (`danceDraging1`, `TopbarDance`, `BeatDanceClient`) | `StarterPlayer.StarterPlayerScripts` |
   | `DanceGui` | `StarterGui` (or clone from client script like legacy BHMS flow) |
   | `SyncSettings` (`danceModule`, `emoteModule`, `syncSettings`) | `ReplicatedStorage.SyncSettings` |

4. Paste bridge files:
   - `SyncBhmsGate.luau` → ModuleScript `ReplicatedStorage.SyncBhmsGate` (**required** — all BHMS scripts check the flag here).
   - `SyncBhmsRemotes.server.luau` → Script in `ServerScriptService` (any name; run before Main1).
   - `SyncBhmsAcmBridge.luau` → ModuleScript `ReplicatedStorage.SyncBhmsAcmBridge`.
5. Ensure **TopbarPlus** `ReplicatedStorage.Icon` exists if `TopbarDance` uses it.
6. At the top of each BHMS script (`TopbarDance`, `danceDraging1`, `BeatDanceClient`, `SyncServer.Main1`, `SyncBhmsRemotes`) add:
   ```lua
   local SyncBhmsGate = require(ReplicatedStorage:WaitForChild("SyncBhmsGate"))
   if not SyncBhmsGate.isEnabled() then
   	return
   end
   ```
7. Playtest: `LegacySyncBhms = true` → ACM Sync Dance + BHMS topbar Dance. `= false` → Club Kit dance / Lead Dance only.

## Mutually exclusive

- `LegacySyncBhms = true` → kit **does not** boot `SyncController` / `DancePanelUIBinder` / server `SyncService`; BHMS pack runs.
- `LegacySyncBhms = false` → BHMS pack **no-ops** via `SyncBhmsGate` (topbar Dance + ★ EMOTE panel hidden); Club Kit dance active.
- Do not run both sync backends on the same place without the gate.

## Maintenance

- This pack is **custom**; BHMS bugs are not universal kit bugs.
- Dance catalog updates = edit `SyncSettings.danceModule` in the place, not `src/`.
- Engine only touches the flag + ACM bridge require hook.
