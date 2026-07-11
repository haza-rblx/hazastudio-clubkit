# Changed Files — v2.2.7 → v2.2.8

## Summary

- Scope: Donation rank reliability, role color dedupe, music volume 100%, cinematic icon, Carry template anims
- Breaking: no
- Git tag: `v2.2.8`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Server/Services/OverheadService.luau` | Rank fail tidak NIL; clear hanya confirmed |
| `src/.../Server/Controllers/ShopController.luau` | assignRobuxTopDonate limit 100, skip miss, flush dirty |
| `src/.../Server/Repositories/DonationLeaderboardRepository.luau` | `flushDirtyCaches()` |
| `src/.../Server/Services/DonationService.luau` | `getPlayerRobuxRank` |
| `src/.../Client/Controllers/DonationSystemController.luau` | Overhead merge (nil rank keep) |
| `src/.../Client/Services/DonationRobuxService.luau` | Merge comment |
| `src/.../Shared/Domain/RolesDomain.luau` | Auto-remap duplicate team/chat colors |
| `src/.../Shared/Domain/SettingsDomain.luau` | musicVolume 100 + migrate 50→100 |
| `src/.../Shared/Domain/Types.luau` | `_musicVolBase` |
| `src/.../Client/State/MusicPlayerStore.luau` | volume default 1 |
| `src/.../Client/Controllers/SettingsController.luau` | fallback 100 + persist schema |
| `src/.../Shared/Constants/Config.luau` | Camera topbar icon |
| `src/.../KitProduct.luau` | KitVersion `2.2.8` |

## Buyer-owned — review manual, jangan replace via Update Engine

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan place |
| `src/.../Hazastudio_ClubKitConfig/ClubKitConfig.luau` (repo template) | Carry anim IDs updated — paste manual ke Studio jika mau |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.8` |
| `docs/releases/2.2.8/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.8` |
