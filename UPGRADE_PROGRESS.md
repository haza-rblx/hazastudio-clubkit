# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.7.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|
| Text filtering compliance (ToS audit fix) | Released in 2.6.7 | |
| VIP-on-join (`VipOnCommunityJoin = true`) | Place-specific, not engine — set manually per place | |
| Emote AnimationId (hash → numeric) | Place-specific content, done manually in KASTA | |

---

## File changes (unreleased)

| Path | Change |
|------|--------|
| `tools/donation-api/migrations/0010_notification_deliveries.sql` | New — D1 delivery ledger + ack audit tables |
| `tools/donation-api/src/v3-routes.js` | New — v3 delivery/ack/status/DLQ endpoints + admin report |
| `tools/donation-api/src/worker.js` | Wire v3 routes + admin delivery-report/dlq + health v3_version |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +`RELIABILITY_V2_ENABLED`, `REMOTE_NOTIF_ACK`, retry params; `NOTIF_MAX_QUEUE` 20→100 |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`Donation.ReliabilityV2` (buyer opt-in flag) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Fill-forward `ReliabilityV2` → `RELIABILITY_V2_ENABLED` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | +`DonationNotifPayload.donationId` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | Ack listener, retry sweep, delivery register/ack/DLQ HTTP, v3 URL builder |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Main.server.luau` | +`DonationNotifAck` remote, pass to DonationService |
| `src/StarterPlayerScripts/.../Client/Controllers/DonationNotificationController.luau` | Fire `DonationNotifAck` on enqueue (delivery, not display) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AnnouncementRateLimitDomain.luau` | New — per-role-group announce budget resolver (Leadership/Spender/Member/Player) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +`Announcement.RATE_LIMIT_*` defaults (4 groups) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`Announcement.RateLimits` buyer override |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Fill-forward `Announcement.RateLimits` per group |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/CommandExecutionService.luau` | `/announce` now uses per-role-group limiter via shared resolver |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/ExternalAdminFacade.luau` | Facade announce uses same per-role-group resolver |
| **Load-test hardening (evidence-based, 30/50-donation D1 bursts via MCP Studio playtest)** | |
| `DonationService.luau` | Fix forward-reference crash in `handleNotifAck`/`sweepPendingDeliveries` (locals forward-declared); bodies moved after helpers |
| `DonationNotificationController.luau` | Ack on **enqueue** (delivery) not after display; idempotent retry-dedup by `donationId`; nil-guard on `showingNotifPayload` |
| `Config.luau` | Retry window `5s×3` → `8s×20` (~160s) to cover worst-case burst queue drain |
| `tools/donation-api/src/v3-routes.js` | `delivery-dlq` accepts `roblox_user_id=0` sentinel + `reason` → whole-donation `failed_resolve` rows; admin DLQ surfaces both |
| `DonationService.luau` | `reportResolveFailure` — phase-2 resolve crash / empty-result now lands in ledger as `failed_resolve` instead of silent loss |
| **Locked-decision closure (a/b/c) + race fix** | |
| `DonationNotificationController.luau` | (a) Removed lowest-amount eviction entirely (soft cap, never drop); (b) hard floor `NOTIF_BACKLOG_HARD_FLOOR_SECS=2` past half-queue |
| `Config.luau` | +`NOTIF_BACKLOG_HARD_FLOOR_SECS=2` |
| `v3-routes.js` | `delivery-ack` now UPSERT (was UPDATE) — fixes ack-beats-registration race observed in 60-burst |
| **Code-review fixes (two-axis gate passed)** | |
| `Config.luau` / `ConfigBootstrap.luau` | +`RATE_LIMITS_CONFIGURED` — detects buyer `RateLimits` from RAW ClubKitConfig (not fill-forwarded state) so legacy fallback is real |
| `CommandExecutionService.luau` / `ExternalAdminFacade.luau` | Wire `legacyBudget()` fallback when `RATE_LIMITS_CONFIGURED=false` (was dead code → silently changed budgets) |
| `Main.server.luau` / `DonationNotificationController.luau` | Drop unnecessary `:: any` casts on existing strict constant |
| `v3-routes.js` / migration 0010 | `failed_resolve` added to `DELIVERY_STATUSES` + status comment |
| Reverted (other session's, NOT this release) | `ClubKitConfig.luau` (buyer-owned), `CinematicDockController.luau`, Cinematic hunks in Schema/Bootstrap |
| **Couple chat tag toggle (unreleased, this session)** | |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | +`Config.Couple.SHOW_CHAT_TAG = true` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Overlay `Features.ShowCoupleChatTag` → `Config.Couple.SHOW_CHAT_TAG` (non-FeatureFlags pattern, like DonationRankGradientAnim) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | +`defaults.Features.ShowCoupleChatTag = true` + FEATURE_MANIFEST "Couple chat tag (General)" |
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` (template) | +`ShowCoupleChatTag = true` with comment |
| `src/StarterPlayerScripts/.../Client/Controllers/ChatTagsController.luau` | Gate `buildPrefixText` coupleTag on `Config.Couple.SHOW_CHAT_TAG ~= false` (client-side render gate; server still sends data — backward compat) |
| **Group-owner text-filter fix (unreleased, this session)** | Root cause: on group-owned places `game.CreatorId` is a GROUP id → `FilterStringAsync` author fails → community/provider-donor names stored as `#####` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/TextFilterUtil.luau` | +`resolveFilterAuthorUserId()` — user-owned → `game.CreatorId`; group-owned → group owner via `GroupService:GetGroupInfoAsync` (memoized); +`GroupService` import |
| `src/ServerScriptService/.../Repositories/DonationLeaderboardRepository.luau` | Community-name filter author now uses resolver (was `game.CreatorId`) |
| `src/ServerScriptService/.../Services/DonationService.luau` | `filteredProviderDisplayName` fallback author now uses resolver (was `math.floor(game.CreatorId)`) |

**REVERTED:** replay-on-join ring buffer (locked decision (c)) was implemented then REMOVED per product call — donation notifications are live-moment only; late joiners intentionally do not see them. No config surface shipped. |

---

## Backlog (not scheduled)

- **Packager `collect()` bundles installed admin loaders** (`Adonis_Loader` / `Kohl's Admin`) into the main template pack — these are buyer-choice and should be excluded like BHMS. Caused a leftover Kohl's to ship into a buyer place. Consider adding admin loaders to the Packager exclusion list.
- **Overhead cash-rank chip can be assigned to the wrong player** — observed on Atlantis: hazatargz showed `#12 RUPIAH` while having `cash_total=0` in the backend (rank #12 is a different, unlinked donor). Likely in rank-matching/`assignPlayer` name-fallback path in `DonationService`. Separate from the v2.6.5 webhook fix. Needs its own diagnosis.

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
