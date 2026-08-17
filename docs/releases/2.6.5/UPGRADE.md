# Upgrade v2.6.4 → v2.6.5

## Quick steps
1. **Update Engine** via the Club Kit plugin (Settings → Update plugin if prompted → Engine → Update Engine). Engine updates ship via source sync; no RBXM needed.
2. Your `ClubKitConfig.luau` and `Secrets.luau` are **never replaced**. The new `Features.MusicReadOnlyLibrary` key is fill-forwarded automatically (additive) after the update — existing values are preserved.
3. Save the place.

## What's new

### Fixed — real cash donations now show the real total and update the Cash leaderstat
Previously, a donation that arrived via the external webhook (Bagibagi) played the notification but the small chip always read **"Total: First donation"**, and the donor's **Cash leaderstat never updated** — even for donors with real history in the backend. Manual donations (`/fakecash`, Admin Hub) always worked, which is why testing looked fine. Two engine bugs on the webhook path caused this; both are fixed. No action needed — existing donors' correct totals will show on the next server session / donation.

### Added — Read-only music library mode
New optional toggle `ClubKitConfig.Features.MusicReadOnlyLibrary`:
- `false` (default) = **Editable** — today's behavior, unchanged.
- `true` = **Read-only** — the music library never touches DataStore (fast boot, no DataStore errors). The library comes from your `MusicCatalog` script + songs requested in-game (kept in memory only, lost on restart). The Manage tab is hidden for everyone (the DJ tab hides too, same permission gate). Any playlists you previously saved in DataStore are **not deleted** — they simply don't appear while read-only is on, and show up again if you switch back to editable.

Use it for venues that don't need in-game music editing and want the fastest, error-free boot.

## Config changes
| Key | Where | Default | Meaning |
|-----|-------|---------|
| `Features.MusicReadOnlyLibrary` | `ClubKitConfig.luau` | `false` | `true` = read-only music library (no DataStore). Fill-forwarded automatically. |

`Config.Donation.SKIP_API_FOR_UNKNOWN_DONORS` (engine-level, not buyer-edited) is now a legacy no-op — safe to leave in old configs.

## QA after upgrade
1. Boot the place → confirm the donation notif for a **real** (webhook) donation shows the donor's real total on the chip (not "First donation"), and their Cash leaderstat updates.
2. (Optional) Set `Features.MusicReadOnlyLibrary = true` → boot → confirm: no DataStore music read in logs, library loads from MusicCatalog, Manage tab hidden. Set back to `false` → confirm your old playlists reappear.
