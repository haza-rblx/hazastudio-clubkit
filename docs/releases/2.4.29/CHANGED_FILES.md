# Changed Files — v2.4.28 → v2.4.29

## Summary
- One-shot displayName heal + verified metadata flag
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `Shared/Utils/LeaderboardIdentity.luau` | Verified skip; write-back hook; HttpApi fetch |
| `Server/.../DonationController.luau` | Session-deduped heal write-back |
| `Server/.../DonationLeaderboardRepository.luau` | `displayNameVerified` + `healUserDisplayName` |
| `Server/.../AvatarLikeRepository.luau` | Persist/surface verified |
| `KitProduct.luau` | Version 2.4.29 |
| `tools/.../ClubKitManifest.luau` | KIT_VERSION 2.4.29 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig.luau` | Keep |
| `Secrets.luau` | Keep |

## Tools / docs only

| Path | Change |
|------|--------|
| `tools/OneTimeLeaderboardSeeder/...` | Seed with verified=true |
| `CHANGELOG.md` / `docs/releases/2.4.29/` | Release notes |
| `VERSION` | 2.4.29 |
