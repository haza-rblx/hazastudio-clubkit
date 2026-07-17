# Upgrade v2.4.50 → v2.4.51

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place

## What's new

### Changed
- **Chat bubble default height** — `Config.ChatBubble.NUDGE_STUDS = -0.5` (nilai yang pas dari tune `/height -0.5`). `/height` tetap bisa override lokal.

## Config changes

Engine only. No buyer `ClubKitConfig` fields.

## QA setelah upgrade

- [ ] Bubble sits just above overhead top without large gap (no need to `/height` first)
- [ ] `/height reset` returns to nudge -0.5
