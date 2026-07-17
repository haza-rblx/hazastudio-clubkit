# Changed Files — v2.4.49 → v2.4.50

## Summary

- 4 engine files + version bump + docs
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | INTRO_MIN_DURATION 5; ChatBubble HEIGHT 0.25, NUDGE, TUNE_COMMAND |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/UI/LoadingScreenUI.luau` | Intro min hold respected on finish |
| `src/StarterPlayerScripts/.../Client/Services/ChatBubbleAdornee.luau` | Overrides + `/height` `/bh` `/bubbleheight` |
| `src/StarterPlayerScripts/.../Client/Controllers/ChatTagsController.luau` | bindTuneCommands |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.50 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.50 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.50 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.50 |
| `CHANGELOG.md` | Section 2.4.50 |
| `docs/releases/2.4.50/` | UPGRADE.md + CHANGED_FILES.md |
| `UPGRADE_PROGRESS.md` | Reset |
