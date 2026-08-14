# Changed Files — v2.5.1 → v2.5.2

## Summary
- Engine + config schema + plugin Carry fix + docs
- Breaking: no

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.5.2` |
| `src/.../Shared/Constants/Config.luau` | Gravity restore soft-brake; AdminHub/JoinCommun scales; `Branding.DISCORD_INVITE` |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Map `Branding.DiscordInvite` |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | Schema default `DiscordInvite` |
| `src/.../Shared/Domain/OverheadDomain.luau` | Coupled → `relationshipMode = Taken` |
| `src/.../Shared/Domain/CoupleDomain.luau` | Couple domain tweak for presentation |
| `src/.../Server/Services/GravityService.luau` | Controlled idle-down drop + soft landing |
| `src/.../Server/Services/LicenseService.luau` | Fail-open / optimistic while verify in flight |
| `src/.../Server/Services/MusicCatalogSeeder.luau` | Grouped `playlists[].tracks` + legacy flat |
| `src/.../Server/Services/OverheadService.luau` | Fingerprint includes couple / relationshipMode |
| `src/.../Server/Controllers/CoupleController.luau` | Flush reliability; Taken retry; chat patch |
| `src/.../Server/Controllers/OverheadController.luau` | Couple clear + presentation patch |
| `src/.../Client/Controllers/TopMenuController.luau` | Discord invite text + open browser |
| `src/.../Client/Controllers/CoupleController.luau` | Optimistic couple chat tag set/clear |
| `src/.../Client/Controllers/ChatTagsController.luau` | lastGood allows nil coupleTag |
| `src/.../Client/Services/ChatTagStore.luau` | `setCoupleTag` |
| `src/.../Client/Services/MobileScaleService.luau` | AdminHub / JoinCommun layout |
| `src/.../Client/Controllers/AdminHubController.luau` | Apply hub layout on init |
| `src/.../Client/Controllers/JoinCommunityPromptController.luau` | Apply join layout on open |
| `src/.../Client/Controllers/MusicPlayerController.luau` | `_loadLibraryData` — playlists then tracks + 1-frame wait |
| `src/.../Client/UI/MusicPlayerUIBinder.luau` | Virtual list rebind when window height was 0 |
| `src/.../Client/UI/MusicPlayerUIBinderPart2.luau` | TrackLength under TrackDetails; clear cover placeholders |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template adds `Branding.DiscordInvite` — set your invite; existing places get key via fill-forward |
| `ReplicatedStorage/Hazastudio_ClubKitConfig/MusicCatalog.luau` | Template prefers grouped `playlists`; keep your library — optional rewrite |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.5.2` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitUI.luau` | Pass button into `onClick` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | Carry upload uses `btn.Text` safely |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.5.2]` section |
| `CLUB_KIT_SETUP.md` | MusicCatalog groups + `DiscordInvite` |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.5.2` |
| `docs/releases/2.5.2/` | This folder |
| `docs/roles-guide.html` | New Roles & Ranks slide guide |
| `docs/index.html` / `docs/updates.html` / locales | Hub version → 2.5.2 + changelog entry |
| `docs/setup.html` / locales | Branding step includes `DiscordInvite` |
| `docs/delivery/TEMPLATE_PLACE.md` / `PLUGIN.md` | Delivery bundle paths for v2.5.2 |
| `deliver/README.md` | Current delivery file list |
