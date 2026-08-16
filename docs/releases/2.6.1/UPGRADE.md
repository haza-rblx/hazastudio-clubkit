# Upgrade v2.6.0 → v2.6.1

**Date:** 2026-08-16

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

No config changes in this release — nothing to merge.

## What's new

- **Packager plugin automation hooks** — `_G.clubkit_update_engine()` + `_G.clubkit_engine_update_status` for command-bar / MCP automation of "Update engine".

## Fixes

- **AFK auto-rejoin only worked once** — after the first successful rejoin, the chain latched: the in-flight flag was never cleared on success, `handleAfkRejoin` was not pcalled, and the client burned its 3 retry attempts on silent `rate_limited` denials (no server→client feedback), dead-ending until physical input. Now: new `AfkRejoinResponse` remote reports the gate outcome + `retryAfterSec` to the client; transient denials don't consume the attempt budget; the client re-arms on `allowed`/`rejoin_failed`; `handleAfkRejoin` is pcalled; in-flight clears on success/error/stale watchdog.
- **Dance sync lost on native respawn** — AFK dance sync now also restores on a native respawn (Reset / LoadCharacter / reconnect), not only after a teleport.

## Known limitation (documented, not a bug)

Roblox's native 20-minute idle kick is client-side and is **not** prevented by teleport rejoins (the idle counter survives a same-server teleport). Preventing it requires synthetic input (`VirtualUser`), which Roblox's own docs call unmaintained and unreliable. This guard restores position + dance sync for semi-active players — it is not an AFK-kick bypass.

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] AFK rejoin: idle past threshold → rejoin fires; idle again after rejoin → rejoin fires again on the next cycle (no longer latches)
- [ ] Dance sync: trigger AFK rejoin, then respawn manually (Reset) → dance animation resumes
- [ ] No new errors in Output on boot
