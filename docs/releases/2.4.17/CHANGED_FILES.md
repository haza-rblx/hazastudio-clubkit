# Changed Files — v2.4.16 → v2.4.17

## Summary

- 12+ source/docs files for music Load Track, topbar Inter/Menu label, VIP join recovery, overhead respawn
- Breaking: **no** (music open UX: one extra click)
- Git tag: `v2.4.17`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/UI/MusicTopbarIcon.luau` | Horizontal `setMenu`: Music Player + Load Track |
| `src/.../Client/Controllers/MusicPlayerController.luau` | Menu wiring; harden `resyncPlayback`; volume toast; fade volume assert |
| `src/.../Main.client.luau` | Inter font; music menu children; Menu label; MobilePanel on Open Player |
| `src/.../Client/Controllers/TopMenuController.luau` | Keep Deselected **Menu** label; Selected **X** uses Inter |
| `src/.../Shared/Constants/Config.luau` | Font asset, music menu labels, reload toasts, VIP rate |
| `src/.../Server/Services/CommunityVipService.luau` | Longer IsInGroup wait + recovery grants |
| `src/.../Server/Main.server.luau` | Inject overhead into CommunityVipService |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Delayed CommunityVipRecheck retries |
| `src/.../Server/Controllers/OverheadController.luau` | No raw template enable on respawn; subject in recipients |
| `src/.../Client/Controllers/OverheadController.luau` | Re-seed pending on CharacterAdded |
| `src/.../KitProduct.luau` | KitVersion `2.4.17` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan — no required merge |
| `Secrets` | Pertahankan — no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.17` |
| `docs/releases/2.4.17/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.17` |
