# ServerStorage

## Tools/

Empty folder per role/membership.

### Studio — Command Bar

**Option A — one line (no plugin, always works):**

```lua
require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Studio.GenerateRoleToolsFolder).run()
```

**Option B — `generate_tools_folder()` (requires plugin):**

Install `tools/ClubKitStudioTools/` to `%LOCALAPPDATA%\Roblox\Plugins\` then restart Studio.  
Or use the **Gen Tools** toolbar in the Club Kit Packager plugin.

After the plugin is active:

```lua
generate_tools_folder()
```

Folders follow `ClubKitConfig` + membership (`VIP`, `VVIP`, `SUPREME`). Empty — add Tools manually.

### Alternative: PowerShell (Rojo filesystem)

```powershell
powershell -File tools/GenerateRoleToolFolders.ps1
```

### Legacy paste script

`tools/EnsureRoleToolFolders.editmode.luau` — paste into Command Bar (calls the module above).
