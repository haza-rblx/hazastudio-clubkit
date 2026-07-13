# Changed Files — v2.4.24 → v2.4.25

## Summary
- 5 core files + version stamps
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `.../Config.luau` | Sync per-tier preload + prewarm admission; Leaderboards coalesce/retry knobs |
| `.../DanceWarmupService.luau` | Per-tier budgets; full = tier1 then tier2 |
| `.../SyncService.luau` | Global prewarm admission + cancel on leave |
| `.../DonationController.luau` | Trailing rebuild coalesce; skip unchanged paint |
| `.../WorkspaceLeaderboardRenderService.luau` | Bound missing-board retries |
| `KitProduct.luau` | 2.4.25 |
| `tools/.../ClubKitManifest.luau` | 2.4.25 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `CHANGELOG.md` | 2.4.25 |
| `docs/releases/2.4.25/*` | Upgrade notes |
| `VERSION` | 2.4.25 |
