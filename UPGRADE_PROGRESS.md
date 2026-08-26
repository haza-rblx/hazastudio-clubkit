# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.9.2` (see [`VERSION`](VERSION))
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

**Open follow-ups (carried past 2.9.2):**
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
