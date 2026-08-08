# Upgrade v2.4.74 → v2.4.75

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. Play test — server should boot without `DonationController` syntax error

`ClubKitConfig` / `Secrets` unchanged.

## What's new

**Hotfix only** — removes a stray `er` line at the end of `DonationController.luau` that prevented the server from starting (`Expected <eof>, got 'er'`). Clients could not pass the loading screen because `Main.server` failed to load.

## Config changes

None.

## Breaking

**No.**

## QA after upgrade

- [ ] F9 / KitVersion **2.4.75**
- [ ] Play — no `DonationController:1913` error on server
- [ ] Loading screen completes (server `Main` loads)
- [ ] Donation panel / leaderboards still work after boot
