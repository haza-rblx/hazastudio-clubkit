# Hazastudio Club Kit Packager

Roblox Studio plugin to **export** and **unpack** the full Club Kit v1.3 asset set in one click — scripts, GUI, leaderboard boards, tools, donation effects, and WorldEffects.

## Automatically packed

Main template pack (`Create package`) — **SyncBhms excluded** (`DanceGui`, bridge scripts). Workspace **`hazastudioBoard`** folder packed as one unit.

| Service | Contents |
|---------|----------|
| `ReplicatedFirst` | `Hazastudio_ClubKit` |
| `ReplicatedStorage` | `Hazastudio_ClubKit`, `Icon`, `WorldEffects`, optional `Hazastudio_ClubKitConfig` |
| `ServerScriptService` | `Hazastudio_ClubKit`, optional `Hazastudio_ClubKitSecrets` |
| `StarterPlayerScripts` | `Hazastudio_ClubKit` |
| `StarterGui` | GUI `01-` … `15-`, `IconGroup`, `HotbarGUI`, `CommandLibraryGUI`, etc. |
| `ServerStorage` | `Tools`, `DonationEffects`, `DonationSounds` |
| `Workspace` | `hazastudioBoard` folder, Top1–3 posters, `LiveChatDonations`, `RunningText` |

**SyncBhms add-on** (`Create SyncBhms add-on`): BHMS dance place-pack only — ship separately from main template.

Full delivery guide: [`docs/delivery/TEMPLATE_PLACE.md`](../../docs/delivery/TEMPLATE_PLACE.md)

## Install plugin

### Option A — Install `.rbxm` (recommended)

From repo root:

```powershell
.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1
```

Restart Roblox Studio → **Hazastudio Club Kit** toolbar appears on the Plugins tab.

Buyers only need to **install the RBXM once**. After that, update from the panel:
**Settings → Update plugin** (soft-update from GitHub) → **Engine → Update engine**.
The place must have HTTP Requests enabled (same as Update Engine).

### Soft-update plugin (in-app)

The plugin fetches `tools/ClubKitPackagerPlugin/plugin/*.luau` from a public GitHub tag
(`ClubKitManifest.UPDATER`) and remounts via `loadstring` — it does **not** overwrite the
`.rbxm` file in the Plugins folder. Bootstrap (`HazastudioClubKit.plugin.luau`) stays from install.
If bootstrap itself changes significantly, ship a new RBXM (rare).

Required order: **Update plugin first**, then **Update engine**.

### Option B — Copy folder (not sufficient)

Copying the folder alone is **not** enough — Roblox only loads `.rbxm` / `.plugin.luau`, not a plain `init.server.luau` folder. Use Option A.

```bash
rojo serve tools/ClubKitPackagerPlugin/default.project.json
```

Then connect from the Studio Rojo plugin to the Plugins folder.

### Option C — Save as `.rbxm` (buyer distribution)

1. Install the plugin in Studio (Option A).
2. Create an empty place → insert the plugin folder as a temporary model **or** run from the dev Plugins folder.
3. Right-click the plugin folder → **Save to File** → `HazastudioClubKitPackager.rbxm`.
4. Buyer: drag `.rbxm` to `%LOCALAPPDATA%\Roblox\Plugins\`.

## Dev hot-reload (no Studio restart)

Iterate panel UI/code without rebuilding RBXM + restarting:

```powershell
# 1. Once after RBXM changes: rebuild + restart Studio
.\build-plugin-rbxm.ps1

# 2. Run dev server (leave it open)
.\dev-serve.ps1          # serves plugin/*.luau at http://127.0.0.1:8798
```

3. Edit `.luau` files in `plugin/` → save.
4. In Studio: **Hazastudio Club Kit** toolbar → **Reload Panel**
   (or `reload_clubkit_panel()` from the command bar).

The panel is destroyed and rebuilt from the latest source via `HttpService` +
`loadstring`. If the dev server is down, Reload falls back to bundled modules (no error).
**Not** hot-reloaded: `HazastudioClubKit.plugin.luau` (bootstrap) and
new module files that are not yet in the RBXM — those still need rebuild + one restart.

## Usage

### Export (from source / dev kit place)

1. Open a place that has **all** kit assets (Rojo scripts + GUI/board/tools in Studio).
2. **Hazastudio Club Kit** toolbar → **Export RBXM**.
3. Configure options in the **Club Kit Packager** panel (config/secrets).
4. Choose save location → `HazastudioClubKit_v1.3.rbxm`.

### Unpack (target / buyer place)

1. **Hazastudio Club Kit** toolbar → **Unpack RBXM**.
2. Select the exported `.rbxm` file.
3. The plugin places instances in the correct services.
4. Default: does **not** overwrite buyer `ClubKitConfig` and `Secrets` if they already exist.

Alternative: import `.rbxm` manually into Explorer → select package folder → **Unpack Selection**.

## After unpack (buyer)

1. Edit `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig`
2. Edit `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets`
3. Remove `ClubKitShowcase` for live mode (optional)
4. Publish

Full guide: [`CLUB_KIT_SETUP.md`](../../CLUB_KIT_SETUP.md)
