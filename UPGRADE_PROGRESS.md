# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.11.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|
| 2.11.0 release | **Released 2026-08-30** (roleColor.stops, role chip, per-role privileges, dynamic Admin Hub picker, ADR 0008 phase 1 guards in `log` mode, external-loading contract + ClubKitMusic duck, boot timeout 120 s, `Features.HierapolisCustom`). Docs: `docs/releases/2.11.0/`. Still to do: push tag, customer web update, Discord announce, delivery pack rbxm. |
| **MovementGuard flip to `kick` — due 2026-09-06** | 2.11.0 ships `Config.MovementGuard.ENFORCE = "log"` (ADR 0008 decision 4). After one week, review `runtime:movement_warn` / `movement_kick` beacons on the Fleet page; if clean, flip the default to `"kick"` and ship it. If one place shows false positives (teleport pads / lifts / vehicles), flip per place instead. |
| License hardening (ADR 0006) | **Released in 2.10.0** (kit + VPS backend live). Deferred to a future release: universe check on the *data* endpoints (Pillar 1) + per-buyer hidden canary (Pillar 4 Packager step); brick default OFF until validated live. |
| 2.10.0 release + delivery pack | Released + pushed (`v2.10.0`) 2026-08-28. Desktop `ClubKit v2.10.0 Delivery/` ready **except** `HazastudioClubKit_Package_v2.10.0.rbxm` — owner still owes: **Ctrl+S the-basic** (the 19-file MCP sync is unsaved otherwise) then packager **Create package** into the folder. Plugin 2.10.0 rbxm installed; loads on next Studio restart. |
| Runtime integrity & abuse defense (ADR 0008) | **Phase 1 released in 2.11.0** (SoundGuard, ScriptGuard, RemoteStorm, AvatarGuard, MovementGuard; 41 lune tests; verified the-basic 2026-08-29 + 2-client pass 2026-08-30). Defaults: sound `log`, script `beacon`, movement **`log`** (Owner/CoOwner exempt), avatar effects `cap`. Decision 4 closed; owner still owes decisions 1, 2, 3, 5, 6. Phase 2 (`/purgesounds`, `/lockdown`, foreign-animation rule, per-place `ClubKitConfig.Security` overrides) not started. |
| Security audit 2026-08-29 | `docs/security/AUDIT-2026-08-29.md` — **5 HIGH open** (H1 Studio gift bypass → Owner on live DataStore; H2 ProfileMenuUpdate ungated; H3 NotifDisplay ledger/HTTP flood; H4 SettingsReset ungated; H5 arbitrary sticker image), 14 MEDIUM, 11 LOW. Guard-related HIGHs fixed same day (noclip filter, seated exemption, RemoteStorm default `log`, leaks). Suggested order in the doc; nothing else fixed yet. |
| Product telemetry (ADR 0007) | Phases 0+A **live on the VPS** 2026-08-28: `/fleet` (master-only, enriched) + `v3/telemetry` ingest. Kit phases B–D pending a future kit release. |
| RUST → VPS + data migration | Done 2026-08-27 (`docs/buyers/rust.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| NIGHT ZONE → VPS + data migration | Done 2026-08-27 (`docs/buyers/night-zone.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| AFTER HOURS → VPS data migration | Done 2026-08-28 (`docs/buyers/after-hours.md`, 164/164). Owner still owes: repoint BagiBagi webhook + point place ApiUrl. |

---

## File changes (unreleased)

| Path | Change |
|------|--------|
| _(none yet — 2.11.0 shipped 2026-08-30)_ | |

---

## Open follow-ups (carried past 2.11.0)

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
