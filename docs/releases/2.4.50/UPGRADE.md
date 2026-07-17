# Upgrade v2.4.49 → v2.4.50

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place

## What's new

### Added
- **Bubble height tune** — `/height` (alias `/bh`, `/bubbleheight`):
  - `/height` — show current factor/extra/nudge
  - `/height -0.5` — lower bubble (nudge studs; can be negative)
  - `/height factor 0.25` — set HEIGHT_FACTOR
  - `/height reset` — clear local overrides

### Changed
- **Loading intro** — black screen + logo held at least **5s**; fast boot no longer skips early.
- **Chat bubble default** — `HEIGHT_FACTOR` 0.25, `EXTRA_STUDS` 0.

## Config changes

Engine only (`Config.Loading.INTRO_MIN_DURATION`, `Config.ChatBubble`). No buyer `ClubKitConfig` fields.

## QA setelah upgrade

- [ ] Join: black + logo stays ~5s before cinematic/main loading
- [ ] Bubble closer to overhead top; `/height -0.5` lowers further; chat to verify
- [ ] `/height reset` restores default
