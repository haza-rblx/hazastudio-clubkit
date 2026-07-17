# Carry Anim Uploader (Studio local plugin)

Bulk-upload `KeyframeSequence` clips from `ReplicatedStorage.Carry` and patch `ClubKitConfig.Carry.Styles.*.animations`.

## Why local plugin?

`AssetService:CreateAssetAsync(..., Enum.AssetType.Animation)` only works from a **local** plugin with the **CreateAssetAsync** Studio beta enabled. Creator Store plugins are sandboxed.

## Install

1. Studio → **File → Beta Features** → enable **CreateAssetAsync Lua API**
2. Open this file as a Script in Studio, or copy the folder:

```
%LOCALAPPDATA%\Roblox\Plugins\CarryAnimUploaderPlugin\init.server.luau
```

3. Or: right-click Script → **Save as Local Plugin**
4. Restart Studio → toolbar **Hazastudio Club Kit** → **Carry Upload**

## Naming convention

| Instance name | Maps to |
|---------------|---------|
| `Hug 1` / `Hug1` | `Hug.carrier` |
| `Hug 2` / `Hug2` | `Hug.carried` |
| `Fireman1` / `Fireman 1` | `Fireman.carrier` |
| `Tandem2` | `Tandem.carried` |

Known styles: `Piggyback`, `Bridal`, `Hug`, `Tandem`, `Fireman`, `Choke`.

Built-in alias: `Pasakal` → `Choke` (edit `STYLE_ALIASES` in the plugin if you use other names).

Optional Attributes on a KeyframeSequence (override name parse):

- `CarryStyle` = `"Hug"`
- `CarryRole` = `"carrier"` | `"carried"`

## Usage

1. Put KeyframeSequences under `ReplicatedStorage.Carry` (or select them / their folder)
2. Open **Carry Upload** panel
3. **Scan Carry folder** (dry-run mapping) — check Output log for MISSING pairs
4. Turn **Dry run: OFF**
5. Optional: enter **Group ID** (blank = personal inventory)
6. **Upload + patch config**
7. If Rojo syncs `ClubKitConfig.luau`, copy the printed `animations = { ... }` lines into the repo file (Studio Source patch can be overwritten by sync)

## Safety

- Source KeyframeSequences are not destroyed
- Each successful upload sets Attribute `UploadedAnimationId` on the sequence
- Always scan (dry-run) first

## Troubleshoot

| Error | Fix |
|-------|-----|
| CreateAssetAsync / beta | Enable beta + use **local** plugin, not Toolbox |
| unknown style | Rename clip or add `STYLE_ALIASES` |
| could not find animations block | Style missing in `ClubKitConfig.Carry.Styles` |
| Group lookup failed | Wrong group id / no permission |
