# Changed Files — v2.4.61 → v2.4.62

## Summary
- 4 core engine files + version/docs
- Breaking: no (behavior change on name-tag privacy toggles)

## Core — replace via Update Engine
| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | Public-only layer/badge gate; donation chips respect TopSpender/TopDonate |
| `src/StarterPlayerScripts/.../Client/UI/MenuSettingsCore.luau` | Privacy subtitles; remove misleading localOnly on privacy toggles |
| `src/StarterPlayerScripts/.../Client/Controllers/SettingsController.luau` | Save notif copy |
| `src/ServerScriptService/.../Server/Controllers/SettingsController.luau` | Debounced + diff-before-write public overhead sync |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.62 |

## Buyer-owned — review manual, jangan replace
| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Keep |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Keep |

## Tools / docs only
| Path | Change |
|------|--------|
| `VERSION` | 2.4.62 |
| `CHANGELOG.md` | [2.4.62] |
| `UPGRADE_PROGRESS.md` | Reset |
| `docs/releases/2.4.62/*` | Upgrade notes |
| `tools/ClubKitPackagerPlugin/**/ClubKitManifest*` | KIT_VERSION 2.4.62 |
