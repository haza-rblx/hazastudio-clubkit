# Changed Files — v2.6.1 → v2.6.2

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 8 |
| Breaking | no |

All engine changes ship via **Update Engine (source sync)**. No RBXM needed. No buyer config changes.

## Core — replace via Update Engine

| Path | Type | Summary |
|------|------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | mod | `KitVersion` → 2.6.2 |
| `src/ReplicatedStorage/.../Shared/Session/RejoinMode.luau` | NEW | reads + caches `afkRejoin` flag from teleport data (dual-source: `GetJoinData().TeleportData` + `GetLocalPlayerTeleportData()`) |
| `src/ReplicatedFirst/.../LoadingBootstrap.client.luau` | mod | skip loading screen entirely on AFK rejoin (`WaitForChild` for Session/RejoinMode — replication-race safe) |
| `src/StarterPlayerScripts/.../Client/Controllers/JoinCommunityPromptController.luau` | mod | `tryPromptAfterGameplay` returns early on AFK rejoin |
| `src/StarterPlayerScripts/.../Main.client.luau` | mod | read rejoin flag; bypass music-engine delay + force dance warmup on rejoin |
| `src/ServerScriptService/.../Server/Services/SyncService.luau` | mod | solo dancers try top leader on rejoin; extracted shared `trySyncTopLeader` helper |

## Tools / docs only

| Path | Summary |
|------|---------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.6.2 |
| `tools/ClubKitPackagerPlugin/dev-serve.ps1` | add `/repo/<path>` route (serve repo files for test injection) |
| `VERSION` | 2.6.2 |
| `CHANGELOG.md` | `[Unreleased]` → `[2.6.2]` |
| `UPGRADE_PROGRESS.md` | unreleased table reset |
| `docs/releases/2.6.2/` | this release folder |
