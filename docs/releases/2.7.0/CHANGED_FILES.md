# Changed Files — v2.6.7 → v2.7.0

## Summary
- 15 files changed (12 modified + 3 new)
- Breaking: **no** (fully additive; both features opt-in / backward compatible)
- Buyer-owned files: **untouched** (`ClubKitConfig.luau`, `Secrets.luau` unchanged at HEAD)

## Core — replace via source sync / RBXM
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +ReliabilityV2 + retry/backlog constants; +Announcement per-group `RATE_LIMIT_*`; `NOTIF_MAX_QUEUE` 20→100 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`Donation.ReliabilityV2`, +`Announcement.RateLimits` buyer surface |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | fill-forward `ReliabilityV2`, `RateLimits` per group, `RATE_LIMITS_CONFIGURED` from raw buyer config |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | +`DonationNotifPayload.donationId` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AnnouncementRateLimitDomain.luau` | **NEW** — shared per-role announce budget resolver + `legacyBudget()` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | v3 delivery ledger client (register/ack/DLQ/resolve-failure), retry sweep, ack listener wiring |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/CommandExecutionService.luau` | `/announce` per-group limiter + legacy fallback |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/ExternalAdminFacade.luau` | facade announce uses same per-group resolver + legacy fallback |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | +`DonationNotifAck` remote, pass to DonationService |
| `src/StarterPlayerScripts/.../Client/Controllers/DonationNotificationController.luau` | ack on enqueue, retry-dedup by donationId, eviction removed, hard backlog floor |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → 2.7.0, `BuildId` → 20260819 |

## Buyer-owned — review manually, do NOT replace
| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | unchanged at HEAD. New optional keys documented in UPGRADE.md: `Donation.ReliabilityV2`, `Announcement.RateLimits`. Fill-forward adds them automatically — no manual merge needed. |
| `Secrets.luau` | unchanged |

## Tools / docs only
| Path | Change |
|------|--------|
| `tools/donation-api/src/worker.js` | wire v3 routes + admin delivery-report/dlq + health v3_version |
| `tools/donation-api/src/v3-routes.js` | **NEW** — v3 delivery/ack/status/DLQ endpoints + admin report |
| `tools/donation-api/migrations/0010_notification_deliveries.sql` | **NEW** — D1 delivery ledger + ack audit tables (additive) |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.7.0 |
| `CHANGELOG.md` / `UPGRADE_PROGRESS.md` / `VERSION` | release bookkeeping |
