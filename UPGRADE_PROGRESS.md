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
| RUST → VPS + data migration | Done 2026-08-27 (`docs/buyers/rust.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| NIGHT ZONE → VPS + data migration | Done 2026-08-27 (`docs/buyers/night-zone.md`). On 2.9.2-era build; 2.10.0 available to roll out. Owner still owes: Ctrl+S, Saweria webhook repoint. |
| AFTER HOURS → VPS data migration | Done 2026-08-28 (`docs/buyers/after-hours.md`, 164/164). Owner still owes: repoint BagiBagi webhook + point place ApiUrl. |

---

## File changes (unreleased)

_(empty — 2.10.0 just shipped. Add new engine/buyer file changes here as development continues.)_

| Path | Change |
|------|--------|
|      |        |

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
