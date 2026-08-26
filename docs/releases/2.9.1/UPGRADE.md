# Upgrade v2.9.0 → v2.9.1

Small fix + polish release: a packager syntax bug fixed, a new on/off switch for the panel-open camera zoom effect (defaults **off** — this is a visible change if your place currently shows it), and an optional SyncBhms add-on update (Lead Dance topbar). No buyer config schema changes.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (they are never replaced by Update Engine).
2. In Studio: Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine** → Save place.
3. If you use the **SyncBhms add-on**, re-unpack it (or manually add the two new bridge files — see below) to get the restored Lead Dance topbar icon.
4. Done — no new buyer config fields to review this release.

## What's fixed
- **Packager could ship a `ClubKitConfig` that fails to compile.** The blank-template generator (used when packing a fresh install) could double-annotate the `AdminUserIds` field (`{} :: T :: T`), a Luau syntax error — every fresh install built from an affected pack would load a dead config module. Seller-side tooling fix only; does not affect already-installed places.

## What's new
- **`Config.PanelZoom` on/off switch** for the small camera zoom-in effect that plays when a modal panel opens (Shop, Gift, Admin Panel, Admin Hub, Music Player, Couple, Donation, Avatar profile card, Top Menu, Paid Broadcast, Join Community prompt). **Defaults to `false` (off)** — previously this was always on with no way to disable, unlike the sibling blur effect (`Config.PanelBlur.ENABLED`). If you want to keep the zoom, set `Config.PanelZoom.ENABLED = true` in `Shared/Constants/Config.luau` after updating (this is an engine constants file, not `ClubKitConfig` — same place `Config.PanelBlur` lives).
- **SyncBhms add-on: Lead Dance topbar restored** (optional — only relevant if `Features.LegacySyncBhms = true`). Two new bridge scripts let the topbar "Lead Dance" icon work under BHMS instead of Club Kit's own (disabled) dance panel, and the dropdown now shows real active followers (mirrored from BHMS's own follower graph) instead of just everyone with the `LeadDance` role. See `extras/place-packs/SyncBhms/README.md` for install steps.

## Config changes
- New `Config.PanelZoom = { ENABLED = false }` in `Shared/Constants/Config.luau` (engine file, see above).

## QA after upgrade
- Open any modal panel (Shop, Settings, Admin Panel, etc.) — confirm there's no more small camera zoom-in on open/close. If you re-enabled `Config.PanelZoom.ENABLED`, confirm the zoom is back.
- Fresh-install a place from a newly-exported pack → confirm `ClubKitConfig` loads without a script error (Output should be clean, not `AdminUserIds` compile errors).
- If using SyncBhms: confirm the topbar "Lead Dance" icon appears and its dropdown lists only players with an active follower or the `LeadDance` role.
