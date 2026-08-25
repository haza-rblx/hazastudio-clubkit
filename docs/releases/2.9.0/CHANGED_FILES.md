# Changed Files — v2.8.9 → v2.9.0

## Summary
- 16 source files changed (2 new) + release docs + version triad
- Breaking: no

## Core — replace via Update Engine (source sync)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` 2.8.9 → 2.9.0 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `VOTE_SKIP_DURATION` 1 → 15; new `Config.ImagePreload` table; new `Config.AfkGuard.REJOIN_LADDER` / `HARD_STOP_IDLE_SEC` / `AUTO_REJOIN_CYCLE_TTL_SEC` / `TELEPORT_CONFIRM_TIMEOUT_SEC`; `IDLE_THRESHOLD_SEC` 17m → 13m; `AUTO_REJOIN_RATE_WINDOW` 900 → 600 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AfkGuardDomain.luau` | Attempt-counter model replaced with ladder model: `getLadder` / `resolveLadderStep` / `isIdleRegression` / `getHardStopIdleSec`; request payload gains `cycleId` + `stepIndex` |
| `src/StarterPlayerScripts/.../Client/Services/ImagePreloadService.luau` | **New.** Tiered image warm-up service |
| `src/StarterPlayerScripts/.../Client/Utils/ImageSwap.luau` | **New.** Blank-frame-free image assignment helper |
| `src/StarterPlayerScripts/.../Client/Utils/GroupedRowCornerUtil.luau` | **New.** Grouped-list corner rounding for settings/profile rows |
| `src/StarterPlayerScripts/.../Client/UI/MenuSettingsCore.luau` | `resolveSegmentedButtonFrame` rewritten (content-based lookup, fixes dead MultiOption rows); exported `SETTINGS_ICON` for preload |
| `src/StarterPlayerScripts/.../Client/UI/SettingsTabBinder.luau` | Calls `GroupedRowCornerUtil.apply()` on conditional-visibility refresh |
| `src/StarterPlayerScripts/.../Client/UI/ProfileTabBinder.luau` | Calls `GroupedRowCornerUtil.apply()` on profile patch |
| `src/StarterPlayerScripts/.../Client/Controllers/GenericBroadcastController.luau` | Wrapper type check relaxed `CanvasGroup` → `GuiObject` (fixes dead `/announce`) |
| `src/StarterPlayerScripts/.../Client/Controllers/AfkGuardController.luau` | Ladder-driven scheduling; resets on `idleTime` regression instead of `InputBegan` alone; fires remote before notifying |
| `src/StarterPlayerScripts/.../Main.client.luau` | Registers + starts `ImagePreloadService` before the loading screen finishes |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/AfkGuardService.luau` | Rate token now admits one cycle instead of one request; leak metric on `onPlayerRemoving` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/SessionCommandService.luau` | `safeTeleportAsync` gains `requireConfirmedExit`; `handleAfkRejoin` performs exactly one attempt per call |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | `filteredProviderDisplayName` removed; unlinked donor nickname on the cash workspace board now uses `cleanOptionalMessage` only (ADR 0004 amendment) |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | `afkGuardService` forward-declared above the `PlayerRemoving` handler that uses it (was silently never invoked) |

## Buyer-owned — review manually, do NOT replace
_None this release — no buyer config fields added or changed._

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` 2.8.9 → 2.9.0 |
| `VERSION` | 2.9.0 |
| `CHANGELOG.md` | v2.9.0 entry |
| `UPGRADE_PROGRESS.md` | reset |
| `docs/adr/0004-text-filtering-policy.md` | Amendment (2026-08-24) documenting the unlinked-donor-nickname exemption |
| `docs/releases/2.9.0/` | this folder |
