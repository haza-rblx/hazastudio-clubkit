# Changed Files — v2.6.0 → v2.6.1

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 11 |
| Breaking | no |

All engine changes ship via **Update Engine (source sync)**. No RBXM needed. No buyer config changes.

## Core — replace via Update Engine

| Path | Type | Summary |
|------|------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | mod | `KitVersion` → 2.6.1 |
| `.../Shared/Constants/Config.luau` | mod | `AfkGuard.REMOTE_RESPONSE = "AfkRejoinResponse"` |
| `.../Shared/Domain/AfkGuardDomain.luau` | mod | `RejoinOutcome`/`RejoinResponse` types, `isTransientDenial`, `nextRetryDelaySec` (jittered), `ClientRetryState` docstring fix |
| `.../Shared/Utils/RateLimiter.luau` | mod | `check()` returns `waitSec` as third value on deny (additive) |
| `src/ServerScriptService/.../Server/Services/AfkGuardService.luau` | mod | response remote fires every gate outcome; `handleAfkRejoin` pcalled; in-flight flag cleared on success/error + stale watchdog |
| `src/ServerScriptService/.../Server/Services/SessionCommandService.luau` | mod | `CharacterAdded` also restores `pendingAfkSyncRestore` on native respawn |
| `src/StarterPlayerScripts/.../Client/Controllers/AfkGuardController.luau` | mod | consume response remote, schedule retry from server hint, re-arm attempts on allowed/failed, `afk_idle_after_rejoin` probe |
| `src/ServerScriptService/.../Server/Main.server.luau` | mod | `ensureRemoteEvent(AfkRejoinResponse)` + deps wiring |

## Tools / docs only

| Path | Summary |
|------|---------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | `_G.clubkit_update_engine` + `_G.clubkit_engine_update_status` automation hooks |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.6.1 |
| `VERSION` | 2.6.1 |
| `CHANGELOG.md` | `[Unreleased]` → `[2.6.1]` |
| `UPGRADE_PROGRESS.md` | unreleased table reset |
| `docs/releases/2.6.1/` | this release folder |
