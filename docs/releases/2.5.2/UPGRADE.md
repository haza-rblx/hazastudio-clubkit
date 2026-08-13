# Upgrade v2.5.1 → v2.5.2

## Quick steps
1. Studio → ClubKit plugin → **Settings → Update plugin** (if outdated)
2. Studio → ClubKit plugin → **Engine → Update Engine** → Save place
3. Optional config (fill-forward after Update Engine, or set manually):
   - `Branding.DiscordInvite` — Top Menu Discord chip (e.g. `discord.gg/your-invite`)
4. Optional: rewrite `MusicCatalog` to grouped `playlists = { { name = "...", tracks = { ... } } }` (flat list still works)

`ClubKitConfig` / `Secrets` are never fully replaced. New schema keys fill-forward additively.

## What's new
- **Gravity** — controlled idle-down drop scaled by dial + soft landing (no bury into floor)
- **License** — verify timeout no longer disables cash donation polling
- **Couples** — chat tag clears on breakup; partner title shows on accept (`Taken`)
- **MusicCatalog** — grouped playlists (no per-line `playlistName`)
- **Top Menu Discord** — `Branding.DiscordInvite` drives chip text + open browser
- **Mobile** — Admin Hub / JoinCommun phone UIScale
- **Plugin** — Carry Upload + patch button no longer nil-Text crash
- **Docs** — Roles & Ranks slide guide

## Config changes
| Key | Notes |
|-----|--------|
| `Branding.DiscordInvite` | New (default `""`). Empty hides Top Menu Discord chip. |
| `MusicCatalog.playlists[].tracks` | Preferred seed shape (template updated). Legacy `tracks` + `playlistName` still OK. |

## Breaking
- None.

## QA after upgrade
- [ ] `/gravity 1` vs `/gravity 10` feel different; idle-down (not fall anim); soft land
- [ ] Cash donations still poll if license verify is slow/fails in Studio
- [ ] Couple accept → partner title; breakup → chat tag clears for both
- [ ] Top Menu Community shows Discord invite from config; click opens browser
- [ ] MusicCatalog grouped seed merges without duplicating (additive)
- [ ] Admin Hub / JoinCommun readable on phone layout
- [ ] Plugin → Carry → Upload + patch (no Text nil error) after plugin update
