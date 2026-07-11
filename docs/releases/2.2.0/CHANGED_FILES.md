# Changed Files — v2.1.0 → v2.2.0

## Summary

- Scope: Gravity feature + music topbar fix + packager plugin restructure
- Breaking: no
- Git tag: `v2.2.0`

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/.../KitProduct.luau` | KitVersion `2.2.0` |
| `src/ReplicatedStorage/.../Constants/Config.luau` | `Config.Gravity`, `GravityEnabled`, music `TOPBAR_ORDER` |
| `src/ReplicatedStorage/.../Config/ConfigBootstrap.luau` | Gravity feature flag map |
| `src/ReplicatedStorage/.../Domain/CommandLibraryDomain.luau` | `/gravity`, `/ungravity` |
| `src/ServerScriptService/.../Services/GravityService.luau` | Added |
| `src/ServerScriptService/.../Controllers/GravityController.luau` | Added |
| `src/ServerScriptService/.../Init/EarlyRemotes.luau` | Gravity remotes |
| `src/ServerScriptService/.../Main.server.luau` | Wire Gravity |
| `src/StarterPlayerScripts/.../Controllers/GravityController.luau` | Added |
| `src/StarterPlayerScripts/.../Controllers/MusicPlayerController.luau` | Topbar re-assert |
| `src/StarterPlayerScripts/.../UI/MusicTopbarIcon.luau` | Robust show/hide |
| `src/StarterPlayerScripts/.../Main.client.luau` | Wire Gravity client |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Opsional: tambah `Features.Gravity = true` |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Pertahankan |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/**` | Plugin source (restructured) |
| `tools/ClubKitPackagerPlugin/plugin-build/**` | Plugin build tree |
| `tools/ClubKitPackagerPlugin/build-plugin-rbxm.ps1` | Added |
| `tools/install-plugin.ps1` | Added |
| `tools/release.ps1` | Manifest path → `plugin/` |
| `docs/releases/2.2.0/**` | Upgrade notes |
| `CHANGELOG.md` / `VERSION` | `2.2.0` |
