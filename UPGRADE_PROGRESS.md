# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `3.0.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_ — never bump `VERSION` before "okay this is update X.Y"
**Active branch:** `main`

---

## Status summary

**3.0.0 released 2026-10-09.** The full 3.0 progress log (tables, decisions, verification notes) as it stood at release is in [`docs/releases/3.0.0/PROGRESS_ARCHIVE.md`](docs/releases/3.0.0/PROGRESS_ARCHIVE.md). Buyer guide: [`docs/releases/3.0.0/UPGRADE.md`](docs/releases/3.0.0/UPGRADE.md). File list: [`docs/releases/3.0.0/CHANGED_FILES.md`](docs/releases/3.0.0/CHANGED_FILES.md).

## Carried over after 3.0.0

| Item | Who | Notes |
|------|-----|-------|
| PARKLAB event absen (quest milestones) rollout | owner + agent | PARKLAB is still on 2.12.0 and has no event board. Needs: full engine sync, GUIs `18-EventQuestPopup`, `19-EventReminders` and the `EventTab` templates in `07-MenuGUI`; set `FreeTitleEvent.Trigger = "Topbar"` first (sync wipes the place-only topbar/menu); check `Group.GROUP_ID`; create the quest on the dashboard: 7 days 50 R$ ×100, 14 days 50 R$ ×150, 21 days voucher. Start 2026-10-09. |
| Music panel 3.0 GUI RBXM | owner | Save the cover stack (`BackdropNear`, `BackdropFar`, `CoverImage`) into the template, then export `06-MusicPlayerGUI` v3 with `Enabled = false`. Buyers cannot run 3.0 scripts without it. |
| Delete the duplicate `QueueListTemplate` in `06-MusicPlayerGUI` | owner | Place GUI only. |
| Ctrl+S on THE BASIC TEST and the Experiment Area | owner | Unsaved synced files. |
| clubkit-infra: commit and push `main`; deploy migration `0024` with `license-routes.js` and `discord.js` | owner | Foreign GUI detail. Migrations 0028 and 0029 are deployed (2026-10-09). |
| 3.0 playtests: 2-player music pass, Stage E gate, per-track cover in game, panel refresh | owner | See UPGRADE.md "Known issues". |
| UI motion: reduced-motion run, phone-emulator pass, live checks | owner | ADR 0011 gate. |
| Security hardening SH2–SH10 (H1 Studio gift bypass, H2–H4 DoS, D4 sticker writes, others) | agent | Guard modes (RemoteStorm, `MovementGuard` `ENFORCE`, SoundGuard, ScriptGuard) are owner decisions. |
| Onboarding modal and cinematic loading | owner | Built, both flags off. Needs an owner verdict. |
| ADR 0020 for the VPS-owned quota and the one-Robux rule | agent | Offered, not answered. |
| Creator live status (`🔴 LIVE`) | owner | Paused at round 3; feasibility spike first. |
| Perf & Structure Lane B (template and place data, RBXM) | owner | Not started. This lane is what justified the major version. |
| Overhead cash-rank chip assigned to the wrong player (Atlantis) | agent | Backlog. Needs its own diagnosis. |
| Packager `collect()` bundles installed admin loaders | agent | Backlog. |
| RUST and NIGHT ZONE still on a 2.9.2-era build | owner | Plan the jump separately from the release. |
| `sourcemap.json` stale since 2.6.0 | agent | Regenerate with `rojo sourcemap`. |

---

## On release — agent checklist

1. [ ] User confirms version number
2. [ ] Move `[Unreleased]` in `CHANGELOG.md` to new version section + date
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion` (+ `PLUGIN_VERSION`)
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset unreleased table in this file
7. [ ] Git tag: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** from `tools/ClubKitPackagerPlugin` (plugin-build sync alone is not enough if the place Tool still uses an old binary)
