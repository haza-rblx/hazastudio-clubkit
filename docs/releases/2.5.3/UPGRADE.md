# Upgrade v2.5.2 → v2.5.3

## Quick steps
1. Studio → ClubKit plugin → **Settings → Update plugin** (if outdated)
2. Studio → ClubKit plugin → **Engine → Update Engine** → Save place
3. If you ever used engine zone mode: delete any `MusicZone`-tagged parts from the place (harmless leftovers if unused)

`ClubKitConfig` / `Secrets` are never fully replaced. No new config keys in this release.

## What's new
- **Music is global-only** — one server-wide session; every player hears the same track
- Removed vestigial zone mode (`Music.MODE`, `ZoneTrackerService`, `MusicZoneChanged`, client zone handlers)

## Config changes
| Key | Notes |
|-----|--------|
| _(none)_ | Buyer `ClubKitConfig` unchanged (never had zone keys) |

## Breaking
- Engine `Config.Music.MODE = "zone"` no longer exists. If you edited engine `Config.luau` for zone mode, remove that and delete `MusicZone`-tagged parts. Normal buyer places (global music / `ClubKitConfig` only) are unaffected.

## QA after upgrade
- [ ] F9 / KitVersion shows **2.5.3**
- [ ] All players hear the same track (join mid-song syncs)
- [ ] Request / vote skip / DJ / Manage still work
- [ ] No `MusicZoneChanged` / `not_in_zone` errors in output
- [ ] Optional: place has no leftover `MusicZone` tags
