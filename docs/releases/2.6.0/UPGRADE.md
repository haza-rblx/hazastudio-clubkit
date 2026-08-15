# Upgrade v2.5.3 → v2.6.0

**Date:** 2026-08-16

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

`ClubKitConfig` and `Secrets` are never replaced by Update Engine. Missing config keys are **fill-forwarded automatically** (plugin Sources patch + runtime `ConfigBootstrap`), so the two new keys below appear with safe defaults — no manual merge needed unless you want to change them.

RBXM flow (fresh installs only): export/import RBXM via the Packager, then restore buyer config/secrets.

## What's new

- **External Admin Bridge (optional)** — sync Club Kit staff roles one-way to **Adonis** or **Kohl's** (`ClubKitConfig.ExternalAdmin.Provider`), and run `:cksetrole` / `:ckgift` / `:ckannounce` (Adonis) or `;ck...` (Kohl's) through Club Kit permission gates. Membership and Spender roles are never synced. Requires the optional place-pack `extras/place-packs/ExternalAdminBridge/` (manual inject — not part of Engine sync). See `docs/adr/0003-external-admin-bridge.md`.
- **`Announcement.MinMembership`** — buyer gate for free `/announce` + free broadcast panel (`Tier1`/VIP, `Tier2`/VVIP, `Tier3`/Supreme). Default stays VVIP+. Staff / Leadership and top spenders remain free.
- **Workspace boards show top 50** — cash, Robux, community, and likes boards paint 50 rows (was 10/20). Fetch/cache still capped at 100. Overhead tags and join greetings unchanged.

## Fixes

- **AFK auto-rejoin could silently never teleport** — rejoin now uses `TeleportAsync` with a `TeleportInitFailed` watcher (async failures were previously invisible), client retries up to 3× per idle streak, and transient denials no longer burn the 15-minute rate window. `/rejoin` fixed the same way.
- **DJ effect sliders + toggles crackle** — DSP nodes are created once per sound and mutated in place; toggles flip `Enabled` instead of destroy/recreate.
- **ConfigBootstrap boot fix** — `MinMembership` resolves without requiring `OverheadDomain` (was recursive require → kit failed to boot).

## Config changes (fill-forwarded, nothing to do)

| Field | Change |
|-------|--------|
| `Announcement.MinMembership` | NEW — `"Tier2"` default (VVIP+). Set `"Tier1"` / `"Tier2"` / `"Tier3"` to retune the free-announce gate. |
| `ExternalAdmin.Provider` | NEW — `"None"` default. `"Adonis"` / `"Kohls"` only if you install the optional bridge place-pack. |

Engine-only (not buyer-facing): `AfkGuard.TELEPORT_INIT_TIMEOUT_SEC`, `AfkGuard.CLIENT_RETRY_BACKOFF_SEC`, `AfkGuard.MAX_CLIENT_ATTEMPTS`.

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] Kit boots (no ConfigBootstrap error in output)
- [ ] `/announce` as a VVIP member works (default gate unchanged)
- [ ] AFK rejoin: idle past the threshold → player actually teleports back; test twice in a row
- [ ] DJ: drag effect sliders + flip toggles while music plays → no crackle
- [ ] Workspace cash/Robux boards paint up to 50 rows
- [ ] (Only if bridge installed) `:cksetrole` via Adonis respects Club Kit permission gates
