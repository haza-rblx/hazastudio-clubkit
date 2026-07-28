# Changed Files — v2.4.67 → v2.4.68

## Summary
- Fake donation commands + donation aura host Part hide fix
- Breaking: **no**
- Git tag: `v2.4.68`

## Core — replace via source sync (Update Engine)

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.68` |
| `src/.../Shared/Constants/Config.luau` | `CMD_FAKE_CASH` / `CMD_FAKE_ROBUX` + legacy `/test*` → fake |
| `src/.../Shared/Domain/CommandLibraryDomain.luau` | Library entries fakecash/fakerobux + deprecated test* |
| `src/.../Server/Controllers/DonationController.luau` | Parse optional player + amount + message; admin fake handlers |
| `src/.../Server/Services/DonationEffectService.luau` | Hide aura host Parts (ParticleEmitter no longer keeps brick visible) |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Pertahankan — tidak ada field baru |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `KIT_VERSION` `2.4.68` (plugin UI v2 masih WIP — rebuild plugin nanti) |
| `CLUB_KIT_SETUP.md` / `QA_CHECKLIST.md` | Docs/QA pakai `/fakecash` / `/fakerobux` |
| `docs/releases/2.4.68/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.68` |
