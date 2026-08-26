# Delivery output — v2.9.0

Built from template place **THE BASIC TEST 1.3** (engine synced to v2.9.0 before packing).

| File | Purpose |
|------|---------|
| `HazastudioClubKit_Plugin_v2.9.0.rbxm` | Studio plugin (install once) |
| `HazastudioClubKit_Package_v2.9.0.rbxm` | Full place pack (fresh install) |
| `HazastudioClubKit_SyncBhmsAddon_v2.9.0.rbxm` | Optional BHMS dance pack (106 instances, per-service layout) |

> Existing places only need the plugin + **Update Engine** (source sync) — see `docs/releases/2.9.0/UPGRADE.md`.

## What's new in v2.9.0

- **Three silent-failure fixes** — dead MultiOption settings rows (Graphics "Overall Quality"), `/announce` + paid broadcasts not rendering after a CanvasGroup→Frame redesign, and the vote-skip modal closing after ~1s instead of 15s.
- **AFK auto-rejoin overhaul** — 4-rung escalation ladder (`Config.AfkGuard.REJOIN_LADDER`) replaces the single 17-minute attempt; rate token now opens a cycle, not a request; state resets on `idleTime` regression; a teleport that never happened no longer counts as success.
- **UI image warm-up** (`Config.ImagePreload`) — panel artwork warms during the loading screen, ~0.55s cold → ~0.05s. Plus grouped-list corner rounding on settings/profile rows.
- **ADR 0004 amendment** — unlinked donor nicknames on the cash workspace board display raw; every other filtered surface unchanged.

Full notes: `docs/releases/2.9.0/UPGRADE.md` + `CHANGELOG.md`.

## Buyer install (main)

1. Plugin → **Update plugin** → **Engine → Update Engine** (existing place), **or** Unpack a `HazastudioClubKit_Package_*.rbxm` for a fresh install.
2. Fill `Secrets.luau` + `ClubKitConfig` (Group, shop, donation)
3. Optional: unpack SyncBhms add-on → set `Features.LegacySyncBhms = true`
4. Enable HttpService → Publish → test

Owner intake (fill `ClubKitConfig` later): [`OWNER_ONBOARDING.txt`](OWNER_ONBOARDING.txt)

Docs: [`docs/delivery/TEMPLATE_PLACE.md`](../docs/delivery/TEMPLATE_PLACE.md) · [`docs/delivery/PLUGIN.md`](../docs/delivery/PLUGIN.md)
