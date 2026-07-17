# Changed Files — v2.4.50 → v2.4.51

## Summary

- 1 engine config + version bump + docs
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | ChatBubble.NUDGE_STUDS = -0.5 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.51 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.51 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.51 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.51 |
| `CHANGELOG.md` | Section 2.4.51 |
| `docs/releases/2.4.51/` | UPGRADE.md + CHANGED_FILES.md |
| `UPGRADE_PROGRESS.md` | Reset |
