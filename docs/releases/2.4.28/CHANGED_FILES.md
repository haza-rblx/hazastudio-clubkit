# Changed Files — v2.4.27 → v2.4.28

## Summary
- Leaderboard displayName enrich heal
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Server/.../DonationController.luau` | Fix `enrichEntryList` pcall (entries only) |
| `Shared/Utils/LeaderboardIdentity.luau` | Resolve when `displayName == username` |
| `KitProduct.luau` | Version 2.4.28 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.28 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/OneTimeLeaderboardSeeder/OneTimeLeaderboardSeeder.server.luau` | UserService identity |
| `CHANGELOG.md` / `docs/releases/2.4.28/` | Release notes |
| `VERSION` | 2.4.28 |
