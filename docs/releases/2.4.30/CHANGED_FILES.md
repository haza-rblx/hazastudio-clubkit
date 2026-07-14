# Changed Files — v2.4.29 → v2.4.30

## Summary
- Studio isolation off + exclude ClubKitShowcase from ship
- Breaking: no (behavioral note for Studio live keys)

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Shared/Constants/Config.luau` | `USE_STUDIO_DATASTORE_ISOLATION = false` |
| `KitProduct.luau` | Version 2.4.30 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.30 + `ENGINE_SOURCE_EXCLUDES` |
| `tools/.../SourceSyncCore.luau` | Honor excludes; destroy Showcase on update |
| `tools/.../PackagerCore.luau` | Strip Showcase from RBXM collect |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/OneTimeLeaderboardSeeder/...` | isolation = false |
| `CHANGELOG.md` / `docs/releases/2.4.30/` | Release notes |
| `VERSION` | 2.4.30 |
