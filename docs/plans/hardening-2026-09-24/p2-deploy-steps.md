# P2 (VPS routes for the kit) — deploy steps

Source: `C:\Users\haza\Desktop\ClubKit v2.7.0 Delivery\clubkit-infra` (local checkout, uncommitted).
Plan: `docs/plans/production-hardening-2026-09-24.md` §C/§D, phase P2. Same procedure as P0
(`p0-deploy-steps.md`): `/opt/clubkit` is not git, migrations are additive and applied on boot.
Nothing below has been run. **VPS** = over ssh as a sudo user; `$VPS` = your ssh target.
No command prints a secret: game secrets go into shell variables and are `unset` after the smoke test.

Tests (local, 2026-09-24): `node --experimental-sqlite --test test/api.test.js test/event-board.test.js
test/hardening.test.js test/p2.test.js` → 102/102 green. `test/p2.test.js` migrates its DB **without
0024**, like prod. Bun is not installed on the dev PC, so the Bun path is only exercised on the VPS
(the `db.js` change is two small hooks; watch the journal after restart).

## 0. What ships (and what must NOT)

| File | Kind |
|---|---|
| `apps/api/migrations/0027_p2_query_indexes.sql` | new, additive — 3 indexes, no table/column change |
| `apps/api/src/lib/query-cache.js` | new — per-game cash index + leaderboard + event-board caches |
| `apps/api/src/lib/player-lookup.js` | new — `players/lookup` parsing + response |
| `apps/api/src/lib/request-guards.js` | new — game/IP token buckets, `secret_in_query` log |
| `apps/api/src/db.js` | changed — `onWrite` hook (caches drop on writes) |
| `apps/api/src/lib/rate-limit.js` | changed — `take()` also returns `retryAfterSec` (additive) |
| `apps/api/src/config.js` | changed — `GAME_RATE_LIMIT_*`, `IP_RATE_LIMIT_MODE`, `*_IP_RATE_LIMIT_PER_MIN` |
| `apps/api/src/app.js` | changed — IP guard on /api + /webhook, v1 cached reads + guard + secret log |
| `apps/api/src/routes/v2-routes.js` | changed — `GET players/lookup`, `has_commands`, cached cash/leaderboards, guard + secret log |
| `apps/api/src/routes/v3-routes.js` | changed — `POST players/lookup`, constant-time secret compare, guard + secret log |
| `apps/api/src/routes/social-routes.js` | changed — Bearer or `?secret=` (either), constant-time, batch helper, in-flight dedup, guard |
| `apps/api/src/routes/owner-routes.js` | changed — `deliveryCountsFor` replaces `DELIVERY_COUNTS_SQL` |
| `apps/api/src/routes/event-routes.js` | changed — 50/50 caps, SQL due filter, cached board |

**Do NOT ship:** `apps/api/src/lib/license-routes.js` (its beacon INSERT needs the 0024 `detail`
column; prod has no 0024), `apps/api/migrations/0024_*.sql`, `apps/api/src/lib/discord.js`,
anything under `apps/dashboard` or `apps/brm-api`, `apps/api/.env.example` (reference only).
Nothing in P2 imports anything new from `license-routes.js` or reads a 0024 column.

**Known non-P2 hunks you will see in the staged diff (local work already written before P2):**
- `owner-routes.js`: SSE keepalive 25 s → 8 s, and `GET /api/owner/leaderboard?limit=` (≤ 500, default 50).
  Both additive and harmless. If prod already has them, they do not show.
- `v3-routes.js`: `djs` passed through in the music library response, and the event-board route.
  Both additive. The event-board hunk must already be on prod (0025 is live); if it shows, stop and check.
Any other hunk that is not listed here or in the table = prod has a hand patch → stop and merge.

## 1. Pre-checks (VPS, read-only)

```bash
cd /opt/clubkit/apps/api
sqlite3 /var/lib/clubkit/db.sqlite "SELECT name FROM _migrations ORDER BY name DESC LIMIT 3;"   # expect 0026, 0025, 0023 — no 0024, no 0027
ls src/routes/event-routes.js src/lib/event-board.js src/lib/rate-limit.js src/lib/retention.js   # all present (event board + P0)
grep -c "export function wibToday" src/lib/event-board.js                                         # 1 (event-routes imports it)
grep -c "export function secretEquals" src/lib/auth.js                                            # 1 (P0)
grep -E '^(GAME_RATE_LIMIT|IP_RATE_LIMIT|API_IP|WEBHOOK_IP)' .env || echo "no P2 keys: defaults = log mode"
```

## 2. Package and upload (your PC, Git Bash)

```bash
cd "C:/Users/haza/Desktop/ClubKit v2.7.0 Delivery/clubkit-infra"
tar -czf p2.tgz \
  apps/api/migrations/0027_p2_query_indexes.sql \
  apps/api/src/lib/query-cache.js apps/api/src/lib/player-lookup.js apps/api/src/lib/request-guards.js \
  apps/api/src/db.js apps/api/src/lib/rate-limit.js apps/api/src/config.js apps/api/src/app.js \
  apps/api/src/routes/v2-routes.js apps/api/src/routes/v3-routes.js apps/api/src/routes/social-routes.js \
  apps/api/src/routes/owner-routes.js apps/api/src/routes/event-routes.js
tar -tzf p2.tgz | grep -E 'license-routes|0024|discord|dashboard|brm-api' && echo "STOP: forbidden file in the tarball"
scp p2.tgz $VPS:/tmp/
```

## 3. Backup first + stage (VPS)

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ); echo $TS          # write it down for the rollback
sudo -u clubkit sqlite3 /var/lib/clubkit/db.sqlite ".backup '/var/lib/clubkit/backups/pre-p2-$TS.sqlite'"
sudo -u clubkit sqlite3 /var/lib/clubkit/backups/pre-p2-$TS.sqlite 'PRAGMA integrity_check;'   # ok
sudo mkdir -p /root/p2-rollback-$TS
for f in apps/api/src/db.js apps/api/src/lib/rate-limit.js apps/api/src/config.js apps/api/src/app.js \
         apps/api/src/routes/v2-routes.js apps/api/src/routes/v3-routes.js apps/api/src/routes/social-routes.js \
         apps/api/src/routes/owner-routes.js apps/api/src/routes/event-routes.js; do
  sudo install -D -p /opt/clubkit/$f /root/p2-rollback-$TS/$f
done
rm -rf /tmp/p2 && mkdir /tmp/p2 && tar -xzf /tmp/p2.tgz -C /tmp/p2
grep -rlI $'\r' /tmp/p2 && echo "CRLF found — fix before installing"
for f in apps/api/src/db.js apps/api/src/lib/rate-limit.js apps/api/src/config.js apps/api/src/app.js \
         apps/api/src/routes/v2-routes.js apps/api/src/routes/v3-routes.js apps/api/src/routes/social-routes.js \
         apps/api/src/routes/owner-routes.js apps/api/src/routes/event-routes.js; do
  diff -u /opt/clubkit/$f /tmp/p2/$f | less        # every hunk = P2, or one of the known hunks in §0
done
```

## 4. Install + restart (VPS)

```bash
REF=/opt/clubkit/apps/api/src/app.js
for f in apps/api/migrations/0027_p2_query_indexes.sql \
         apps/api/src/lib/query-cache.js apps/api/src/lib/player-lookup.js apps/api/src/lib/request-guards.js \
         apps/api/src/db.js apps/api/src/lib/rate-limit.js apps/api/src/config.js \
         apps/api/src/routes/social-routes.js apps/api/src/routes/owner-routes.js apps/api/src/routes/event-routes.js \
         apps/api/src/routes/v2-routes.js apps/api/src/routes/v3-routes.js apps/api/src/app.js; do
  sudo cp /tmp/p2/$f /opt/clubkit/$f && sudo chown --reference=$REF /opt/clubkit/$f && sudo chmod 644 /opt/clubkit/$f
done
sudo systemctl restart clubkit-api
journalctl -u clubkit-api -n 30 --no-pager     # expect "applied migration 0027_p2_query_indexes.sql" and "listening on http://127.0.0.1:3000 (bun)"
sqlite3 /var/lib/clubkit/db.sqlite "SELECT name FROM sqlite_master WHERE name IN ('idx_deliveries_donation_status','idx_donations_game_voided','idx_venue_quests_game_due');"   # 3 rows
```

## 5. Smoke (VPS, loopback; secrets stay in variables)

```bash
B=http://127.0.0.1:3000; K=thebasic
S=$(sqlite3 /var/lib/clubkit/db.sqlite "SELECT secret FROM games WHERE game_key='$K'")
SS=$(sqlite3 /var/lib/clubkit/db.sqlite "SELECT social_secret FROM games WHERE game_key='$K'")
curl -s $B/health; echo
# old routes, unchanged shapes
curl -s -o /dev/null -w 'v1 ping %{http_code}\n' "$B/game/$K?action=ping&secret=$S"
curl -s -H "Authorization: Bearer $S" "$B/game/$K/v2/players/1/cash?username=x" | head -c 200; echo
curl -s -H "Authorization: Bearer $S" "$B/game/$K/v2/leaderboards?limit=3" | head -c 200; echo
curl -s -H "Authorization: Bearer $S" "$B/game/$K/v2/notifications?limit=1" | grep -o '"has_commands":[a-z]*'   # new field
curl -s -o /dev/null -w 'event-board %{http_code}\n' -H "Authorization: Bearer $S" "$B/game/$K/v3/event-board"
# new routes
curl -s -H "Authorization: Bearer $S" "$B/game/$K/v2/players/lookup?ids=1,2&usernames=a,b&want=cash,group,connections"; echo
curl -s -X POST -H "Authorization: Bearer $S" -H 'content-type: application/json' \
     -d '{"userIds":[1,2],"want":["cash"]}' "$B/game/$K/v3/players/lookup"; echo
curl -s -o /dev/null -w 'lookup >50 %{http_code}\n' -H "Authorization: Bearer $S" "$B/game/$K/v2/players/lookup?ids=$(seq -s, 1 51)"   # 422
# social: Bearer now works on its own
curl -s -o /dev/null -w 'social bearer %{http_code}\n' -H "Authorization: Bearer $SS" "$B/social/game/$K/social/1"   # 200
unset S SS
journalctl -u clubkit-api -f      # a few minutes: kits polling, no 5xx, no crash loop
```

Also open the customer dashboard once (Live feed, DLQ, Event page): the delivery badges and counts must
look the same as before (compacted old donations may now show their true recipient count).

## 6. After deploy — what to watch

- **Rate limits are log-only** (`GAME_RATE_LIMIT_MODE=log`, `IP_RATE_LIMIT_MODE=log`). After ~7 days:
  `journalctl -u clubkit-api --since -7d | grep -c '\[rate\] rate_limited'` and look at which games/IPs.
  If only abuse (or nothing) shows, set `GAME_RATE_LIMIT_MODE=enforce` / `IP_RATE_LIMIT_MODE=enforce` in
  `.env` and restart. Defaults: 600/min per server (key + `Roblox-Game-Id`), 6000/min per game,
  `/social` separate, 600/min per IP on `/api`, 60/min per IP on `/webhook`.
- **Who still sends `?secret=`** (input for P5): one line per game per route family (v1/v2/v3/social) per hour:
  `journalctl -u clubkit-api --since -7d | grep secret_in_query | awk '{for(i=1;i<=NF;i++) if($i~/^game=|^route=/) printf "%s ",$i; print ""}' | sed 's#route=\([a-z0-9]*\)/.*#\1#' | sort | uniq -c`
- Event board: a venue already over 50 posts or 50 quests keeps them; only a new create answers
  `422 too_many_posts` / `too_many_quests` (the dashboard shows the error text).

## 7. Rollback

```bash
TS=<timestamp from step 3>
for f in $(cd /root/p2-rollback-$TS && find apps -type f); do sudo cp -p /root/p2-rollback-$TS/$f /opt/clubkit/$f; done
sudo rm -f /opt/clubkit/apps/api/src/lib/query-cache.js /opt/clubkit/apps/api/src/lib/player-lookup.js \
           /opt/clubkit/apps/api/src/lib/request-guards.js
#   0027 stays applied and its file may stay: three indexes, the old code simply does not use them.
sudo systemctl restart clubkit-api
journalctl -u clubkit-api -n 20 --no-pager
```

Kits are unaffected by a rollback: old kits never call the new routes, and a P3 kit falls back to the
per-user routes when `players/lookup` answers 404.

## 8. API contract for the kit (P3)

All routes authenticate with the game secret (`Authorization: Bearer <DonationApiSecret>`; `?secret=`
still accepted until P5 but logged). Licence-gated like the rest of v2/v3.

**`GET /game/<key>/v2/players/lookup?ids=1,2,3[&usernames=a,,c][&want=cash,group,connections][&groupId=N]`**
**`POST /game/<key>/v3/players/lookup`** body
`{ "userIds": [1,2,3], "usernames": { "1": "a" }, "want": ["cash","groupRank","connections"], "groupId": N }`
(or `"users": [{ "user_id": 1, "username": "a" }]`). ≤ 50 distinct ids, else `422 {ok:false,error:"too_many_ids_max_50"}`;
none valid → `422 validation_failed — ids required`. `want` defaults to all three; aliases `groupRank`/`group_rank`
→ group, `social`/`connectionsCount` → connections. `usernames` are positional in GET (Roblox names have no commas).

```json
{ "ok": true, "server_time": 1790000000,
  "players": [
    { "user_id": 1, "username": "a",
      "cash_total": 50000, "cash_rank": 3,
      "group": { "ok": true, "rankId": 10, "roleName": "Member", "roleId": "555", "fetchedAt": 1790000000.1, "stale": false, "fromCache": true },
      "connectionsCount": 42 } ] }
```
- `cash_total`/`cash_rank`: identical to `GET /v2/players/<id>/cash?username=` (rank `null` when total is 0).
  The username matters: most donors match by name, not by a donor link.
- `group`: identical body to `/social/game/<key>/groups/<id>`; failures are
  `{ok:false,error:"groups_disabled"|"group_id_required"|"roblox_unavailable"|"pending"}`. `pending` = not
  resolved within 3 s; it keeps resolving server-side — ask again later (it will be cached, 300 s fresh / 900 s stale).
- `connectionsCount`: the value the kit pushed via `POST /social/.../social/<id>`, or `null`.
- Only requested fields are present. Players come back in request order.

**`GET /game/<key>/v2/notifications`** gains `"has_commands": true|false` (a pending `game_commands` row exists).
`/v2/commands` is unchanged.

**429 (only once enforce is on):** `{ok:false,error:"rate_limited",retry_after:N}` + `Retry-After: N`.
The per-server bucket keys on `Roblox-Game-Id` (JobId), else `Roblox-Id` (PlaceId), else the game key alone.
Roblox game servers are documented to add these headers to HttpService requests, but this has **not** been
checked against our own traffic yet — until it is, assume servers of one place may share a bucket (log mode
makes that visible as `server=-` or a repeated place id in the `[rate]` lines).
