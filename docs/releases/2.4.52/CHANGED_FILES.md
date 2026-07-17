# Changed Files — v2.4.51 → v2.4.52

## Summary

- Engine client chat tags + chat bubble adornee + music tab label + version bump + docs
- Dev tool: CarryAnimUploaderPlugin (not engine sync)
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/StarterPlayerScripts/.../Client/Controllers/ChatTagsController.luau` | Source of truth → OverheadController cache + last-known-good (fix Guest flicker) |
| `src/StarterPlayerScripts/.../Client/Services/ChatBubbleAdornee.luau` | Attachment on HumanoidRootPart; head→HRP Y offset |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | ChatBubble.ADORNEE_PART; Music TAB_LABELS.reqSong → Library |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.52 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Tidak berubah (tidak perlu merge) |
| `Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.52 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.52 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.52 |
| `tools/CarryAnimUploaderPlugin/` | Local plugin (upload Carry KFS + patch ClubKitConfig) |
| `CHANGELOG.md` | Section 2.4.52 |
| `docs/releases/2.4.52/` | UPGRADE.md + CHANGED_FILES.md |
| `UPGRADE_PROGRESS.md` | Reset |
