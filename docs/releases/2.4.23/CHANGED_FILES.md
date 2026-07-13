# Changed Files — v2.4.22 → v2.4.23

## Summary
- Interest radius Phase 2 (55 enter / 15 hysteresis) + legacy kill switch
- Breaking: soft (farther players lose interest sooner)

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/.../Config.luau` | Interest 55/15 + USE_LEGACY_VIEW_RANGE |
| `src/ServerScriptService/.../ProximityInterestService.luau` | Legacy resolve + log leaveRadius |
| `src/ReplicatedStorage/.../KitProduct.luau` | 2.4.23 |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| ClubKitConfig / Secrets | Keep |

## Tools / docs

| Path | Change |
|------|--------|
| VERSION / ClubKitManifest | 2.4.23 |
| CHANGELOG / docs/releases/2.4.23/* | Release notes |
