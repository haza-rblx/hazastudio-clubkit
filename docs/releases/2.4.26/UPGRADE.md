# Upgrade v2.4.25 → v2.4.26

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Hotfix: strip UTF-8 BOM from `KitProduct.luau` (and Manifest) that blocked kit boot on 2.4.25 after Update Engine

## Breaking

Tidak ada.

## QA

- [ ] Kit 2.4.26
- [ ] No `U+feff` / KitProduct parse error
- [ ] Server + client Main boot normally
