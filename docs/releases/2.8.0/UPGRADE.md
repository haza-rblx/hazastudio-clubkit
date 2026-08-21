# Upgrade v2.7.1 → v2.8.0

Avatar Context Menu v2 redesign (buyer-toggleable) + camera zoom/blur backdrop. No breaking changes — everything defaults to current behavior.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (they are never replaced by Update Engine).
2. In Studio: Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine** → Save place.
3. Done — Update Engine fill-forwards the new `Features.AvatarContextMenuV2` (default `false`) into buyer config.

## What's new
- **Avatar Context Menu v2 (`Features.AvatarContextMenuV2`).** Pick your avatar context menu design:
  - `false` (default) = **legacy v1** — 3D rotating avatar `ViewportFrame` (GUI `AvatarContextMenu`). Existing places unchanged.
  - `true` = **redesign v2** — static full-body profile picture (GUI `AvatarContextMenuV2`) with a camera zoom + background-blur backdrop on open.
  - Also in the plugin Config Features panel as "Avatar context menu v2 (redesign)". The panel picks the GUI by the flag, disables the other variant, and falls back to whichever ACM GUI your place has.
  - **Note for existing places:** the v2 ScreenGui is a place asset, not synced by Update Engine. To use v2, add the `AvatarContextMenuV2` GUI to StarterGui (from the rebuilt `HazastudioClubKit_Package` or your template), then set the flag to `true`.
- **Camera zoom + blur backdrop (v2).** Opening the v2 panel zooms the camera in and fades in a frosted blur behind the panel, restored on close (same language as TopMenu/Settings/Music).
- **Background blur enabled globally (`Config.PanelBlur.ENABLED = true`).** The shared frosted backdrop on shop/gift/couple/donation/admin/music/top-menu modals is now on by default. Buyers can opt out per-place via `ClientSettings.BackgroundBlur`.

## What's fixed
- **Double avatar in the 3D viewport (v1).** A leftover `WorldModel` could stack a duplicate avatar in the viewport; the loader now clears every `WorldModel` before rendering. 
- **Avatar/profile picture hidden for Studio test players.** Negative test userIds (`-1`, `-2`, …) were treated as "no target"; now they render correctly.

## Config changes
- New optional flag `ClubKitConfig.Features.AvatarContextMenuV2` (boolean, default `false`). Fill-forwarded automatically; existing buyer configs keep working.
- `Config.PanelBlur.ENABLED` default is now `true` (was `false`) — global backdrop blur for panels that use the shared frosted backdrop.

## QA after upgrade
- Default: open the avatar context menu → 3D rotating avatar (v1), no zoom/blur.
- Set `Features.AvatarContextMenuV2 = true` (+ have the v2 GUI) → panel shows the profile picture, camera zooms in, background blurs; closing restores both.
- Any frosted-backdrop modal (shop/gift/music/etc.) now blurs the background on open.
