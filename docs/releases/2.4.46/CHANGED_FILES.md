# Changed Files — v2.4.45 → v2.4.46

## Summary

- 8 file berubah (6 engine + 2 docs) + version bump
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/CoupleController.luau` | Force Taken on accept; `flushThenInvalidate` sebelum refresh (accept/breakup/open panel) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/CoupleService.luau` | `breakupBoth`: Err jika tidak coupled / save initiator gagal |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | Wire profileRepository + profileMenuSync ke CoupleController |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/MusicRepository.luau` | `loadAll` non-destructive: keep snapshot lama + Err saat read gagal/incomplete |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicSession.luau` | `onLibraryReloaded` sync-only (tidak prune queue); logging prune delete |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/MusicService.luau` | Log reload gagal lebih jelas (queues untouched) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.46, BuildId 20260717 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Tidak berubah |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.46 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.46 |
| `tools/ClubKitPackagerPlugin/plugin-build/HazastudioClubKit/ClubKitManifest/init.luau` | KIT_VERSION 2.4.46 |
| `CHANGELOG.md` | Section 2.4.46 |
| `docs/releases/2.4.46/` | UPGRADE.md + CHANGED_FILES.md |
