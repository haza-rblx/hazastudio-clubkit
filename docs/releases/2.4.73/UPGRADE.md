# Upgrade v2.4.72 → v2.4.73

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place (no new Config keys — nothing to fill-forward)
3. Confirm `ClubKitConfig.Donation.Provider` matches your cash provider (`bagibagi` / `saweria` / `sociabuzz`)
4. QA checklist below

`ClubKitConfig` / `Secrets` are not fully replaced, as usual.

## What's new

- **Cash leaderboard title follows provider** — the workspace cash board header (e.g. `SaweriaDonationBoard`) no longer stays stuck on the baked-in `SAWERIA DONATIONS` label. After Update Engine, it auto-updates to match `ClubKitConfig.Donation.Provider` (e.g. `BAGIBAGI DONATIONS`).
- **English default runtime copy** — engine defaults for couple announce, donation chat tag, gift errors, admin test-donation messages, and related Config strings are now English. Comments and internal docs are English too (buyer Indonesian docs UI at `docs/locales/id.js` unchanged).

## Config changes

No new keys. Existing field:

| Field | Notes |
|-------|--------|
| `Donation.Provider` | Drives cash tab branding, donation UI labels, **and cash leaderboard board title** after this release |

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## Breaking

**Soft (copy only):** default player-visible strings switch from Indonesian to English unless you override them in `ClubKitConfig` / custom UI. Gameplay and DataStore behavior unchanged.

## QA after upgrade

- [ ] F9 / KitVersion **2.4.73**
- [ ] `Donation.Provider = "bagibagi"` → cash board title shows **BAGIBAGI DONATIONS** (not Saweria)
- [ ] Switch provider to `saweria` / `sociabuzz` in config → title updates after engine sync + board paint
- [ ] Couple announce, donation chat tag, gift username error — English defaults
- [ ] Donation panel + leaderboards still load and refresh normally
