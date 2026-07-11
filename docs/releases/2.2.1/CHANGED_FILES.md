# Changed Files — v2.2.0 → v2.2.1

## Summary

- Scope: Split oversized MusicPlayerUIBinder for Roblox Source limit
- Breaking: no
- Git tag: `v2.2.1`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../UI/MusicPlayerUIBinder.luau` | Trimmed entry (~141k); applies Part2 |
| `src/.../UI/MusicPlayerUIBinderPart2.luau` | **Added** — late methods (~126k) |
| `src/.../KitProduct.luau` | KitVersion `2.2.1` |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| `ClubKitConfig` / `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../ClubKitManifest.luau` | `2.2.1` |
| `docs/releases/2.2.1/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` | `2.2.1` |
