# Delivery output — v2.6.2

Built from template place **THE BASIC TEST 1.3**.

| File | Purpose |
|------|---------|
| `HazastudioClubKit_Plugin_v2.6.2.rbxm` | Studio plugin (install once) |

> **Package / SyncBhms RBXM** (`HazastudioClubKit_Package_*`, `HazastudioClubKit_SyncBhmsAddon_*`) are not rebuilt for v2.6.2 yet — engine updates ship via **Update Engine** (source sync), so an existing template only needs the plugin + Update Engine. Rebuild the place pack only for a fresh-install delivery, from a **duplicate** place (see `docs/delivery/TEMPLATE_PLACE.md` Step 0).

## What's new in v2.6.x

- **v2.6.2 — Seamless AFK rejoin**: rejoin lands with no loading screen, no Join Community prompt, and music/dance resume instantly. Solo dancers auto-sync to the top leader on rejoin. (Note: Roblox's native 20-min idle kick is client-side and is **not** prevented — this restores position + dance sync, it is not an AFK-kick bypass.)
- **v2.6.1 — AFK rejoin latch fix**: auto-rejoin no longer works only once; plus Packager `_G.clubkit_update_engine` automation hook.
- **v2.6.0 — External Admin Bridge** (Adonis/Kohl's), `Announcement.MinMembership` gate, workspace boards top 50, AFK rejoin + DJ crackle fixes.

## Buyer install (main)

1. Plugin → **Update plugin** → **Engine → Update Engine** (existing place), **or** Unpack a `HazastudioClubKit_Package_*.rbxm` for a fresh install.
2. Fill `Secrets.luau` + `ClubKitConfig` (Group, shop, donation)
3. Optional: unpack SyncBhms add-on → set `Features.LegacySyncBhms = true`
4. Enable HttpService → Publish → test

Owner intake (fill `ClubKitConfig` later): [`OWNER_ONBOARDING.txt`](OWNER_ONBOARDING.txt)

Docs: [`docs/delivery/TEMPLATE_PLACE.md`](../docs/delivery/TEMPLATE_PLACE.md) · [`docs/delivery/PLUGIN.md`](../docs/delivery/PLUGIN.md)
