# Changed Files — v2.4.74 → v2.4.75

## Summary
- Hotfix: remove stray `er` after `return createDonationController` in DonationController
- Server boot + loading screen blocked without this fix
- Breaking: **no**
- Git tag: `v2.4.75` (vs `v2.4.74`)

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.75` |
| `src/.../Server/Controllers/DonationController.luau` | **Fix** — delete stray line 1913 `er` (syntax error) |

## Buyer-owned — do not replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | No change |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.4.75` |
| `CHANGELOG.md`, `docs/releases/2.4.75/**` | This release |

## Optional

- Plugin reload optional (manifest version bump only; no plugin logic change in this patch)
