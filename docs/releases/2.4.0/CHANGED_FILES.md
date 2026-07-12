# Changed Files — v2.3.1 → v2.4.0

## Summary

- ~12 files changed (engine + buyer template + tools + docs)
- Breaking: **behavior** (join community prompt UX; not a DataStore break)
- Git tag: `v2.4.0`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinGreetingService.luau` | **New** — eligibility + broadcast payload |
| `src/.../Controllers/JoinGreetingController.luau` | **New** — GenericBroadcast-style toast UI |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Custom modal + skip if member; Shop/Gift center-panel motion |
| `src/.../Server/Main.server.luau` | Remote + JoinGreetingService wire |
| `src/.../Main.client.luau` | Init JoinGreetingController |
| `src/.../Constants/Config.luau` | `Config.JoinGreeting` + `FeatureFlags.JoinGreetingsEnabled` |
| `src/.../Config/ConfigBootstrap.luau` | Map `Features.JoinGreetings` → flag |
| `src/.../KitProduct.luau` | KitVersion `2.4.0` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Merge: `Features.JoinGreetings`; review `PromptJoinCommunityOnLoad` comment/behavior |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `src/.../Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template: `JoinGreetings = true`; PromptJoin comment |
| `tools/PrintJoinCommunityAndGreetingGuiTree.editmode.luau` | **New** — edit-mode GUI tree dump |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.0` |
| `docs/releases/2.4.0/**` | Upgrade notes |
| `CLUB_KIT_SETUP.md` | PromptJoinCommunityOnLoad comment |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.0` |
