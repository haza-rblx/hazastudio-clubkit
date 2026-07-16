# Changed Files — v2.4.44 → v2.4.45

## Summary

- Carry: full Massless + CanCollide false on carried; carrier jump/walk normal; carrier anim Action vs carried Action4
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `Server/Services/CarryService.luau` | Carried Massless+CanCollide; carrier locomotion; anim priorities |
| `Shared/Constants/Config.luau` | Carry PHYSICS comment |
| `KitProduct.luau` | KitVersion 2.4.45 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Tidak perlu diubah |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.45 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest` | KIT_VERSION 2.4.45 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.45 |
| `docs/releases/2.4.45/*` | Upgrade guide |
