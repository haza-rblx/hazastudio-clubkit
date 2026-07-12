# Upgrade v2.4.15 ? v2.4.16

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio ? Club Kit Packager ? **Check Update** ? **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- Empty release / version bump only for engine sync. No feature or bugfix changes.

## Breaking / behavior changes

- None.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | - | No required merge |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.16** after Update Engine
- [ ] ClubKitConfig + Secrets unchanged by Update Engine
