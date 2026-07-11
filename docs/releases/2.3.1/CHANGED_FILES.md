# Changed Files — v2.3.0 → v2.3.1

## Summary

- 8+ files changed (engine + buyer template + docs)
- Breaking: **no**
- Git tag: `v2.3.1`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Client/Controllers/JoinCommunityPromptController.luau` | **New** — delay + `PromptJoinAsync` once/session |
| `src/.../Main.client.luau` | Call prompt from `enterGameplay` |
| `src/.../Constants/Config.luau` | `FeatureFlags.PromptJoinCommunityOnLoadEnabled` |
| `src/.../Config/ConfigBootstrap.luau` | Map `Features.PromptJoinCommunityOnLoad` → flag |
| `src/.../KitProduct.luau` | KitVersion `2.3.1` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Merge optional: `Features.PromptJoinCommunityOnLoad` (kit template adds it; sync does not overwrite buyer file) |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `src/.../Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template: `PromptJoinCommunityOnLoad = true` |
| `tools/.../plugin/ClubKitManifest.luau` | `2.3.1` |
| `docs/releases/2.3.1/**` | Upgrade notes |
| `CLUB_KIT_SETUP.md` | Features example note |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.3.1` |
