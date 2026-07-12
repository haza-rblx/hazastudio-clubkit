# Changed Files — v2.4.14 → v2.4.15

## Summary

- VipOnCommunityJoin feature flag (default off); CommunityVipService + CommunityVipRecheck
- Breaking: **no** (opt-in config)
- Git tag: `v2.4.15`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/CommunityVipService.luau` | **New** — Tier1 VIP when IsInGroup; recheck remote handler |
| `src/.../Server/Main.server.luau` | Wire CommunityVipService; ensure CommunityVipRecheck remote |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Fire CommunityVipRecheck after PromptJoinAsync |
| `src/.../Shared/Constants/Config.luau` | FeatureFlags.VipOnCommunityJoinEnabled; REMOTE_VIP_RECHECK + rate limits |
| `src/.../Shared/Config/ConfigBootstrap.luau` | Map Features.VipOnCommunityJoin → FeatureFlags |
| `src/.../KitProduct.luau` | KitVersion `2.4.15` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | **Manual merge:** add `Features.VipOnCommunityJoin = true` to enable (repo template has `false`) |
| `Secrets` | Pertahankan — no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.15` |
| `docs/releases/2.4.15/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.15` |
