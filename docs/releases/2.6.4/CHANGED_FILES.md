# Changed Files — v2.6.3 → v2.6.4

## Summary

| Metric | Value |
|--------|-------|
| Files changed | 9 |
| Breaking | no |

New `CASH` currency option. Ship via **Update Engine (source sync)**.

## Core — replace via Update Engine

| Path | Type | Summary |
|------|------|---------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | mod | `KitVersion` → 2.6.4 |
| `.../Shared/Domain/CashCurrencyDomain.luau` | mod | new `CASH` preset (neutral "Cash" labels) |
| `.../Shared/Config/ClubKitConfigSchema.luau` | mod | schema comment documents `CASH` option |

## Buyer-owned — review manually, do not replace

| Path | Action |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **Template** comment documents `CASH`. Live buyer config fill-forwarded — never overwritten. |

## Tools / docs only

| Path | Summary |
|------|---------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | currency dropdown gains `Cash (neutral)` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → 2.6.4 |
| `VERSION` | 2.6.4 |
| `CHANGELOG.md` | `[Unreleased]` → `[2.6.4]` |
| `UPGRADE_PROGRESS.md` | unreleased table reset |
| `docs/releases/2.6.4/` | this release folder |
