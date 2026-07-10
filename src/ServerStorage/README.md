# ServerStorage

## Tools/

Folder kosong per role/membership.

### Studio — Command Bar

**Opsi A — satu baris (tanpa plugin, selalu jalan):**

```lua
require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Studio.GenerateRoleToolsFolder).run()
```

**Opsi B — `generate_tools_folder()` (butuh plugin):**

Install `tools/ClubKitStudioTools/` ke `%LOCALAPPDATA%\Roblox\Plugins\` lalu restart Studio.  
Atau pakai toolbar **Gen Tools** di plugin Club Kit Packager.

Setelah plugin aktif:

```lua
generate_tools_folder()
```

Folder mengikuti `ClubKitConfig` + membership (`VIP`, `VVIP`, `SUPREME`). Kosong — isi Tool manual.

### Alternatif: PowerShell (Rojo filesystem)

```powershell
powershell -File tools/GenerateRoleToolFolders.ps1
```

### Legacy paste script

`tools/EnsureRoleToolFolders.editmode.luau` — paste ke Command Bar (memanggil module di atas).

