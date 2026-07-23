# Upgrade v2.4.64 → v2.4.65

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place
3. QA: star a dance mid-list — position & scroll stay; Favorites tab still shows favs

`Secrets` / `ClubKitConfig` tidak diganti — engine-only.

## What's new
- **Dance favorite keep position** — starring no longer jumps the emote to the top / rebuilds Dance/Pose list
- Favorites tab remains the dedicated fav list

## Config changes
Tidak ada.

## Breaking
Tidak ada.

## QA setelah upgrade
- [ ] Tab Dance: star emote di tengah list — badge on, scroll & urutan tetap
- [ ] Tab Favorites: emote muncul di sana
- [ ] Unstar di Favorites — hilang dari tab itu; di Dance hanya badge off
- [ ] F9 KitVersion **2.4.65**
