# Changed Files — v2.4.54 → v2.4.55

## Summary

- Fix disconnected client-local world-effect event
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/.../Client/Utils/WorldEffectDispatch.luau` | Reuse the same parentless BindableEvent for connect and fire |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.55 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.55 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.55 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.55 |
| `CHANGELOG.md` | Section 2.4.55 |
| `docs/releases/2.4.55/` | Upgrade and changed-files docs |
| `UPGRADE_PROGRESS.md` | Reset |
