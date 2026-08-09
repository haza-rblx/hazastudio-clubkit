# Delivery output

## Template place (Workspace models)

- `HazastudioClubKit_Package` — main full template (full service clone, no BHMS)
- `HazastudioClubKit_SyncBhmsAddon` — optional SyncBhms / BHMS dance add-on

See [`docs/delivery/TEMPLATE_PLACE.md`](../docs/delivery/TEMPLATE_PLACE.md).

## Studio plugin (RBXM)

- `HazastudioClubKit_Plugin_vX.Y.Z.rbxm` — buyer installs once into `%LOCALAPPDATA%\Roblox\Plugins\`

Build:

```powershell
.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1 -CopyToDeliver
```

See [`docs/delivery/PLUGIN.md`](../docs/delivery/PLUGIN.md).
