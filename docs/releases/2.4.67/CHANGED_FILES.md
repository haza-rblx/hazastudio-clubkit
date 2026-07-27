# Changed Files — v2.4.66 → v2.4.67

## Summary
- MusicCatalog script seed + ClubKitConfig toggle
- Breaking: **no**
- Git tag: `v2.4.67`

## Core — replace via source sync

| Path | Change |
|------|--------|
| `src/.../KitProduct.luau` | KitVersion `2.4.67` |
| `src/.../Shared/Config/ClubKitConfigSchema.luau` | `Features.MusicCatalogSeed` |
| `src/.../Shared/Config/ConfigBootstrap.luau` | FeatureFlags map |
| `src/.../Shared/Constants/Config.luau` | `MusicCatalogSeedEnabled` + catalog consts |
| `src/.../Server/Services/MusicCatalogSeeder.luau` | **new** — boot merge |
| `src/.../Server/Services/MusicService.luau` | wire seeder after `loadAll` |
| `src/.../Server/Repositories/MusicRepository.luau` | `getTrackTombstones`, `bulkSeed.syncSource`, playlist visibility |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Pertahankan — merge/fill-forward `Features.MusicCatalogSeed` |
| `Hazastudio_ClubKitConfig/MusicCatalog.luau` | **new template** — copy jika place belum punya; jangan timpa isi buyer |
| `Secrets` | Pertahankan |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/.../plugin/ClubKitManifest.luau` | `2.4.67` |
| `CLUB_KIT_SETUP.md` | MusicCatalog docs |
| `docs/releases/2.4.67/**` | Upgrade notes |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | `2.4.67` |
