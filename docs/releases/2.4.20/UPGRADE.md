# Upgrade v2.4.19 → v2.4.20

**Tanggal:** 2026-07-13

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- Fix leaderboard LoadingOverlay stacked/ghost text (client no longer runs a second loading animation when server paints)
- Music library scroll/search much lighter: identity row recycle, 1 redraw/frame, fixed-height titles, search debounce, list covers at 150×150 rbxthumb

## Breaking / behavior changes

- Virtual music track titles are single-line truncated (no 1/2-line auto height) — intentional for scroll perf
- None for ClubKitConfig / Secrets / remotes / DataStore

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | — | No required merge |
| Buyer `Secrets` | — | No required merge (trim API tokens if license Auth header errors) |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.20** after Update Engine
- [ ] LoadingOverlay: one cycling message, no stacked double text
- [ ] Music Request library: smooth scroll; search not remounting every keystroke
- [ ] Add-to-queue click matches visible track
- [ ] ClubKitConfig + Secrets unchanged
