# Changed Files — v2.4.71 → v2.4.72

## Summary
- Audit-driven patch: DataStore data-loss fixes, client boot hardening, dance/hotbar client fixes, 3 abuse-gate closures, template/log cleanup
- Breaking: **no** (gates only tighten actions that were already meant to be admin/DJ-only)
- Git tag: `v2.4.72` (vs `v2.4.71` @ `99e5902`)
- 26 files changed (25 modified + 1 new)

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.72`, BuildId `20260808`, mojibake fix in `Support.Note` |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Fill-forward summary → `Logger:info` instead of unconditional `print` |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | `LegacySyncBhms` flag comment (carried from pre-release fix) |
| `src/.../Shared/Constants/Config.luau` | `LegacySyncBhms` internal default (carried from pre-release fix) |
| `src/.../Server/Repositories/FavoritesRepository.luau` | `_pendingFlush` retry pattern — no more data loss when leave-time save fails |
| `src/.../Server/Repositories/MusicFavoritesRepository.luau` | Same `_pendingFlush` retry pattern |
| `src/.../Server/Repositories/StickerRepository.luau` | `load()` returns `Err` on failure instead of seeding an empty default collection |
| `src/.../Server/Services/StickerService.luau` | `_loadedByUserId` gate rejects `addSticker`/updates until load succeeds; global pool write gated to admin/Studio |
| `src/.../Server/Services/LevelService.luau` | New `flushAllPending()` retry path for XP that failed to flush for a player who already left |
| `src/.../Server/Services/MusicService.luau` | `resolveOrCreateTrackForAsset` now gated by `isManageAllowed` (admin/DJ) |
| `src/.../Server/Controllers/CommandLibraryController.luau` | **NEW** central permission gate (`OPEN_ALIASES` allowlist + `canUseAdminPanel` fallback) before `service:execute` |
| `src/.../Server/Main.server.luau` | `levelService:flushPlayer` wired into `Players.PlayerRemoving` + pending retry; `overheadService` passed into `CommandLibraryController` |
| `src/StarterPlayerScripts/.../Main.client.luau` | Boot timeouts on `Shared`/`Constants`/`Domain`/`UI`/`Utils` folder waits + 2 synchronous remote waits |
| `src/.../Client/Controllers/CoupleController.luau` | Boot timeout + soft-disable on remote waits |
| `src/.../Client/Controllers/SettingsController.luau` | Boot timeout + soft-disable on remote waits |
| `src/.../Client/Controllers/AvatarContextController.luau` | Boot timeout + soft-disable on remote waits |
| `src/.../Client/Controllers/MusicPlayerController.luau` | Client-side "no_permission" message for resolve-asset request |
| `src/.../Client/UI/DancePanelGuiRefs.luau` | Falls back to desktop wrapper (warn) instead of `error()` when the mobile wrapper GUI is missing |
| `src/.../Client/Services/HotbarInventoryService.luau` | Disconnects previous character's `ChildAdded`/`ChildRemoved` listeners before rebinding on respawn |

## Extras (optional place-pack) — carried from the pre-release LegacySyncBhms fix

| Path | Change |
|------|--------|
| `extras/place-packs/SyncBhms/bridge/SyncBhmsGate.luau` | **NEW** — `isEnabled()` reads `Features.LegacySyncBhms` |
| `extras/place-packs/SyncBhms/bridge/SyncBhmsRemotes.server.luau` | Early-return gate when the flag is off |
| `extras/place-packs/SyncBhms/README.md` | Documents the mutual-exclusivity gate + why `ReplicatedStorage.Icon` is kept (TopbarDance pack dependency, not a stray duplicate) |

Place-side script edits (TopbarDance / danceDraging* / BeatDanceClient / SyncServer.Main1) that consume `SyncBhmsGate` live in the Studio place itself, not in this repo — see the README for the pattern if you maintain your own BHMS pack copy.

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template only: dev `OwnerUserId` → `0`, `AdminUserIds` → empty. **Place yang sudah jalan tidak tersentuh** (buyer config never overwritten by engine sync) |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `KIT_VERSION` / `PLUGIN_VERSION` → `2.4.72`; mojibake cleanup in a comment |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.72` |
| `docs/index.html` / `updates.html` / `setup.html` | Version pill/footer → `2.4.72`; new `2.4.72` highlight card + changelog entry |
| `docs/locales/{id,en,ja,es}.js` | Version strings + 9 new keys per locale (`updates.v72.*`, `updates.cat.security`) |
| `docs/releases/2.4.72/**` | This upgrade guide + changed-files list |
