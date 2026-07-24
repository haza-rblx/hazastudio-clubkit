# Upgrade v2.4.65 → v2.4.66

**Tanggal:** 2026-07-24

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- Empty release / version bump only for engine sync. No feature or bug fix changes.

## Breaking / behavior changes

- None.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | - | No required merge |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.66** after Update Engine
- [ ] F9 KitVersion **2.4.66**
- [ ] ClubKitConfig + Secrets unchanged by Update Engine
