# Changed Files — v2.0.0 → v2.1.0

## Summary

- Scope: Source-sync updater plugin + studio tools helpers
- Breaking: Tidak (buyer config/secrets tetap terpisah)
- Git tag: `v2.1.0`

## Core — update via plugin source sync

| Path | Ringkasan |
|------|-----------|
| `src/ReplicatedStorage/.../KitProduct.luau` | KitVersion `2.1.0` |
| `src/ReplicatedStorage/.../RolesDomain.luau` | Membership tool folders in studio list |

## Tools — plugin (Studio only, not in game)

| Path | Ringkasan |
|------|-----------|
| `tools/ClubKitPackagerPlugin/SourceSyncCore.luau` | NEW — GitHub fetch + apply |
| `tools/ClubKitPackagerPlugin/RojoPathMap.luau` | NEW — path mapping |
| `tools/ClubKitPackagerPlugin/DovetailTheme.luau` | NEW |
| `tools/ClubKitPackagerPlugin/DovetailUI.luau` | NEW |
| `tools/ClubKitPackagerPlugin/UpdaterPanel.luau` | NEW |
| `tools/ClubKitPackagerPlugin/PackagerPanel.luau` | NEW |
| `tools/ClubKitPackagerPlugin/init.server.luau` | Refactor |
| `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` | UPDATER config |
| `tools/release.ps1` | NEW |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Pertahankan |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Pertahankan |
