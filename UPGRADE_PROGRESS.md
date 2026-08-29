# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.10.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|
| CanvasGroup blank/flicker (ADR 0005) | **Released in 2.10.0.** QA: NIGHT ZONE 0/91 groups (2026-08-28) + the-basic admin panel 0.0px seam + boot/cull verified. |
| License hardening (ADR 0006) | **Released in 2.10.0** (kit + VPS backend live). Deferred to a future release: universe check on the *data* endpoints (Pillar 1) + per-buyer hidden canary (Pillar 4 Packager step); brick default OFF until validated live. |
| Manual Robux via Admin Hub | **Released in 2.10.0.** Persist fix validated end-to-end in the-basic (42→542). |
| 2.10.0 release + delivery pack | Released + pushed (`v2.10.0`) 2026-08-28. Desktop `ClubKit v2.10.0 Delivery/` ready **except** `HazastudioClubKit_Package_v2.10.0.rbxm` — owner still owes: **Ctrl+S the-basic** (the 19-file MCP sync is unsaved otherwise) then packager **Create package** into the folder. Plugin 2.10.0 rbxm installed; loads on next Studio restart. |
| Runtime integrity & abuse defense (ADR 0008) | **Phase 1 built + verified in the-basic 2026-08-29** (SoundGuard, ScriptGuard, RemoteStorm, AvatarGuard, MovementGuard; 41 lune tests). Defaults: sound `log`, script `beacon`, movement `kick` (Owner/CoOwner exempt), avatar effects `cap`. Owner still owes decisions 1–6 in the ADR. Phase 2 (`/purgesounds`, `/lockdown`, foreign-animation rule, per-place `ClubKitConfig.Security` overrides) not started. |
| Security audit 2026-08-29 | `docs/security/AUDIT-2026-08-29.md` — **5 HIGH open** (H1 Studio gift bypass → Owner on live DataStore; H2 ProfileMenuUpdate ungated; H3 NotifDisplay ledger/HTTP flood; H4 SettingsReset ungated; H5 arbitrary sticker image), 14 MEDIUM, 11 LOW. Guard-related HIGHs fixed same day (noclip filter, seated exemption, RemoteStorm default `log`, leaks). Suggested order in the doc; nothing else fixed yet. |
| Product telemetry (ADR 0007) | Phases 0+A **live on the VPS** 2026-08-28: `/fleet` (master-only, enriched) + `v3/telemetry` ingest. Kit phases B–D pending a future kit release. |
| RUST → VPS + data migration | Done 2026-08-27 (`docs/buyers/rust.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| NIGHT ZONE → VPS + data migration | Done 2026-08-27 (`docs/buyers/night-zone.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| AFTER HOURS → VPS data migration | Done 2026-08-28 (`docs/buyers/after-hours.md`, 164/164). Owner still owes: repoint BagiBagi webhook + point place ApiUrl. |

---

## File changes (unreleased)

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RoleColorDomain.luau` | **New (pure).** `normalizeStops` / `toKeypoints` / `deriveChatPair` for `roleColor.stops`. Harness `.tmp/test_role_color_domain.luau` (lune, 11/11). |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RolesDomain.luau` | Sanitizes `roleColor.stops` at boot; fills `primary`/`secondary` from first/last stop when omitted. |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/Roles.luau` | `RoleColor.stops: { string }?` type. |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `RoleColorPalette` type gains `stops`; `Config.ClientBoot` gains the external-loading attribute names + `EXTERNAL_LOADING_TIMEOUT`. |
| `src/StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | `applyRoleStopsGradient` on `04-SpecialRank` (keyed setter, restores template gradient on role change). |
| `src/StarterPlayerScripts/.../Main.client.luau` | Publishes `ClubKitBootProgress` / `ClubKitBootSettled` / `ClubKitGameplayReady`; `enterGameplayAfterExternalHold` when the kit loading screen is off. |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau`, `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Comment-only: document `roleColor.stops` (no new schema key — it is optional inside an existing table). |
| `src/StarterPlayerScripts/.../Client/Controllers/AdminHubController.luau` | Set-role picker built from `Config.Roles` (`buildSetroleOptions` + `retargetPickCards`); hardcoded `SETROLE_OPTIONS` is fallback only. |
| `extras/place-packs/CinematicLoading/` | **New place pack (not engine):** Hierapolis cinematic loading screen ported onto the external loading contract. |
| `docs/adr/0008-runtime-integrity-abuse-defense.md` | **New ADR (Proposed).** Threat classes for a live venue (executors, backdoors, unguarded remotes, admin abuse, accounts, resource abuse) + 4-layer defense: place scan, `RuntimeGuard` (SoundGuard / ScriptGuard / RemoteStorm, log-only first), staff response commands, telemetry. Triggered by the "guest played laughing audio for everyone" incident. Layer 2b `MovementGuard` (fly/speed/noclip/teleport/inf-jump/foreign-animation → strike ledger → warn → kick, kit states exempt) and Layer 2c `AvatarGuard` (oversized accessories / beam-particle-light "laser" UGC → server-side trim, no kick) added same day. Owner decisions pending (enforce defaults, ScriptGuard destroy, buyer policy, movement kick default, animation rule). |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MovementPolicy.luau`, `.../AvatarPolicy.luau` | **New (pure).** Movement rules + strike ledger (harness `.tmp/test_movement_policy.luau`, lune 26/26); accessory size/effect judgement (`.tmp/test_avatar_policy.luau`, 15/15). |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Init/RuntimeGuard.luau`, `.../MovementGuard.luau` | **New.** SoundGuard / ScriptGuard / RemoteStorm / AvatarGuard, and the movement sampler + kick. Wired in `Main.server` after gravity/carry services (0 new Main locals); `ServerModuleBag` +2. |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.RuntimeGuard`, `Config.MovementGuard`, `Config.AvatarGuard` (engine constants — no buyer schema key yet; per-place override is a phase-2 decision). |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CharacterReady.luau` | `pivotTo` stamps `ClubKitTeleportAt` on the character (server-teleport exemption). |
| `tools/security/PlaceSecurityScan.luau`, `docs/delivery/SECURITY_CHECKLIST.md` | **New (tooling, not engine).** Static backdoor / remote-surface scan runnable in Studio; per-place hygiene checklist. |
| `docs/adr/0007-product-telemetry.md` | **New ADR (Accepted).** Product telemetry: fleet health + field diagnostics. Decisions locked 2026-08-28: v3 endpoint transport, v1 metrics = memory/FPS/device + network top-N (errors & feature-opens deferred), opt-out default ON via `ClubKitConfig.Telemetry`, retention 90d, Venue Insights later. Binding constraint: 500 req/min shared HttpService budget → aggregate flush only. **Phases 0+A built + tested in clubkit-infra** (migration 0021, `v3/telemetry` ingest, `/api/owner/fleet` master-only + telemetry read, dashboard Fleet page; suite 39/39, build clean). **Deployed to the VPS 2026-08-28** (API restart auto-applied 0021; dashboard swapped atomically). Master account `admin` is auto-routed to `/fleet` only — owner pages crash on master's `game_id NULL` (was a live blank-screen bug, fixed same day). Fleet then **enriched** (still existing-data-only): per-venue month/all-time donation volume, upgrade trail from `kit_version_history`, leak-beacon chip, 7-day DLQ chip, fleet-wide leak/DLQ counters. Kit phases B–D (TelemetryService/Client + network attribution + `ClubKitConfig.Telemetry` schema key) not started; will ride a future kit release. |

---

## Open follow-ups (carried past 2.10.0)

- **ADR 0006 deferred pieces:** (1) universe check on the *data* endpoints (`v2-routes`/`v3-routes` + game-data-api) — a cross-cutting kit+backend change so the kit must send its `universe_id` on every data call; (2) per-buyer *hidden* canary stamped into the pack by the Packager at build time (engine files are byte-identical across buyers); (3) brick (`Config.AntiTamper.BRICK_ON_DETECT`) is default OFF — enable once the exploiter detector is trusted live with the owner absent. See `docs/adr/0006-license-hardening.md`.
- **Auto Dance topbar pill is a temporary home.** Intended destination is the dance panel UI itself, next to the existing emote controls.
- **`Config.AutoDance.TOPBAR_ICON` is a hardcoded asset id** taken from the stock `StarterGui.IconGroup.DancePanelButton`. A buyer who rebrands their dance button gets mismatched icons, and a place without access to that asset shows a blank icon. Better: read `Image` off the live DancePanelButton at runtime, using the config value only as a fallback.
- **Server never notifies a follower when it auto-detaches them** (`SyncService.luau:937`, the "become our own root" branch). The follower's client keeps a stale `isSyncing = true`, so the dance panel keeps showing "syncing with X" and `onEmoteSelected`'s toggle-off branch stays disabled. Auto Dance now routes *around* this, but a player who syncs and then picks an emote manually still hits it. Fix would be to fire `unsync_success` on that path.

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
