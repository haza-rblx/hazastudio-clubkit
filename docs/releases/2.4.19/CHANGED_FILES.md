# Changed Files — v2.4.18 → v2.4.19

## Summary

- Production quiet Logger + red ERROR
- F9 Hazastudio ASCII banner + contact
- Leaderboard Workspace audit/probe tools
- Breaking: **no** (behavior: quieter live logs)
- Git tag: `v2.4.19`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Utils/Logger.luau` | Production gate + red ERROR via TestService |
| `src/.../Shared/Utils/ConsoleBanner.luau` | New — F9 ASCII splash |
| `src/.../KitProduct.luau` | KitVersion `2.4.19` + `Support` contact fields |
| `src/.../Server/Main.server.luau` | Print ConsoleBanner on boot |
| `src/.../Main.client.luau` | Banner + Studio-only boot noise |
| `src/.../LoadingBootstrap.client.luau` | Early client banner |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/CheckWorkspaceLeaderboardSetup.editmode.luau` | New — Workspace board audit |
| `tools/ProbeWorkspaceLeaderboardRuntime.playmode.luau` | New — play-mode overlay probe |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.19` |
| `docs/releases/2.4.19/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.19` |
