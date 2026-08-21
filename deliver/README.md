# Delivery output — v2.8.0

Built from template place **THE BASIC TEST 1.3**.

| File | Purpose |
|------|---------|
| `HazastudioClubKit_Plugin_v2.8.0.rbxm` | Studio plugin (install once) |
| `HazastudioClubKit_Package_v2.8.0.rbxm` | Full place pack (fresh install; includes AvatarContextMenu v1 + v2 GUIs) |

> Existing places only need the plugin + **Update Engine** (source sync) — see `docs/releases/2.8.0/UPGRADE.md`. The `AvatarContextMenuV2` ScreenGui is a place asset, so to use `Features.AvatarContextMenuV2 = true` on an existing place, add the v2 GUI from this package to StarterGui.

## What's new in v2.8.0

- **Avatar Context Menu v2 (`Features.AvatarContextMenuV2`)** — pick legacy v1 (3D rotating avatar) or redesign v2 (full-body profile picture + camera zoom/blur backdrop). Default v1; v2 needs the `AvatarContextMenuV2` GUI in StarterGui.
- **Camera zoom + blur backdrop (v2)** — panel open zooms FOV in + frosted blur, restored on close (same as TopMenu/Settings/Music).
- **Background blur enabled globally** (`Config.PanelBlur.ENABLED = true`) — all shared-backdrop modals now blur by default.
- **Fixes** — double avatar in the 3D viewport (v1); avatar/profile pic hidden for negative Studio test userIds.

Full notes: `docs/releases/2.8.0/UPGRADE.md` + `CHANGELOG.md`.

## Buyer install (main)

1. Plugin → **Update plugin** → **Engine → Update Engine** (existing place), **or** Unpack a `HazastudioClubKit_Package_*.rbxm` for a fresh install.
2. Fill `Secrets.luau` + `ClubKitConfig` (Group, shop, donation)
3. Optional: unpack SyncBhms add-on → set `Features.LegacySyncBhms = true`
4. Enable HttpService → Publish → test

Owner intake (fill `ClubKitConfig` later): [`OWNER_ONBOARDING.txt`](OWNER_ONBOARDING.txt)

Docs: [`docs/delivery/TEMPLATE_PLACE.md`](../docs/delivery/TEMPLATE_PLACE.md) · [`docs/delivery/PLUGIN.md`](../docs/delivery/PLUGIN.md)
