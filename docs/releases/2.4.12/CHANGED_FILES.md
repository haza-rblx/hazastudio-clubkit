# Changed Files - v2.4.11 -> v2.4.12

## Summary

- Join greeting ~7s; Join Commun always show + Already joined CTA
- Breaking: **no** (behavior change for already-in-group players only)
- Git tag: `v2.4.12`

## Core - replace via source sync

| Path | Change |
|------|--------|
| `src/.../Controllers/JoinCommunityPromptController.luau` | Always show modal; IsInGroup -> BUTTON_ALREADY_JOINED + dismiss (no PromptJoinAsync) |
| `src/.../Shared/Constants/Config.luau` | `BUTTON_JOIN` / `BUTTON_ALREADY_JOINED`; JoinGreeting ~7s holds |
| `src/.../Services/JoinGreetingService.luau` | Fallback hold defaults aligned to ~7s |
| `src/.../Controllers/JoinGreetingController.luau` | Fallback hold defaults aligned to ~7s |
| `src/.../KitProduct.luau` | KitVersion `2.4.12` |

## Buyer-owned - review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan - optional comment-only template note (PromptJoinCommunityOnLoad) |
| `Secrets` | Pertahankan - no required merge |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.12` |
| `docs/releases/2.4.12/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.12` |
