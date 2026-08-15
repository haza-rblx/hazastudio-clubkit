# Changed Files — v2.5.3 → v2.6.0

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 29 (+ release docs) |
| Breaking | no |

All engine changes ship via **Update Engine (source sync)**. No RBXM needed.

## Core — replace via Update Engine

| Path | Type | Summary |
|------|------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | mod | `KitVersion` → 2.6.0 |
| `.../Shared/Config/ClubKitConfigSchema.luau` | mod | schema defaults for `Announcement.MinMembership` + `ExternalAdmin` |
| `.../Shared/Config/ConfigBootstrap.luau` | mod | wire `MinMembership` (no `OverheadDomain` require) + `ExternalAdmin` |
| `.../Shared/Constants/Config.luau` | mod | `Announcement.MIN_MEMBERSHIP_TIER`; boards paint/fetch top 50; `AfkGuard.TELEPORT_INIT_TIMEOUT_SEC` / `CLIENT_RETRY_BACKOFF_SEC` / `MAX_CLIENT_ATTEMPTS`; `ExternalAdmin` internal defaults |
| `.../Shared/Domain/AfkGuardDomain.luau` | mod | `ClientRetryState` type + pure `canRequestRejoin(state, idleSec, nowSec)` |
| `.../Shared/Domain/CommandLibraryDomain.luau` | mod | announce help text reads tier from config (no Tier2 hardcode) |
| `.../Shared/Domain/PermissionDomain.luau` | mod | free announce uses min tier from Config |
| `.../Shared/Domain/ExternalAdminDomain.luau` | NEW | pure helpers: provider normalize, never-sync guard, rank map resolution |
| `src/ServerScriptService/.../Server/ExternalAdminFacade.luau` | NEW | singleton facade for Adonis/Kohl's bridge (selector-aware detection) |
| `.../Server/Init/ServerModuleBag.luau` | mod | expose `ExternalAdminFacade` in DI bag |
| `.../Server/Main.server.luau` | mod | inject `eventBus` into GiftService; wire ExternalAdminFacade |
| `.../Server/Services/AfkGuardService.luau` | mod | gate reorder: in-flight + carry checks before rate-limit token consume |
| `.../Server/Services/GiftService.luau` | mod | emit `Gift:RoleChanged` for live rank sync |
| `.../Server/Services/SessionCommandService.luau` | mod | AFK rejoin + `/rejoin`: `TeleportAsync` + `TeleportOptions.ServerInstanceId`, scoped `TeleportInitFailed` watcher (`safeTeleportAsync`), watcher cleanup |
| `src/StarterPlayerScripts/.../AfkGuardController.luau` | mod | boolean latch → retry state (60s backoff, max 3/idle streak); feature-flag gate `== false` |
| `src/StarterPlayerScripts/.../MusicPlayerController.luau` | mod | DJ effects: reuse DSP instances, unchanged-value guards, `Enabled` flips |

## Buyer-owned — review manually, do not replace

| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **Template** gains `Announcement.MinMembership` + `ExternalAdmin` (additive). Live buyer config is fill-forwarded by the plugin/runtime — never overwritten. |

## Optional place-pack (manual inject — not in Engine sync)

| Path | Summary |
|------|---------|
| `extras/place-packs/ExternalAdminBridge/` | README, Adonis plugin, Kohl's addon, `ExternalAdminSelector` boot-gate snippet |

## Docs / tools only

| Path | Summary |
|------|---------|
| `CHANGELOG.md` | `[Unreleased]` → `[2.6.0]` |
| `VERSION` | 2.6.0 |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.6.0 |
| `UPGRADE_PROGRESS.md` | unreleased table reset |
| `CONTEXT.md` | glossary: External admin, Facade, Provider, Rank sync |
| `AGENTS.md` | live-audio DSP rule + release notes |
| `docs/adr/0003-external-admin-bridge.md` | NEW ADR |
| `docs/releases/2.6.0/` | this release folder |
| `docs/delivery/TEMPLATE_PLACE.md`, `docs/delivery/OWNER_ONBOARDING.txt`, `deliver/README.md` | delivery docs |
| `tools/migrate-wx-likes-robux.luau` | dev migration script |
| `sourcemap.json` | regenerated |
| `.mimocode/`, `.cursor/plans/` | agent skills / planning notes (first commit) |
