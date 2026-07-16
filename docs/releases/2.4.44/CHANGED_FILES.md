# Changed Files — v2.4.43 → v2.4.44

## Summary

- Remove predictive local Play on dance click; warm-only + stricter anim_result/toggle
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `Client/Controllers/SyncController.luau` | Drop local Play; click PreloadAsync warm only; stale ack + toggle fixes |
| `KitProduct.luau` | KitVersion 2.4.44 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Tidak perlu diubah |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.44 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest` | KIT_VERSION 2.4.44 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.44 |
| `docs/releases/2.4.44/*` | Upgrade guide |
