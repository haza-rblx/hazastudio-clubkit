# Changed Files — v2.4.52 → v2.4.53

## Summary

- World donation VFX paced by client notif queue + LocalNuke require fix
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/.../Client/Utils/WorldEffectDispatch.luau` | New BindableEvent for world VFX start |
| `src/.../Client/Controllers/DonationNotificationController.luau` | Fire worldEffect when notif starts |
| `src/.../Client/Effects/EffectDonate/LocalNuke/init.client.luau` | Fix DonationVfxClientGate require; listen WorldEffectDispatch |
| `src/.../Client/Effects/EffectDonate/BlackHole/init.client.luau` | Listen WorldEffectDispatch |
| `src/.../Client/Effects/EffectDonate/Blossom/init.client.luau` | Listen WorldEffectDispatch |
| `src/.../Client/Effects/EffectDonate/GreenHammer/init.client.luau` | Listen WorldEffectDispatch |
| `src/.../Server/Services/DonationService.luau` | Payload.worldEffect from resolveWorldByIdr |
| `src/.../Server/Services/DonationEffectService.luau` | Remove server nuke serial queue; aura only |
| `src/.../Shared/Domain/Types.luau` | DonationNotifPayload.worldEffect |
| `src/.../Shared/Constants/Config.luau` | WORLD_EFFECT_DURATIONS marked legacy |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.53 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah (tidak perlu merge) |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.53 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.53 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.53 |
| `CHANGELOG.md` | Section 2.4.53 |
| `docs/releases/2.4.53/` | UPGRADE.md + CHANGED_FILES.md |
| `UPGRADE_PROGRESS.md` | Reset |
