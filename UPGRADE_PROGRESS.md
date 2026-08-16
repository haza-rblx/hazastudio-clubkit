# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.6.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|
| Packager Update Engine automation hook (`_G.clubkit_update_engine`) | done (unreleased) |
| AFK rejoin post-2.6.0 latch fix (response remote + in-flight/pcall + client re-arm) | done (unreleased) |
| Dance sync restore on native respawn | done (unreleased) |

---

## File changes (unreleased)

| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | `_G.clubkit_update_engine` + `_G.clubkit_engine_update_status` automation hooks (engine page) |
| `src/ReplicatedStorage/.../Shared/Constants/Config.luau` | `AfkGuard.REMOTE_RESPONSE` |
| `src/ReplicatedStorage/.../Shared/Domain/AfkGuardDomain.luau` | `RejoinOutcome`/`RejoinResponse` types, `isTransientDenial`, `nextRetryDelaySec`; `ClientRetryState` docstring |
| `src/ReplicatedStorage/.../Shared/Utils/RateLimiter.luau` | `check()` return-3 `waitSec` on deny (additive) |
| `src/ServerScriptService/.../Server/Services/AfkGuardService.luau` | response remote, pcall wrap, in-flight clear (success+error+stale watchdog) |
| `src/ServerScriptService/.../Server/Services/SessionCommandService.luau` | `CharacterAdded` also restores `pendingAfkSyncRestore` on native respawn |
| `src/StarterPlayerScripts/.../Client/Controllers/AfkGuardController.luau` | consume response remote, scheduled retry w/ jitter, re-arm attempts on allowed/failed, idle-after-rejoin probe |
| `src/ServerScriptService/.../Server/Main.server.luau` | `ensureRemoteEvent(AfkRejoinResponse)` + deps wiring |
| `CHANGELOG.md` | `[Unreleased]` entry |

---

## On release — agent checklist

1. [ ] User confirms version number
2. [ ] Move `[Unreleased]` in `CHANGELOG.md` to new version section + date
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset unreleased table in this file
7. [ ] Git tag: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** from `tools/ClubKitPackagerPlugin` (plugin-build sync alone is not enough if the place Tool still uses an old binary)
