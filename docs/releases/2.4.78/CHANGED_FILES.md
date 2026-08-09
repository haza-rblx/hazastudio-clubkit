# Changed Files — v2.4.77 → v2.4.78

## Summary
- 10 files changed
- Breaking: no (gate rename; legacy alias kept)

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | `Features.WutwutDance = false` default + `FEATURE_MANIFEST` entry ("Music & dance"); removed 2.4.77 `Sync.WutwutEnabled` default |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | `Features.WutwutDance` → `Config.Sync.WUTWUT_ENABLED`; legacy `Sync.WutwutEnabled=true` still forces on |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | Gate comment references `Features.WutwutDance` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.4.78 |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Fill-forward adds `Features.WutwutDance = false`. Jika sempat set `Sync.WutwutEnabled = true` (2.4.77), pindahkan ke `Features.WutwutDance = true` (alias lama tetap bekerja). |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.4.78 |
| `tools/ClubKitPackagerPlugin/plugin/ConfigSchemaCore.luau` | Fallback manifest: `WutwutDance` entry |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.4.78]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | 2.4.78 |
