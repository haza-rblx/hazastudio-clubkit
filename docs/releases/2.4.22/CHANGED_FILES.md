# Changed Files — v2.4.21 → v2.4.22

## Summary
- Settings payload limit + HTTP admission/neg-cache + identity/groups backpressure
- Breaking: no (soft: temporary fallbacks during neg-cache TTL)

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/.../Config.luau` | Settings.MAX_PAYLOAD_BYTES; HttpApi admission knobs |
| `src/ReplicatedStorage/.../Validator.luau` | checkSizeLimit |
| `src/ReplicatedStorage/.../Cache.luau` | get() ignores negative markers |
| `src/ReplicatedStorage/.../HttpApi.luau` | neg-cache, admission, no waiter retry |
| `src/ReplicatedStorage/.../LeaderboardIdentity.luau` | no legacy double-API |
| `src/ReplicatedStorage/.../KitProduct.luau` | 2.4.22 |
| `src/ServerScriptService/.../SettingsController.luau` | Settings size limit |
| `src/ServerScriptService/.../OverheadService.luau` | getGroups neg-cache, no fallthrough retry |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| ClubKitConfig / Secrets | Keep |

## Tools / docs

| Path | Change |
|------|--------|
| VERSION / ClubKitManifest | 2.4.22 |
| CHANGELOG / docs/releases/2.4.22/* | Release notes |
