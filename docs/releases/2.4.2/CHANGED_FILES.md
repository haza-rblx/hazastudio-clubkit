# Changed Files — v2.4.1 → v2.4.2

## Summary

- 6 engine/docs files changed (+ VERSION / manifest / KitProduct / release docs)
- Breaking: **no**
- Git tag: `v2.4.2`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Constants/Config.luau` | `JoinCommunityPrompt` community copy; `JoinGreeting.WAIT_FOR_GAMEPLAY` |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Apply headline + body without VIP wording |
| `src/.../Controllers/JoinGreetingController.luau` | Hold toast until `notifyGameplayReady` |
| `src/.../Main.client.luau` | `JoinGreetingController.notifyGameplayReady()` from `enterGameplay` |
| `src/.../KitProduct.luau` | KitVersion `2.4.2` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.2` |
| `docs/releases/2.4.2/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.2` |
