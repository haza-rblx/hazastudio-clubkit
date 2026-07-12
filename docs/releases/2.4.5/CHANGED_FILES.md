# Changed Files — v2.4.4 → v2.4.5

## Summary

- 6 engine/config files + version bumps / release docs
- Breaking: **no** (behavior: real MemberCount + JoinCommun emblem logo)
- Git tag: `v2.4.5`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../Services/JoinCommunityMembersService.luau` | Real MemberCount via GroupService + MEMBER_INFO_URL/roproxy; `memberCountKnown`; emblemUrl; never pool-as-total |
| `src/.../Controllers/JoinCommunityPromptController.luau` | Copy respects known count; JoinCommun CommunityLogo from emblem → proxy → Branding → GUI |
| `src/.../Utils/BrandLogoApplier.luau` | Skip descendants of `16-JoinCommunPrompt` |
| `src/.../Constants/Config.luau` | MEMBER_INFO_URL default, BODY_NO_COUNT, fail TTL |
| `src/.../Config/ConfigBootstrap.luau` | Map `MemberInfoUrl` → MEMBER_INFO_URL |
| `src/.../KitProduct.luau` | KitVersion `2.4.5` |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` | Pertahankan; optional merge `JoinCommunity.MemberInfoUrl` if custom proxy needed |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.5` |
| `docs/releases/2.4.5/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.5` |