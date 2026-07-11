# Changed Files — v2.2.2 → v2.2.3

## Summary

- Scope: Fix Gravity/Ungravity naming + faster restore drop
- Breaking: no (keybind/command semantics corrected)
- Git tag: `v2.2.3`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/Controllers/GravityController.luau` | Shift+U float, Shift+G restore |
| `src/.../Server/Controllers/GravityController.luau` | `/gravity` disable; `/ungravity [n]` float |
| `src/.../Server/Services/GravityService.luau` | Downward kick + Freefall on restore |
| `src/.../Shared/Constants/Config.luau` | Messages + RESTORE_DOWNWARD_VELOCITY |
| `src/.../Shared/Domain/CommandLibraryDomain.luau` | Command descriptions |
| `src/.../KitProduct.luau` | KitVersion `2.2.3` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.3` |
| `docs/releases/2.2.3/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.3` |
