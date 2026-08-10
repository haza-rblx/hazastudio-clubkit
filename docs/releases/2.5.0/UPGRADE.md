# Upgrade v2.4.80 → v2.5.0

## Quick steps
1. Studio → ClubKit plugin → **Settings → Update plugin** (if outdated)
2. Studio → ClubKit plugin → **Engine → Update Engine** → Save place
3. (Optional) Config → Donations tab → set **Cash currency** to `IDR` or `PHP` if your venue settles in Peso
4. If you use custom-designed Admin Hub action sheets, review `StarterGui/04-AdminHub` — see "Admin Hub" below
5. Ops only (not buyer-facing): run `npm run cf:d1:migrate:remote` on `donation-api` **before** `npm run cf:deploy`

Engine-only update — `ClubKitConfig` and `Secrets` are never fully replaced. Missing keys (like `Donation.Currency`) fill-forward to safe defaults after Update Engine.

## What's new

### Cash currency: IDR + PHP
- New `ClubKitConfig.Donation.Currency` (`"IDR"` | `"PHP"`, default `"IDR"`) drives the cash symbol, thousands grouping, chip word, and spender-role label everywhere cash is shown — donation notifications, leaderboard boards, workspace boards, overhead chips, join greetings, the Settings "Name Tag Details" toggle, Command Library descriptions, admin chat command replies, and Admin Hub previews.
- **Display only** — amounts stay untagged integers and are **not** converted. If you switch currency, retune `MinAmount`, `AuraTiers` (`idrMin`/`idrMax`), and `WorldEffectTiers` by hand for the new unit.
- Plugin **Config → Donations** tab gets a **Cash currency** dropdown that writes `Donation.Currency` directly.
- Admin dashboard (`donation-api`) gains a matching per-game `currency` column/dropdown for ops display — separate setting, does not sync to/from `ClubKitConfig`.

### Admin Hub — fully editable action sheets
- Action sheet bodies under `StarterGui/04-AdminHub` can now be redesigned as real GUI: either drop templates under `ActionTemplates/<actionId>`, or design in place on `04-ActionPopup.SheetBody` with an `ActionId` attribute. `openSheet` clones the matching master into `SheetContent` and never destroys your masters.
- Donate **Fake** no longer asks for a player target (attributes to the admin); **Manual**/credit only asks for a player after that mode is picked.
- `SelectedPlayerInfo` now clones your `SheetBody.SelectedPlayerInfo` template instead of a script-built chip.
- Sheet header icon/color follows the selected action tile automatically.
- Section filters moved from the removed sidebar to the top-header `Option1`–`Option5` slider (All / Utilities / Access / Identity / Donations).

### Gravity — independent Ungravity / Gravity gears
- **Ungravity gear** sets rise (float) speed only (1 slow → 10 fast) via `/ungravity N`.
- **Gravity gear** sets drop intensity only (1 soft → 10 hard) via `/gravity N`.
- These are two separate dials now — changing one does not affect the other. Gear value labels sync independently per tile.

### Plugin — Unpack RBXM
- Packager panel can pick a `.rbxm`/`.rbxmx` Club Kit package, deserialize it, and unpack into the place in one step. Existing `ClubKitConfig`/`Secrets` are preserved by default.

## Config changes
| Key | New template default | Notes |
|-----|----------------------|-------|
| `ClubKitConfig.Donation.Currency` | `"IDR"` | `"IDR"` \| `"PHP"`. Missing/unknown fills forward to `"IDR"` — existing buyers unaffected. |

## Breaking
- None. All new keys fill-forward to safe defaults. Admin Hub falls back to the old script-built sheets if you have no `ActionTemplates`/`ActionId` masters.

## QA after upgrade
- [ ] Admin Hub: open each action sheet (announce / role / gift / gravity gears / donate) — opens, closes, and submits correctly
- [ ] Set Ungravity gear to a low value and Gravity gear to a high value (or vice versa) — confirm rise speed and drop intensity differ independently
- [ ] Donate Fake — no player picker shown; Manual — asks for a player only after selecting Manual
- [ ] Switch `Donation.Currency` to `PHP` in the plugin — confirm symbol/chip/board labels update across notifications, boards, and overhead chips
- [ ] Switch back to `IDR` — confirm everything reverts correctly
- [ ] `/gravity` and `/gravity 5` (and `/ungravity`, `/ungravity 5`) still work from chat
- [ ] Shift+U / Shift+G hotkeys still float/restore correctly
