# Changed Files — v2.4.53 → v2.4.54

## Summary

- Fix donation world VFX silently skipped on Graphics Low
- Add dispatch/skip diagnostics
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/.../Client/Utils/DonationVfxClientGate.luau` | Stop gating world FX on Graphics Low / HideAllParticles |
| `src/.../Client/Controllers/DonationNotificationController.luau` | Log dispatch, skip reason, or missing world effect |
| `src/.../Server/Services/DonationService.luau` | Include resolved worldEffect in broadcast log |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.54 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.54 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.54 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.54 |
| `CHANGELOG.md` | Section 2.4.54 |
| `docs/releases/2.4.54/` | Upgrade and changed-files docs |
| `UPGRADE_PROGRESS.md` | Reset |
