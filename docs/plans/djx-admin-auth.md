# djX admin login + release device grant — build contract

Status: **built 2026-10-26**, tested end-to-end on a local API. Steps covered: `lune run tools/release` → approve in the page as master → upload → sha256 match. Deny and the result states are checked in the browser.

The Origin check compares hosts: behind Caddy the app sees `http://`, while browsers send `https://`. Production still needs a master user, created with `scripts/seed-master.js` and your own password. The owner wants a proper login instead of pasting `ADMIN_TOKEN`.

## 1. Admin page uses the existing master login

- The existing pieces are `owner_users` (role `master`), `POST /api/auth/login`, `GET /api/auth/me` and `POST /api/auth/logout`. The session cookie is HttpOnly and lasts 7 days. `authMiddleware` already sets `req.user` before the router reaches `/admin/djx/*`.
- **Who passes `/admin/djx/*`:** `assertAdmin` (ADMIN_TOKEN, kept for scripts) **or** `req.user?.role === "master"`. An `owner` role gets 403 `forbidden`.
- **CSRF:** the cookie is `Domain=.hazastudio.id; SameSite=Lax`, so other subdomains count as same-site.
  - A cookie-authenticated `POST/PUT/PATCH/DELETE` must carry an `Origin` header equal to the request URL's own origin. Anything else → 403 `bad_origin`.
  - Requests authenticated by bearer (`ADMIN_TOKEN` or a grant) skip this check.
- **Local testing:** `cookieDomainAttr()` reads `process.env.COOKIE_DOMAIN`.
  - Unset → `.hazastudio.id` (today's behaviour).
  - `"none"` → no Domain attribute (host-only), so `http://localhost` works.

## 2. Release device grant (like `gh auth login`)

Table `djx_device_grants` (migration `0032_djx_device_grants.sql`):

```sql
CREATE TABLE djx_device_grants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_hash TEXT NOT NULL UNIQUE,     -- sha256(device_code), the script's secret
  user_code   TEXT NOT NULL UNIQUE,     -- "ABCD-1234", shown to the human
  scope       TEXT NOT NULL,            -- only 'template_upload' today
  client      TEXT NOT NULL DEFAULT '', -- e.g. "dj-booth release.luau"
  version     TEXT NOT NULL DEFAULT '', -- the template version it wants to upload
  sha256      TEXT NOT NULL DEFAULT '', -- of the file it wants to upload
  size        INTEGER NOT NULL DEFAULT 0,
  ip          TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','denied','used','expired')),
  approved_by TEXT NOT NULL DEFAULT '', -- owner_users.username
  grant_hash  TEXT NOT NULL DEFAULT '', -- sha256(grant), set when the script collects it
  expires_at  INTEGER NOT NULL,         -- unix s; request 10 min, grant 10 min from collection
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
```

- **User code:** 8 chars from `BCDFGHJKLMNPQRSTVWXZ23456789` (no vowels, no 0/1) shown as `XXXX-XXXX`.
- **Device code:** 32 bytes base64url. **Grant:** `djxg_` + 32 bytes base64url.

| Route | Auth | Does |
|---|---|---|
| `POST /djx/v1/device` `{scope, client, version, sha256, size}` | none; per-IP limit 10 / 10 min (failure-counter style, every call counts) | creates a pending row; returns `{ok, device_code, user_code, verification_url: <origin>/admin/djx/ui#approve=<user_code>, interval: 3, expires_in: 600}`. `scope` must be `template_upload`; `version` must match the template version rule; `sha256` must be 64 hex |
| `POST /djx/v1/device/token` `{device_code}` | the device code | `pending` → 400 `authorization_pending`; `denied` → 403 `access_denied`; past expiry → 400 `expired_token` (and status `expired`); `approved` → mints the grant, stores its hash, sets status `used`, `expires_at = now+600`, returns `{ok, grant, expires_in: 600}`. A second collect → 400 `expired_token` |
| `GET /admin/djx/device/:user_code` | **master session only** (not ADMIN_TOKEN: a human must approve) | the row, without hashes |
| `POST /admin/djx/device/:user_code/approve` and `/deny` | master session + Origin check | only from `pending` and not expired; sets `approved_by` |

- **Using the grant:** `PUT /admin/djx/template` also accepts `Authorization: Bearer djxg_…`.
  - The grant must exist, have scope `template_upload`, be unexpired, and be unused.
  - The uploaded body's sha256 and the `x-djx-version` header must equal what the device request declared. Otherwise → 403 `grant_mismatch`.
  - On success the grant is burned: `grant_hash` is cleared.
  - A grant passes no other admin route.

## 3. Admin page (`src/static/djx-admin.html`)

- The token form is replaced by **username + password**:
  1. `POST /api/auth/login` (with `credentials: "same-origin"`).
  2. `GET /api/auth/me`, which must return role `master`. Otherwise show "This account can't manage djX." and log out.
- On load, `GET /api/auth/me` decides whether to show the login or the app. Sign out → `POST /api/auth/logout`.
- All fetches use `credentials: "same-origin"`, with no Authorization header. A 401 shows the login again.
- **Approve screen:**
  - When the URL hash is `#approve=CODE`, after login show a focused card instead of the app: "Approve a djX release upload?".
  - It lists the code (big, mono), client, version, size, sha256 (short), the requesting IP and the age.
  - Buttons: Approve (primary) and Deny.
  - Afterwards it shows "Approved. You can go back to the terminal." and a link into the app, then clears the hash.
  - An unknown or expired code shows an error state.

## 4. Release script (`dj-booth/tools/release.luau`, Lune)

`lune run tools/release [--api <base>]`. The default API is `https://api.hazastudio.id`, overridable by the env var `DJX_API`. Steps:

1. Run `lune run tests/run`, `selene src` and `stylua --check src tests`. Stop on any failure.
2. Run `bash tools/build.sh` (which also packages `build/djx-template.rbxm`).
3. Check the template: it starts with `<roblox!`, its size is between 100 KB and 8 MB, and the version comes from `wally.toml`.
4. `POST /djx/v1/device` with scope, client, version, sha256 and size. Print the URL + code, and try to open the browser (`cmd /c start "" <url>` on Windows, `open` on macOS, `xdg-open` on Linux).
5. Poll `/device/token` every `interval` seconds until it is approved, denied or expired.
6. `PUT /admin/djx/template` with the grant + version. Compare the returned sha256 with the local one.
7. Print `released djX <version> (<size> KB, sha256 <first 12>)`.

The script never stores the grant. It holds no password and no `ADMIN_TOKEN`.
