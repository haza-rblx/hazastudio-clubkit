# Donation API

Central IDR donation bridge (Saweria + Bagi-Bagi) that replaces per-game Google Apps Script deployments.

## Local Quick Start (Just Works)

From this folder:

```bash
npm install
npm run local:migrate
npm run local:up
```

Keep that terminal running. Open admin panel at:

`http://127.0.0.1:4173`

Default local credentials are prefilled:

- API base: `http://127.0.0.1:8787`
- token: `local-dev-admin-token`

Generate one ready-to-copy game endpoint:

```bash
npm run local:ready
```

Output includes:

- `SAWERIA_WEBHOOK=...`
- `BAGIBAGI_WEBHOOK=...`
- `API_URL=...` (Club Kit `Donation.ApiUrl`, no secret)
- `DONATION_API_SECRET=...` (Club Kit `Secrets.DonationApiSecret`)
- `ROBLOX_V2_BASE=...`
- `CONFIG_LINE_ApiUrl=...` / `CONFIG_LINE_Secret=...`
- `ROBLOX_URL=...` (legacy v1, secret embedded)

Optional seed bootstrap in same command:

```bash
LOCAL_SEED_NAME=bebear_e0 LOCAL_SEED_AMOUNT=5100000 npm run local:ready
```

PowerShell equivalent:

```powershell
$env:LOCAL_SEED_NAME="bebear_e0"; $env:LOCAL_SEED_AMOUNT="5100000"; npm run local:ready
```

## Web Quick Start (Cloudflare)

- Worker API: `https://hazastudio-donation-api.hazastudio.workers.dev`
- Admin panel (web): `https://hazastudio-donation-admin.pages.dev`

Generate one game + endpoints from terminal (copy-paste):

```powershell
$env:ADMIN_TOKEN="<your-admin-token>"
$env:GAME_ID="rust-main"
$env:GAME_NAME="Rust Main"
npm run prod:ready
```

Optional manual seed in same command:

```powershell
$env:SEED_NAME="bebear_e0"
$env:SEED_AMOUNT="5100000"
npm run prod:ready
```

Output includes:

- `SAWERIA_WEBHOOK=...`
- `BAGIBAGI_WEBHOOK=...`
- `API_URL=...` (Club Kit `Donation.ApiUrl`, no secret)
- `DONATION_API_SECRET=...` (Club Kit `Secrets.DonationApiSecret`)
- `ROBLOX_V2_BASE=...`
- `CONFIG_LINE_ApiUrl=...` / `CONFIG_LINE_Secret=...`
- `ROBLOX_URL=...` (legacy v1, secret embedded)

## Cloudflare Worker Migration

- Worker source: `src/worker.js`
- D1 migrations: `migrations/`
- Wrangler config: `wrangler.toml`

### Deploy to Cloudflare

1. `npx wrangler login`
2. `npx wrangler d1 create donation_db`
3. Put returned DB id into `wrangler.toml` `database_id`
4. `npx wrangler secret put ADMIN_TOKEN`
5. Set `PUBLIC_BASE_URL` in `wrangler.toml` to your Worker URL
6. `npm run cf:d1:migrate:remote`
7. `npm run cf:deploy`
8. `npm run panel:build`
9. `npm run panel:deploy:web`

## Deploy Fast

1. Create a Railway project.
2. Add a PostgreSQL database.
3. Deploy this folder as a Node service.
4. Set env vars from `.env.example`.
5. Open `/health`.

If `BOOTSTRAP_GAME_KEY=rust` is set, the first deploy creates one game automatically.

## Generate Game

```bash
curl -X POST "$API_BASE/admin/games" \
  -H "authorization: Bearer $ADMIN_TOKEN" \
  -H "content-type: application/json" \
  -d "{\"id\":\"rust\",\"display_name\":\"Rust Warehouse\"}"
```

Response:

```json
{
  "ok": true,
  "game": { "id": "rust", "...": "..." },
  "endpoints": {
    "saweria_webhook": "https://.../webhook/saweria/rust/wh_...",
    "bagibagi_webhook": "https://.../webhook/bagibagi/rust/wh_...",
    "roblox_poll": "https://.../game/rust?secret=rbx_..."
  }
}
```

Use `saweria_webhook` in Saweria. Use `bagibagi_webhook` in Bagi-Bagi dashboard
(Settings → Webhook URL).

**Club Kit v1.3 config** (recommended — secret separate from URL):

```lua
-- ClubKitConfig.luau
Donation.ApiUrl = "https://.../game/rust"   -- from endpoints.roblox_base / API_URL

-- Secrets.luau
Secrets.DonationApiSecret = "rbx_..."       -- from DONATION_API_SECRET
```

`npm run prod:ready` / `local:ready` now prints `CONFIG_LINE_ApiUrl` and
`CONFIG_LINE_Secret` for copy-paste. Do **not** paste `roblox_poll` (URL with
embedded secret) into `ApiUrl` — that causes double `?secret=` on every request.

Legacy v1 games can still use `roblox_poll` as `SHEETS_WEB_APP_URL`.

## API v2 (Club Kit architecture)

REST routes under `/game/:gameKey/v2/`. Same D1 data as v1; v1 `?action=` routes
stay available for backward compatibility.

**Auth:** `?secret=rbx_...` **or** `Authorization: Bearer rbx_...`

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/game/:key/v2/health` | Ping + version |
| GET | `/game/:key/v2/leaderboards?boards=alltime,daily&limit=10` | Both boards in one call |
| GET | `/game/:key/v2/notifications?cursor=&limit=50` | Cursor-based poll (no `since` drift) |
| GET | `/game/:key/v2/players/:userId/cash?username=` | Donor cash stats |
| GET | `/game/:key/v2/donor-links` | List provider ↔ Roblox links |
| PUT | `/game/:key/v2/donor-links` | `{ "provider_name", "roblox_username" }` |

**Notifications cursor:** response includes `next_cursor` (opaque). Store it server-side
and pass back on the next poll — fixes the v1 millisecond `since` loop bug.

**Leaderboards:** rows include `roblox_username` / `roblox_user_id` when linked.

Source: `src/v2-routes.js`, shared queries in `src/game-data.js`.

### Bagi-Bagi webhook payload

Bagi-Bagi typically POSTs flat JSON:

```json
{ "name": "Donatur", "amount": 10000, "message": "pesan" }
```

The API maps `name` → donor, `amount` → IDR, and synthesizes a dedupe id
(`bb:donor:amount:timestamp`) when no transaction id is present.

Test locally:

```bash
curl -X POST "http://127.0.0.1:8787/webhook/bagibagi/<gameKey>/<webhook_token>" \
  -H "content-type: application/json" \
  -d '{"name":"TestUser","amount":10000,"message":"hello"}'
```

For future agents and repeat game setup, see `AGENT_HANDOFF.md`.

## Roblox Compatibility

The API intentionally keeps the Google Apps Script response shape:

- `GET /game/:gameKey?secret=...&action=ping`
- `GET /game/:gameKey?secret=...&action=leaderboard&type=alltime&limit=100`
- `GET /game/:gameKey?secret=...&action=leaderboard&type=daily&limit=100`
- `GET /game/:gameKey?secret=...&action=notifications&since=0`
- `GET /game/:gameKey?secret=...&action=namemap`
- `POST /game/:gameKey?secret=...` with `{ "action": "namemap_set", ... }`

Donations are stored durably and deduplicated by Saweria transaction id per game.

### `since` parameter — backward-compatible dual format

The notifications endpoint accepts **two formats** for the `since` parameter.
Games that haven't been updated still work without any code change.

| Format | Example | Used by |
|--------|---------|--------|
| **ISO 8601** (recommended) | `2026-06-06T12:00:00.000Z` | NUWA (updated DonationService) |
| **Unix timestamp** (legacy) | `1749200000` | Gudang Timur, older games |

> Internally `received_at` is stored as ISO 8601 text in D1 (SQLite) with
> millisecond precision (e.g. `2026-06-06T12:00:01.500Z`). When the worker
> detects the format of `since`, it normalises it to ISO before the SQL
> comparison and applies a cursor advance offset to prevent infinite loops.

#### Precision problem (why a single donation could loop forever)

The notification response returns `unix_timestamp` as **whole seconds**
(truncated from `received_at` which has millisecond precision). When the
DonationService sends this truncated value back as `since` on the next poll,
the conversion to ISO produces e.g. `12:00:01.000Z`. But the original donation
at `12:00:01.500Z` is STILL greater than `12:00:01.000Z`, so the same donation
is returned on every poll — **infinite notification loop**.

**Fix implemented in the worker:**

| Input format | Offset applied | Result example |
|-------------|---------------|----------------|
| Unix timestamp | `+1 second` | `1749200101` → `2026-06-06T12:00:02.000Z` |
| ISO string | `+1 millisecond` | `2026-06-06T12:00:01.000Z` → `2026-06-06T12:00:01.001Z` |

This ensures the `d.received_at > ?` filter cleanly skips past the last
notification and the loop stops. Both old (Unix timestamp) and new (ISO)
games are covered server-side — no per-game code change required.

#### Why both formats exist
- The original Railway (Node.js) worker expected Unix timestamps.
- After migrating to Cloudflare Workers + D1, `received_at` became ISO strings.
- Updating every game's DonationService at once is impractical.
- The worker now auto-detects which format is sent and handles both.

#### Updating a game to use ISO (optional)
Change the notification poll in `DonationService.luau`:

```diff
- local url = buildUrl("notifications", "since=" .. tostring(lastNotifTimestamp))
+ local sinceIso = os.date("!%Y-%m-%dT%H:%M:%S.000Z", lastNotifTimestamp)
+ local url = buildUrl("notifications", "since=" .. sinceIso)
```

This is optional — the worker handles both formats automatically.

## Club Kit license (v1.3+)

Per-game license lives on the `games` row (`migration 0008_license.sql`).

| Field | Meaning |
|-------|---------|
| `license_enforced` | `0` = legacy (no verify yet). `1` = Club Kit v1.3+ has booted and verified. |
| `license_status` | `active` · `grace` · `expired` · `revoked` |
| `universe_id` | Locked on first `POST /game/:key/v2/license/verify` |

**Backward compatibility:** games with `license_enforced = 0` keep full v2 API access unless
`license_status` is explicitly `revoked` or `expired`. Older kit builds without
`LicenseEnforcementEnabled` never call verify.

**Game boot (Club Kit v1.3+):**

```http
POST /game/{gameKey}/v2/license/verify
Authorization: Bearer rbx_...
Content-Type: application/json

{"universe_id":123,"place_id":456,"job_id":"...","kit_version":"1.3.0","build_id":"20260706"}
```

**Admin:**

```http
GET  /admin/games/{gameKey}/license
PATCH /admin/games/{gameKey}/license
{"license_status":"revoked","license_note":"...","maintenance_until":"2026-08-09T00:00:00.000Z"}
{"rebind":true}   # clear universe bind for trusted-client transfer
```

Admin panel: **Settings → Club Kit license**.

Deploy migration: `npm run cf:d1:migrate:remote`

## Import Saweria history (XLSX / CSV)

**Transaction Report** export from Saweria wallet (`.xlsx` with columns `Transaction ID`, `Sender Username`, …):

```bash
pip install openpyxl
python scripts/import-saweria-transaction-xlsx.py nuwa path/to/report.xlsx backups/nuwa.import.sql
```

Keeps `transaction` + `Debit` rows (incoming donations); skips withdrawals.

**Classic Saweria CSV** (`created_at`, `donator_name`, `type=donation`, …):

```bash
node scripts/import-saweria-csv.mjs nuwa path/to/export.csv backups/nuwa.import.sql
```

Apply to production D1 (requires `wrangler login`):

```bash
npx wrangler d1 execute donation_db --remote --file=backups/nuwa.import.sql
```

Game key `nuwa` must already exist (`npm run prod:ready` with `GAME_ID=nuwa`). Re-running import SQL is idempotent (`ON CONFLICT` upsert).
