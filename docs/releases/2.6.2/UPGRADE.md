# Upgrade v2.6.1 → v2.6.2

**Date:** 2026-08-16

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

No config changes in this release — nothing to merge.

## What's new

- **Seamless AFK rejoin** — after an AFK auto-rejoin, the player no longer sees the first-join interruptions: the loading screen is skipped entirely, the Join Community prompt is not shown, and music/dance resume immediately instead of waiting for the normal post-join delays. Normal (non-rejoin) joins are unchanged.
- **Solo dancers auto-sync to the top leader on rejoin** — a player who was dancing solo when they rejoined is now pulled onto the current top leader (most followers, dancing), so the floor converges. Fully-idle players are left alone. Controlled by the existing `SYNC_FALLBACK_TOP_LEADER` engine flag.

## Config changes

None. (No new buyer-facing keys. `SYNC_FALLBACK_TOP_LEADER` and `SYNC_REQUIRE_LEADER_DANCING` already existed.)

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] AFK rejoin: idle past threshold → rejoin lands with **no loading screen** and **no Join Community prompt**; music/dance resume immediately
- [ ] Solo dancer rejoin: dance solo → rejoin → auto-syncs to the top leader (if another player is leading a group)
- [ ] Normal join (not a rejoin): loading screen + prompt still appear as before
- [ ] No new errors in Output on boot
