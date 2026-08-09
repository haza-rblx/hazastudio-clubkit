# Changed Files — v2.4.75 → v2.4.76

## Summary
- Carry upload UI integrated into Club Kit panel (Tools)
- Command Library Studio NetFail fix
- SociaBuzz donation illustration + docs hub / setup / reference
- Breaking: **no**
- Git tag: `v2.4.76` (vs `v2.4.75`)

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.76` |
| `src/.../Client/Controllers/CommandLibraryController.luau` | **Fix** — pcall `GetRankInGroup`; Guest fallback so topbar still wires |
| `src/.../Shared/Domain/DonationProviderDomain.luau` | SociaBuzz illustration `rbxassetid://113679135532210`, height 160 |

## Buyer-owned — do not replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No schema change; carry upload may patch animation IDs if you run it |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/CarryUploadCore.luau` | **New** — scan / CreateAssetAsync / config patch |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | Tools → Carry animations card |
| `tools/ClubKitPackagerPlugin/plugin/HazastudioClubKit.plugin.luau` | Removed Carry Upload toolbar redirect |
| `tools/ClubKitPackagerPlugin/plugin/UpdaterPanel.luau` | Carry fix tip → Open Panel → Tools |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.4.76` |
| `tools/ClubKitPackagerPlugin/default.project.json` | Includes `CarryUploadCore` |
| `tools/CarryAnimUploaderPlugin/README.md` | Deprecated — use Tools panel |
| `docs/setup.html`, `docs/reference.html`, `docs/index.html`, `docs/updates.html`, `docs/theme.css`, `docs/locales/*` | Setup flow + Reference + visual / voice pass |
| `CHANGELOG.md`, `docs/releases/2.4.76/**` | This release |

## Optional

- **Rebuild / reinstall Studio plugin** required for Carry Tools UI (`build-plugin-rbxm.ps1` or soft Update Plugin after tag is on GitHub)
- StarterGui / Workspace boards: not part of this sync
