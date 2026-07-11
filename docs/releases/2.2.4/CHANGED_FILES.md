# Changed Files — v2.2.3 → v2.2.4

## Summary

- Scope: favorites 32KB + donation burst/queue + Studio `me` clear
- Breaking: no
- Git tag: `v2.2.4`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Constants/Config.luau` | Favorites 32KB; FAVORITES_UPDATE 15/5s; notif backlog scale |
| `src/.../Shared/Utils/Validator.luau` | favoritesUpdate pakai Favorites.MAX_PAYLOAD_BYTES |
| `src/.../Shared/Domain/CommandLibraryDomain.luau` | Docs `me` Studio clear |
| `src/.../Server/Controllers/SyncController.luau` | Reject merged favorites > max |
| `src/.../Server/Controllers/DonationController.luau` | `me`/`@me` Studio-only self-clear |
| `src/.../Server/Services/BackgroundJobScheduler.luau` | `setInterval` pull-earlier |
| `src/.../Server/Services/DonationService.luau` | Burst poll; refreshAll force-only; rank cache invalidate |
| `src/.../Server/Main.server.luau` | Pass scheduler into DonationService |
| `src/.../Client/Controllers/DonationNotificationController.luau` | Backlog scale + lowest-amount eviction |
| `src/.../KitProduct.luau` | KitVersion `2.2.4` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.4` |
| `CLUB_KIT_SETUP.md` | Document Studio `me` clear |
| `docs/releases/2.2.4/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.4` |
