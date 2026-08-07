# Upgrade v2.4.73 → v2.4.74

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. **Reload / reinstall plugin** (Features panel reads schema from engine + new `ConfigSchemaCore` module)
3. Save place
4. QA checklist below

`ClubKitConfig` / `Secrets` are not fully replaced, as usual.

## What's new

- **Plugin Config → Features** — the toggle list is no longer hardcoded in the plugin. It loads from `ClubKitConfigSchema.FEATURE_MANIFEST` after Update Engine.
- **Admin Hub** and **Legacy SyncBhms** now appear in the Features panel (they were in schema/runtime before but missing from plugin UI).

## Config changes

No new keys. Existing `Features.*` keys unchanged — only the **plugin UI manifest** is centralized in the engine schema.

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## Breaking

**No.** Runtime feature flags behave the same; only plugin UI sourcing changed.

## QA after upgrade

- [ ] F9 / KitVersion **2.4.74**
- [ ] Plugin → Config → Features shows **Admin Hub** and **Legacy SyncBhms** toggles
- [ ] Toggle Admin Hub off → save → `Features.AdminHub = false` in config Source
- [ ] Toggle on/off for other features still saves correctly
- [ ] Update Engine on an old tag without schema → plugin still shows Features (embedded fallback list)
