# Delivery output — v2.5.3

Built from template place **THE BASIC TEST 1.3** (engine global-only music; zone mode removed).

| File | Purpose |
|------|---------|
| `HazastudioClubKit_Package_v2.5.3.rbxm` | Main full template (config + blank secrets; no BHMS) |
| `HazastudioClubKit_SyncBhmsAddon_v2.5.3.rbxm` | Optional SyncBhms / BHMS dance add-on |
| `HazastudioClubKit_Plugin_v2.5.3.rbxm` | Studio plugin (install once) |

## Buyer install (main)

1. Plugin → **Unpack RBXM…** → pick `HazastudioClubKit_Package_v2.5.3.rbxm`
2. Fill `Secrets.luau` + `ClubKitConfig` (Group, shop, donation)
3. Optional: unpack SyncBhms add-on → set `Features.LegacySyncBhms = true`
4. Enable HttpService → Publish → test

Owner intake (fill `ClubKitConfig` later): [`OWNER_ONBOARDING.txt`](OWNER_ONBOARDING.txt)

Docs: [`docs/delivery/TEMPLATE_PLACE.md`](../docs/delivery/TEMPLATE_PLACE.md) · [`docs/delivery/PLUGIN.md`](../docs/delivery/PLUGIN.md)
