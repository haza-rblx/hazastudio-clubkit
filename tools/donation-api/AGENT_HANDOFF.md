# Donation API Agent Handoff

Use this when another agent needs to reuse the central Saweria donation API for a new Roblox game.

## Current Production

- Cloudflare Worker: `hazastudio-donation-api`
- API base URL: `https://hazastudio-donation-api.hazastudio.workers.dev`
- Admin panel: `https://hazastudio-donation-admin.pages.dev`
- Service folder: `THE BASIC CLUB KIT v1.1/tools/donation-api`
- Roblox integration keeps the legacy GAS-compatible config name:
  `Config.Donation.SHEETS_WEB_APP_URL`

The API intentionally supports the same actions as the old Google Apps Script bridge:

- `GET /game/:gameKey?secret=...&action=ping`
- `GET /game/:gameKey?secret=...&action=leaderboard&type=alltime&limit=100`
- `GET /game/:gameKey?secret=...&action=leaderboard&type=daily&limit=100`
- `GET /game/:gameKey?secret=...&action=notifications&since=0`
- `GET /game/:gameKey?secret=...&action=namemap`
- `POST /game/:gameKey?secret=...` with `{ "action": "namemap_set", ... }`
- `POST /webhook/saweria/:gameKey/:webhookSecret`
- `POST /webhook/bagibagi/:gameKey/:webhookSecret` (same token; flat `{ name, amount, message }` payload)

## Add a New Game

Fastest (uses helper script):

```powershell
$env:ADMIN_TOKEN="<admin-token>"
$env:GAME_ID="client-game-key"
$env:GAME_NAME="Client Game Name"
npm run prod:ready
```

The response returns:

- `SAWERIA_WEBHOOK`: paste into Saweria dashboard webhook URL.
- `BAGIBAGI_WEBHOOK`: paste into Bagi-Bagi dashboard webhook URL (NUWA uses Bagi-Bagi branding in-game).
- `ROBLOX_URL`: paste into Roblox `Config.Donation.SHEETS_WEB_APP_URL`.

Game keys should be lowercase and stable, for example `rust`, `club-alpha`, or
`clientname-main`.

## Roblox Changes Needed Per Game

Minimal change:

```lua
Config.Donation.SHEETS_WEB_APP_URL = "<robloxEndpoint from admin/games>"
```

Make sure the target game has the URL builder patch in `DonationService.luau`:

```lua
local separator = if string.find(base, "?", 1, true) then "&" else "?"
local url = base .. separator .. "action=" .. action
```

Without this patch, URLs that already contain `?secret=...` become invalid.

## Notes

### `since` parameter — dual format

The notifications endpoint accepts both ISO 8601 (recommended) and Unix timestamps.
Older games (Gudang Timur, etc.) still send Unix timestamps — the worker auto-detects
and converts. See `README.md` for details.

New games should use ISO 8601 format in `DonationService.luau`:

```lua
local sinceIso = os.date("!%Y-%m-%dT%H:%M:%S.000Z", lastNotifTimestamp)
local url = buildUrl("notifications", "since=" .. sinceIso)
```

## What Not To Do

- Do not create a new Google Sheet or Apps Script for each game.
- Do not expose `ADMIN_TOKEN` to Roblox or Saweria.
- Do not reuse one game's `robloxEndpoint` in another game.
- Do not remove donation dedupe. Donations are deduped by `provider_tx_id` per game.

## Suggested User Prompt For Future Agents

```text
Use the existing central donation API in THE BASIC CLUB KIT v1.1/tools/donation-api.
Add a new game called <Game Name> with gameKey <game-key>.
Generate the Saweria webhook URL and Roblox endpoint using npm run prod:ready.
Then update this game's Config.Donation.SHEETS_WEB_APP_URL to the returned robloxEndpoint.
Do not create Google Apps Script or Google Sheets.
Verify /health, action=ping, action=leaderboard, and action=notifications.
```
