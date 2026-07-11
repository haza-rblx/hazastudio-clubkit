# Changed Files — v2.2.9 → v2.3.0

## Summary

- ~35 files changed (engine + docs/tools)
- Breaking: **yes** (Studio DataStore isolation default; gravity scope/permission)
- Git tag: `v2.3.0`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/Utils/WorldEffectFlight.luau` | **New** — VFX single-flight |
| `src/.../EffectDonate/LocalNuke/init.client.luau` | Abort/cleanup prior run |
| `src/.../EffectDonate/Blossom/init.client.luau` | Abort token + cleanup |
| `src/.../EffectDonate/BlackHole/init.client.luau` | Abort + Destroy impactVisuals |
| `src/.../EffectDonate/LocalNuke/Scripts/SpawnFireworks.client.luau` | FIREWORK_COUNT 40 |
| `src/.../Services/DonationEffectService.luau` | WORLD_EFFECT_DURATIONS wait |
| `src/.../Constants/Config.luau` | Isolation default on; effect durations |
| `src/.../Utils/AvatarPrewarmPool.luau` | Generation token / Destroy-on-overwrite |
| `src/.../Utils/UISoundHelper.luau` | Play + Ended/Debris |
| `src/.../Controllers/GenericBroadcastController.luau` | Sound fix |
| `src/.../Controllers/MusicPlayerController.luau` | DJ pad sound fix |
| `src/.../Services/GravityService.luau` | Server-wide float mode |
| `src/.../Controllers/GravityController.luau` (server) | Admin panel permission gate |
| `src/.../Client/Controllers/GravityController.luau` | Keybind gated to admin role |
| `src/.../Main.server.luau` | Gravity wiring; profile loader; DS scope log |
| `src/.../Domain/CommandLibraryDomain.luau` | gravity/ungravity Admin visibility |
| `src/.../Controllers/DonationController.luau` | Defer LB pre-warm |
| `src/.../Repositories/AvatarLikeRepository.luau` | Likes metadata GetAsync cap 20 |
| `src/.../Controllers/SettingsController.luau` | SharedProfileLoader join |
| `src/.../Services/StickerService.luau` | SharedProfileLoader join |
| `src/.../Services/MusicService.luau` | Favorites via loader |
| `src/.../Repositories/MusicFavoritesRepository.luau` | Idempotent onPlayerAdded |
| `src/.../Repositories/FavoritesRepository.luau` | Idempotent onPlayerAdded |
| `src/.../Services/StreakService.luau` | Skip UpdateAsync if alreadyCounted |
| `src/.../Controllers/ShopController.luau` | Receipt dedupe after grant; gift order |
| `src/.../Services/ShopService.luau` | Peek + consumePendingGift |
| `src/.../Repositories/GiftPendingRepository.luau` | peek + consume-after-grant |
| `src/.../Repositories/DonationLeaderboardRepository.luau` | Intent dual-write; community freeze; MS invalidate |
| `src/.../Services/DonationService.luau` | Block manual Robux adjust on live-from-Studio |
| `src/.../Main.client.luau` | enterGameplay on loading miss |
| `src/.../Client/Controllers/OverheadController.luau` | CharacterAdded map cleanup |
| `src/.../Client/Controllers/AvatarContextController.luau` | CharacterAdded cleanup |
| `src/.../KitProduct.luau` | KitVersion `2.3.0` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.3.0` |
| `tools/OneTimeLeaderboardSeeder/...` | Studio isolation default true |
| `docs/releases/2.3.0/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.3.0` |
