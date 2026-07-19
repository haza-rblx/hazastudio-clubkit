# Upgrade v2.4.59 → v2.4.60

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only. `ClubKitConfig` / `Secrets` tidak diganti.

## What's new
- **`/re` tidak lagi stuck di SpawnLocation** — restore posisi production-grade: single-flight (hindari race CharacterAdded ganda), tunggu PartsReady + character di world (+ AppearanceLoaded bila ada), pending sampai pivot sukses, re-assert jika spawn engine menimpa PivotTo.

## Config changes
Tidak ada.

## Breaking
Tidak ada.

## QA setelah upgrade
- [ ] `/re` berkali-kali di dance floor / jauh dari spawn → tetap di posisi
- [ ] Overhead + dance restore masih OK setelah `/re`
- [ ] F9 banner KitVersion **2.4.60**
