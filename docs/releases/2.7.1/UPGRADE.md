# Upgrade v2.7.0 → v2.7.1

Couple chat tag toggle + group-owner text-filter fix. No breaking changes.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (they are never replaced by Update Engine).
2. In Studio: Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine** → Save place.
3. Done — Update Engine fill-forwards the new `Features.ShowCoupleChatTag` (default `true`) into buyer config.

## What's new
- **Couple chat tag toggle** — hide the 💕 couple tag in the General/chat prefix without disabling the couple system. Set `ClubKitConfig.Features.ShowCoupleChatTag = false`. Default `true` (existing places unchanged). Also in the plugin Config Features panel as "Couple chat tag (General)".

## What's fixed
- **Community / provider-donor names showing as `#####` on group-owned places.** Root cause: on a group-owned place `game.CreatorId` is a **group id**, so the text filter failed and every community name on the donation leaderboard (and unlinked Saweria/Bagibagi donor names on boards) was stored as `#####`. Now the filter author resolves to the **group owner** (user-owned places unchanged). No config change needed.

## Config changes
- New optional flag `ClubKitConfig.Features.ShowCoupleChatTag` (boolean, default `true`). Fill-forwarded automatically; existing buyer configs keep working.

## QA after upgrade
- Couple tag still shows in chat by default; set `Features.ShowCoupleChatTag = false` → it hides.
- On a group-owned place, community leaderboard names render as real names (not `#####`) after a donation rewrites that community's metadata.
