# Upgrade v2.4.51 → v2.4.52

## Quick steps

1. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
2. Save & publish place

## What's new

### Fixed
- **Chat tag intermittently Guest** — chat tags now use the same overhead cache as the GUI (plus last-known-good), so CoOwner / VVIP / Staff no longer randomly show as Guest while leaderstats stay correct.

### Changed
- **Chat bubble calmer on head movement** — attachment on `HumanoidRootPart` (no neck pitch / look-down drift).
- **Music panel tab** — `Request` → `Library`.

### Added (dev tool only)
- **CarryAnimUploaderPlugin** — local Studio plugin under `tools/CarryAnimUploaderPlugin/` (not part of engine sync).

## Config changes

Engine only (`Config.ChatBubble.ADORNEE_PART`, `Config.Music.TAB_LABELS.reqSong`). No buyer `ClubKitConfig` fields required.

## QA setelah upgrade

- [ ] CoOwner / VVIP / Staff / chat tags match leaderstats right after join (chat before any donation/respawn)
- [ ] Rejoin / respawn several times — tags stay correct, no Guest flicker
- [ ] Chat bubble stays stable when looking down (does not pitch with head)
- [ ] Music panel tab shows **Library** (not Request)
