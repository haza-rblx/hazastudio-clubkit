# Changed Files — v2.4.79 → v2.4.80

## Summary
- 5 core/template files + version/docs
- Breaking: no

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/UI/DancePanelUIBinder.luau` | Wutwut: soft ~30% gray press tint + fade; no sticky/full white played |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `SWITCH_FADE_*` + `SWITCH_INPUT_COOLDOWN` 0.55 → 0.45 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | Sync SwitchFade* / SwitchInputCooldown defaults 0.45 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.4.80 |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template defaults SwitchFade* / cooldown → 0.45 (repo template only). Place values not auto-replaced — set to 0.45 manually if desired. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.4.80 |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.4.80]` section |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | 2.4.80 |
| `docs/releases/2.4.80/` | This folder |
