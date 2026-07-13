# Changed Files — v2.4.17 → v2.4.18

## Summary

- Icon / MusicTopbar setMenu crash fix
- Breaking: **no**
- Git tag: `v2.4.18`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/UI/MusicTopbarIcon.luau` | Do not re-call `setMenu` in `assertVisible` |
| `src/.../Hazastudio_ClubKit/Icon/Elements/Menu.luau` | Nil-guard before destroy |
| `src/.../Hazastudio_ClubKit/Icon/Elements/Dropdown.luau` | Nil-guard before destroy |
| `src/.../Hazastudio_ClubKit/Icon/init.luau` | Nil-guard childIcon in toggled |
| `src/.../Icon/Elements/Menu.luau` | Mirror nil-guard |
| `src/.../Icon/Elements/Dropdown.luau` | Mirror nil-guard |
| `src/.../Icon/init.luau` | Mirror nil-guard |
| `src/.../KitProduct.luau` | KitVersion `2.4.18` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.18` |
| `docs/releases/2.4.18/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.18` |
