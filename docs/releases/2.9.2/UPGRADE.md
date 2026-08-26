# Upgrade v2.9.1 → v2.9.2

Adds **Auto Dance** (topbar toggle that shuffles dance emotes) and fixes the stale `init` script duplicates that were flagged in 2.9.1 — the ones that threw `Utils is not a valid member` on every client boot. No buyer config changes required.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (they are never replaced by Update Engine).
2. In Studio: Plugin → **Settings → Update plugin** → **Engine → Update Engine** → Save place.
3. Done. The `init` cleanup runs automatically as part of Update Engine.

## What's fixed
- **`Utils is not a valid member of Folder "…Client.Effects"` on client boot is gone.** Four donation-effect scripts (`BlackHole`, `LocalNuke`, `GreenHammer`, `Blossom`) each carried a hidden duplicate copy of themselves named `init`. Because LocalScripts auto-run, those stale duplicates ran on every join with an outdated require path and errored — while the *real* script beside them worked fine, which is why the effects mostly still played and the error looked cosmetic. Update Engine now removes them automatically; a fresh `.rbxm` install cleans them too.
- If you have ever seen that error in your Output, it should be **zero** after updating. Nothing else about donation effects changes.

## What's new
- **Auto Dance** — a new **Auto** button on the left of the topbar, right next to **Lead Dance**, using the same icon as your dance button. Switch it on and your character shuffles to a random dance every 3–6 seconds; switch it off and the dance stops.
  - It never repeats the dance that is already playing, and the gap between dances is randomised so it does not look mechanical.
  - **Dance sync always wins.** Turning Auto on leaves a leader's sync group; joining a sync while Auto is running switches Auto off by itself. The two cannot fight each other.
  - Purely client-side and not saved — it resets when a player rejoins, same as the old system it was ported from.

## Config changes
- New `Config.AutoDance` in `Shared/Constants/Config.luau` (engine constants file, same place `Config.PanelBlur` and `Config.PanelZoom` live — not `ClubKitConfig`):
  - `ENABLED = true` — set `false` to remove the button entirely
  - `MIN_INTERVAL = 3`, `MAX_INTERVAL = 6` — seconds between dance changes
  - `TOPBAR_ORDER = 4` — position on the **left** topbar strip
  - `TOPBAR_ICON` — defaults to the stock dance panel button artwork. **If you have rebranded your dance button**, point this at your own asset so the two icons match.

## QA after upgrade
- Join and check Output: no `Utils is not a valid member` errors.
- Confirm the **Auto** pill appears on the left topbar next to Lead Dance, with your dance icon on it.
- Click it → your character should start changing dances every few seconds, and the label reads **Auto ON**.
- Click it again → the dance stops and the label returns to **Auto**.
- With Auto running, sync to another player → Auto should switch itself off and you should follow the leader normally.
