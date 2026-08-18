# Upgrade v2.6.5 → v2.6.6

Luau engine-only update — source sync, no RBXM needed.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (standard precaution; this update does not touch them)
2. In Studio: Plugin → **Engine → Update Engine** → Save place

## What's new
- **Unlimited levels** — level cap removed (was 100). Players past 100 resume leveling on their next XP gain. Want a cap back? Set `Config.Level.MAX_LEVEL` to any number (`0` = unlimited).
- **Donation cinematic now zooms in** — donation camera tiers (≥500 R$ / ≥50rb cash) use a new `DonationPushIn` dolly-zoom mode instead of the fixed-FOV orbit. `DonationPushIn` is also selectable manually in the Cinematic Dock movement list.

## Config changes
- None required. `ClubKitConfig` fill-forward will not change your existing values; no new keys.

## QA after upgrade
- [ ] Join, chat a few messages / wait online: XP still accrues and level-ups still fire (watch `Lv.N` overhead row)
- [ ] If you had a player previously stuck at Lv.100: their next XP gain should level them past 100
- [ ] Trigger a ≥500 R$ donation (or `/fakecash` equivalent): cinematic holds framing on the donor and eases FOV in (no orbit swing)
- [ ] Cinematic Dock manual movement list shows `DonationPushIn`
