# Carry Anim Uploader (deprecated standalone)

**Integrated into the main Club Kit plugin** (Tools → **Carry animations**).

Use **Open Panel → Tools** instead of this separate local plugin.

## Requirements (unchanged)

`AssetService:CreateAssetAsync(..., Enum.AssetType.Animation)` only works from a **local** plugin with the **CreateAssetAsync** Studio beta enabled.

1. Studio → **File → Beta Features** → enable **CreateAssetAsync Lua API**
2. Install / rebuild the Club Kit local plugin (`.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1`)
3. **Open Panel → Tools → Carry animations** → Scan (dry run) → turn Dry run off → Upload + patch

## Naming convention

| Instance name | Maps to |
|---------------|---------|
| `Hug 1` / `Hug1` | `Hug.carrier` |
| `Hug 2` / `Hug2` | `Hug.carried` |
| `Fireman1` / `Fireman 1` | `Fireman.carrier` |
| `Tandem2` | `Tandem.carried` |

Known styles: `Piggyback`, `Bridal`, `Hug`, `Tandem`, `Fireman`, `Choke`.

Built-in alias: `Pasakal` → `Choke` (edit `STYLE_ALIASES` in `CarryUploadCore.luau` if needed).

Optional Attributes on a KeyframeSequence:

- `CarryStyle` = `"Hug"`
- `CarryRole` = `"carrier"` | `"carried"`

## Safety

- Source KeyframeSequences are not destroyed
- Each successful upload sets Attribute `UploadedAnimationId`
- Always scan (dry-run) first

## Legacy install (standalone)

Only if you still need the old floating widget:

```
%LOCALAPPDATA%\Roblox\Plugins\CarryAnimUploaderPlugin\init.server.luau
```

Prefer the integrated Tools panel.
