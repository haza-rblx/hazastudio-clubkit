# Changed Files — v2.4.73 → v2.4.74

## Summary
- Plugin Features panel reads from `ClubKitConfigSchema.FEATURE_MANIFEST` (single source of truth)
- Admin Hub + Legacy SyncBhms visible in plugin Config → Features
- Breaking: **no**
- Git tag: `v2.4.74` (vs `v2.4.73`)

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.74` |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | `FEATURE_MANIFEST`, `getFeatureGroups()`, `getFeatureKeys()` |

## Buyer-owned — review manually, do not replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change required |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | No change required |

## Tools / docs — plugin reload required

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ConfigSchemaCore.luau` | **New** — require schema from synced engine; fallback manifest |
| `tools/ClubKitPackagerPlugin/plugin/ConfigEditCore.luau` | Feature keys/groups from `ConfigSchemaCore` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | `renderFeatures` uses manifest; removed hardcoded groups |
| `tools/ClubKitPackagerPlugin/default.project.json` | Register `ConfigSchemaCore` module |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.4.74` |
| `CHANGELOG.md`, `docs/releases/2.4.74/**` | This release |

## Optional / not in engine sync

- Rebuild plugin RBXM: `tools/ClubKitPackagerPlugin/build-plugin-rbxm.ps1`
- `plugin-build/` — sync if you ship nested plugin folder
