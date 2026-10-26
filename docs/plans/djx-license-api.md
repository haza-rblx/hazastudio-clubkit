# djX licence API — VPS design (ADR 0022, build half 1)

Status: **built 2026-10-26 in clubkit-infra** (`test/djx.test.js` 19/19); not deployed.

Built deviations:
- A revoked code on activate/redeem → `revoked`.
- IP limits use `rate-limit.js` `clientIp` (the last XFF hop, which cannot be spoofed).
- The Discord embed is Club Kit shaped, so its "Game key" field carries `djX <license_id> · <download_id>`.
- The admin list adds `has_secret`. To be built in `clubkit-infra/apps/api` (Bun + SQLite, same process as the Club Kit API). The in-game client already exists: `dj-booth/src/server/Services/LicenseApi.luau`. This design matches the contract that file expects.

## Why separate tables

Club Kit licences live on `games` (one row per `game_key`, the secret pasted into `Secrets.luau`). djX has no game key and no pasted secret. A licence is a **sale**, and the venue gets its secret only by activating. `license_beacons.game_id` is a `NOT NULL` FK to `games`, so djX gets its own beacon table. It reuses `queueBeaconAlert` for Discord.

## Migration `0030_djx_licenses.sql`

```sql
CREATE TABLE djx_licenses (
  id              TEXT PRIMARY KEY,            -- "lic_" + 16 base32; what Stamp.licenseId carries
  kind            TEXT NOT NULL CHECK (kind IN ('full','guest')),
  status          TEXT NOT NULL DEFAULT 'unused'
                  CHECK (status IN ('unused','active','revoked')),
  dev             INTEGER NOT NULL DEFAULT 0,  -- owner's own places; excluded from sales stats
  code_hash       TEXT NOT NULL UNIQUE,        -- sha256(code); the plaintext is shown once at creation
  code_hint       TEXT NOT NULL DEFAULT '',    -- last 4 chars, for support
  duration_s      INTEGER,                     -- guest only, default 604800
  buyer_roblox_id TEXT NOT NULL DEFAULT '',
  note            TEXT NOT NULL DEFAULT '',
  -- binding, set on activate/redeem
  universe_id     TEXT NOT NULL DEFAULT '',
  place_id        TEXT NOT NULL DEFAULT '',
  creator_id      TEXT NOT NULL DEFAULT '',
  creator_type    TEXT NOT NULL DEFAULT '',
  activated_by    TEXT NOT NULL DEFAULT '',    -- the Roblox user id that pasted it
  activated_at    TEXT NOT NULL DEFAULT '',
  expires_at      INTEGER,                     -- unix seconds; guest = activated + duration_s
  secret_hash     TEXT NOT NULL DEFAULT '',    -- sha256(secret); the venue holds the plaintext in its DataStore
  last_verify_at  TEXT NOT NULL DEFAULT '',
  last_download_id TEXT NOT NULL DEFAULT '',
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE UNIQUE INDEX idx_djx_licenses_secret ON djx_licenses(secret_hash) WHERE secret_hash <> '';
CREATE INDEX idx_djx_licenses_universe ON djx_licenses(universe_id);

CREATE TABLE djx_beacons (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  license_id   TEXT NOT NULL DEFAULT '',  -- from the request (file stamp) or the matched code
  reason       TEXT NOT NULL,             -- code_used | license_mismatch | universe_mismatch | owner_mismatch | revoked
  universe_id TEXT NOT NULL DEFAULT '', place_id TEXT NOT NULL DEFAULT '',
  creator_id  TEXT NOT NULL DEFAULT '', creator_type TEXT NOT NULL DEFAULT '',
  user_id     TEXT NOT NULL DEFAULT '', download_id TEXT NOT NULL DEFAULT '',
  fingerprint TEXT NOT NULL DEFAULT '',
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX idx_djx_beacons_created ON djx_beacons(created_at DESC);
```

`djx_downloads` (per-download stamp log) is ADR 0023 work and is **not** in this migration. Until then, `download_id`/`fingerprint` are only logged.

## Codes and secrets

- **Code:** `DJX-` + 40 base32 chars (≈200 bits), or `DJXG-…` for a guest pass. It is long and pasted (ADR 0022 item 8). Only `sha256` is stored. The plaintext is returned once by the admin create call.
- **Secret:** 32 random bytes, base64url, issued on activate/redeem and stored as `sha256`. A re-activation of the same code from the **same** universe + owner issues a fresh secret and invalidates the old one. This covers a wiped DataStore or a reinstall.
- Times on the wire are unix seconds. That is what `LicensePolicy` uses.

## Game endpoints — `/djx/v1/*`

All are `POST` with a JSON body. The body is `identity()` from `LicenseApi`: `universe_id, place_id, creator_id, creator_type, license_id, download_id, fingerprint`. Replies are `{ ok: true, … }` or `{ ok: false, error }`.

The client treats only these errors as **definitive**: `invalid_code, code_used, license_mismatch, universe_mismatch, owner_mismatch, revoked, expired`. Everything else (5xx, `rate_limited`, `validation_failed`) reads as *unreachable*, and the 7-day grace applies. So the server must never return a definitive error for a transient problem.

| Route | Extra body | Checks, in order | Success reply |
|---|---|---|---|
| `/activate` | `code, user_id` | universe ≠ 0 → code exists, `kind='full'`, not revoked → **owner** (below) → **file match** (below) → unused, *or* already bound to this universe + owner | `kind:"full", license_id, secret` |
| `/redeem` | `code, user_id` | same, but `kind='guest'`, no file match, and the universe has no active full licence (else `invalid_code`); sets `expires_at = now + duration_s` once (a re-redeem keeps the original end) | `kind:"guest", license_id, secret, expires_at` |
| `/verify` | `Authorization: Bearer <secret>` | secret_hash found → not revoked → universe and creator equal the binding → guest not past `expires_at` | `kind, license_id, expires_at?, next_check_seconds: 1800` |

**Error mapping:**
- unknown code → `invalid_code`
- unknown secret → `revoked` (the venue's key was rotated or dropped)
- bound elsewhere → `code_used` + beacon
- guest past its end → `expired`

**Owner check:** on a `User` place, `user_id` must equal `creator_id`, else `owner_mismatch`. On a `Group` place, the VPS trusts the game server's `Roles.isOwner` gate. A Roblox groups-API rank check is an optional later hardening.

**File match (two layers, ADR 0022 item 12):**
- A full code is accepted only when the request's `license_id` equals the code's licence id, else `license_mismatch` + beacon naming `download_id`.
- Unstamped files (`license_id = "TEMPLATE"`) are accepted **only for `dev` licences** (decision 1).

**Rate limits:** reuse `createFailureCounter`. Count only failed `activate`/`redeem` attempts: 10 per 10 min per universe and 30 per 10 min per IP (Roblox egress IPs are shared, so the IP budget stays loose). Over the limit → `rate_limited` (non-definitive). Verify gets a token bucket per secret (6/min).

**Beacons:** `code_used`, `license_mismatch`, `universe_mismatch` and `owner_mismatch` write a `djx_beacons` row and call `queueBeaconAlert` with `product: "djx"`. Throttle 1 per hour per (license_id, universe).

## Admin endpoints — `/admin/djx/*` (master `ADMIN_TOKEN`, like `/admin/games`)

| Route | Does |
|---|---|
| `POST /admin/djx/licenses` `{kind, dev?, duration_days?, buyer_roblox_id?, note?, count?}` | create 1..50 codes; returns the plaintext codes **once** |
| `GET /admin/djx/licenses?status=&kind=&q=` | list (no hashes) |
| `PATCH /admin/djx/licenses/:id` `{status?, note?, rebind?: true, rotate?: true}` | `revoked` locks immediately; `rebind` clears the binding + secret → back to `unused`, so the owner re-activates with the same code (e.g. the place moved to a group); `rotate` clears the secret only → the venue gets `revoked` and re-activates |
| `GET /admin/djx/beacons?license_id=` | leak log |

The dashboard "create code" button calls the first route. Account login (ADR 0023) later adds owner-scoped reads. Nothing here changes Club Kit routes.

## Files

- `apps/api/migrations/0030_djx_licenses.sql`
- `apps/api/src/lib/djx-license.js` (codes, hashing, checks; pure where possible)
- `apps/api/src/routes/djx-routes.js` (`/djx/v1/*` + `/admin/djx/*`, mounted in `app.js` before `/game`)
- `apps/api/test/djx.test.js` (node:test, same harness as `api.test.js`)
- Caddy: `api.hazastudio.id` already proxies everything to the API, so no change is needed. Verify on deploy.

## Decided (owner, 2026-10-26)

1. **Unstamped files work with dev codes only.** A sold full code on a `TEMPLATE` file → `license_mismatch`. Consequence: **stamped downloads (ADR 0023) must ship before djX full codes are sold.** Guest passes skip the file match, so trials work on any file.
2. **Codes stored as hash only.** A lost code → revoke it and issue a new one.
3. **The server refuses a guest pass on a venue that already has an active full licence** (`invalid_code`), so the code is not burned and can go to someone else.
