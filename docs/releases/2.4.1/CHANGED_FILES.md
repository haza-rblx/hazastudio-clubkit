# Changed Files — v2.4.0 → v2.4.1

## Summary

- ~12 files changed (engine + buyer template comment + docs)
- Breaking: **no**
- Git tag: `v2.4.1`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Shared/Utils/BrandLogoApplier.luau` | NAME_MATCH includes `CommunityLogo` |
| `src/.../Shared/Constants/Config.luau` | `JoinCommunityPrompt` remotes/cache; JoinGreeting holds ~15s |
| `src/.../Services/JoinCommunityMembersService.luau` | **New** — Http group roster sample for modal thumbs |
| `src/.../Server/Main.server.luau` | Wire JoinCommunityMembersService + remotes |
| `src/.../Services/JoinGreetingService.luau` | Default hold timings aligned to ~15s |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Logo / thumbs / Subtitle+Body / CounterLeft |
| `src/.../Controllers/JoinGreetingController.luau` | Fallback hold defaults ~15s |
| `src/.../KitProduct.luau` | KitVersion `2.4.1` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Set `Branding.LogoImage` if still kit default (comment updated in template) |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `src/.../Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template comment: LogoImage also drives Join Commun |
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.1` |
| `docs/releases/2.4.1/**` | Upgrade notes |
| `CLUB_KIT_SETUP.md` | Stronger LogoImage buyer warning |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.1` |