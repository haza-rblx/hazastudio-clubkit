# Changed Files - v2.4.10 → v2.4.11

## Summary

- Join greeting double-fire fix; EffectDonate uses NukeWorldPosition; game-data `/community` allow-all authenticated keys
- Breaking: **no** (behavior fix only)
- Git tag: `v2.4.11`

## Core - replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinGreetingService.luau` | `evaluationInFlight` before yielding `getPayload`; one fire per user/session |
| `src/.../Controllers/JoinGreetingController.luau` | Ignore duplicate remote per `userId` this client session |
| `src/.../EffectDonate/LocalNuke/init.client.luau` | Impact = `NUKE_WORLD_POSITION`; launch = optional NukeModel or stage |
| `src/.../EffectDonate/BlackHole/init.client.luau` | Stage/SPAWN from `NUKE_WORLD_POSITION` |
| `src/.../EffectDonate/GreenHammer/init.client.luau` | Giant spawn from `NUKE_WORLD_POSITION` |
| `src/.../EffectDonate/Blossom/init.client.luau` | Same as GreenHammer |
| `src/.../Shared/Constants/Config.luau` | Comment: NUKE_WORLD_POSITION / buyer override |
| `src/.../KitProduct.luau` | KitVersion `2.4.11` |

## Buyer-owned - review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan — optional comment-only template note; `NukeWorldPosition` now used by engine |
| `Secrets` | Pertahankan - no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/game-data-api/src/worker.js` | `COMMUNITY_ENABLED_GAMES = []` → allow all after auth (redeploy separately) |
| `tools/game-data-api/README.md` | Docs: community not allowlisted |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.11` |
| `docs/releases/2.4.11/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.11` |
