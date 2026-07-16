# Changed Files — v2.4.46 → v2.4.47

## Summary

- ~20 files changed (engine + config template/schema + docs) + version bump
- Breaking: soft — `Donatur` removed; spender labels/MaxRank changed (top 10)

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.ChatBubble`; RoleTools folder names; spender labels |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | Remove Donatur; MaxRank 10; rename labels |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/Roles.luau` | Drop Donatur; new chat/tool names |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/RoleCategoryBuilder.luau` | No Donatur from spenderRoles |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RolesDomain.luau` | Top role map + MaxRank gate |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadDomain.luau` | Per-currency MaxRank normalize |
| `src/ServerScriptService/.../OverheadService.luau` | Pass spenderType to normalize |
| `src/ServerScriptService/.../RoleToolService.luau` | No DONOR folder; new folder names |
| `src/ServerScriptService/.../JoinGreetingService.luau` | Title strings |
| `src/StarterPlayerScripts/.../ChatTagsController.luau` | AdorneeName + OnBubbleAdded style |
| `src/StarterPlayerScripts/.../Services/ChatBubbleAdornee.luau` | **New** — Attachment offset helper |
| `src/StarterPlayerScripts/.../UI/OverheadUI.luau` | scheduleSync after apply |
| `src/StarterPlayerScripts/.../JoinGreetingController.luau` | Title strings |
| `src/StarterPlayerScripts/.../SettingsController.luau` | Layer labels Top Rupiah / Top Robux |
| `src/StarterPlayerScripts/.../UI/MenuSettingsCore.luau` | Layer labels |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.47 |

## Buyer-owned — review manual, jangan replace utuh

| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template repo updated (MaxRank 10, rename, no Donatur). **Jangan timpa nilai buyer** — merge `SpenderRoles` manual jika place punya custom. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Tools / docs only

| Path | Change |
|------|--------|
| `VERSION` | 2.4.47 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.47 |
| `tools/ClubKitPackagerPlugin/plugin-build/.../ClubKitManifest/init.luau` | KIT_VERSION 2.4.47 |
| `tools/UpdateRoleToolFolders.editmode.luau` | Rename map; archive DONOR |
| `CHANGELOG.md` | Section 2.4.47 |
| `docs/releases/2.4.47/` | UPGRADE.md + CHANGED_FILES.md |
| `UPGRADE_PROGRESS.md` | Reset after release |
