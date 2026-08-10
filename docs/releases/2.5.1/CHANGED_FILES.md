# Changed Files — v2.5.0 → v2.5.1

## Summary
- 3 files changed (plugin + version/docs only)
- Breaking: no

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` | `blankTemplateSecretsSource` — blanks `Secrets.<Field> = "..."` before packaging; `collect()` clones + blanks `Hazastudio_ClubKitSecrets` when `includeSecrets = true` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | New "Include blank secrets" switch (default on) next to "Include blank config"; `Create package` passes `includeSecrets = includeBlankSecrets` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.5.1` |

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.5.1` |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.5.1]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.5.1` |
| `docs/releases/2.5.1/` | This folder |
