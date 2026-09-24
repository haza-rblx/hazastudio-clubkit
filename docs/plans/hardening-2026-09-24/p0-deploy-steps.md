# P0 (VPS safety) — deploy steps

Source: `C:\Users\haza\Desktop\ClubKit v2.7.0 Delivery\clubkit-infra` (local checkout, uncommitted).
Plan: `docs/plans/production-hardening-2026-09-24.md` §D/§E, phase P0.
Nothing below has been run. Commands marked **VPS** run over ssh as a sudo user; `$VPS` = your ssh target.
No command here prints a secret; the only credential-handling steps (rclone token, SESSION_SECRET) print lengths or nothing.

## 0. What ships (and what must NOT)

Ship exactly these files (paths relative to the repo root):

| File | Kind |
|---|---|
| `apps/api/src/app.js` | changed — webhook idempotency/limits, v1 licence gate, timing-safe compares, awaited dispatcher, body cap (keeps the Discord release-announcement patch) |
| `apps/api/src/config.js` | changed — HOST default 127.0.0.1, body/webhook/retention env keys, `bootConfigProblems` |
| `apps/api/src/server.js` | changed — SESSION_SECRET boot refusal, Bun `maxRequestBodySize` 2.5 MB + `idleTimeout: 30`, SIGTERM closes DB, daily retention timer |
| `apps/api/src/lib/auth.js` | changed — exported `secretEquals` |
| `apps/api/src/lib/rate-limit.js` | new |
| `apps/api/src/lib/retention.js` | new |
| `apps/api/src/routes/auth-routes.js` | changed — login throttle, constant-time miss, awaited last_login_at |
| `apps/api/src/routes/v2-routes.js` | changed — beacon throttle/dedup, timing-safe secret |
| `apps/api/migrations/0026_donation_delivery_stats.sql` | new, additive (new table + 3 indexes) |
| `apps/api/scripts/prune.js` | new |
| `scripts/backup.sh`, `scripts/verify-backup.sh`, `scripts/backup-cron`, `scripts/backup-restore.md` | changed/new |
| `systemd/clubkit-api.service.d/10-hardening.conf` | new drop-in |
| `caddy/Caddyfile` | reference only — **merge the `log {}` block by hand**, do not copy the file (prod has the `/music/*` handle that the repo copy lacks) |

**Do NOT ship** (uncommitted local work unrelated to P0): `apps/api/src/lib/license-routes.js`
(its beacon INSERT uses the `detail` column from `0024_license_beacon_detail.sql`, which is not on
prod — shipping it would break every beacon), `apps/api/migrations/0024_*.sql`,
`apps/api/src/lib/discord.js`, `apps/api/src/routes/owner-routes.js`, `apps/api/src/routes/v3-routes.js`,
anything under `apps/brm-api` or `apps/dashboard`. P0 was built so none of these are needed.

## 1. Pre-checks (VPS, read-only)

```bash
cd /opt/clubkit/apps/api
# SESSION_SECRET must exist and be >= 32 chars, or the new server refuses to boot. Prints a LENGTH only.
sudo awk 'index($0,"SESSION_SECRET=")==1{v=substr($0,16); gsub(/^["\047]|["\047]$/,"",v); print "SESSION_SECRET length:", length(v)}' .env
#   no output or < 32 -> generate one BEFORE deploying (logs every dashboard user out once):
#   NEW=$(openssl rand -hex 32); sudo sed -i '/^SESSION_SECRET=/d' .env; echo "SESSION_SECRET=$NEW" | sudo tee -a .env >/dev/null; unset NEW
grep -E '^(HOST|PORT|NODE_ENV)=' .env                       # not secrets; HOST=0.0.0.0 here would override the new default
systemctl show clubkit-api -p Environment                    # expect NODE_ENV=production
sqlite3 /var/lib/clubkit/db.sqlite "SELECT name FROM _migrations ORDER BY name DESC LIMIT 3;"   # expect 0025, 0023, 0022 — no 0024/0026
which sqlite3 flock gzip; caddy version
ls -l /var/lib/clubkit/brm/                                   # owner of brm.sqlite (backup runs as clubkit: needs read + write on the dir for -shm)
ss -ltnp | grep -E ':3000|:8787'
```

If `brm.sqlite` is not owned by `clubkit` (and clubkit cannot write in `/var/lib/clubkit/brm/`),
either add clubkit to that group with group-write on the dir, or the backup log will say `brm: .backup FAILED`.

## 2. Package and upload (your PC, Git Bash or PowerShell)

```bash
cd "C:/Users/haza/Desktop/ClubKit v2.7.0 Delivery/clubkit-infra"
tar -czf p0.tgz \
  apps/api/src/app.js apps/api/src/config.js apps/api/src/server.js \
  apps/api/src/lib/auth.js apps/api/src/lib/rate-limit.js apps/api/src/lib/retention.js \
  apps/api/src/routes/auth-routes.js apps/api/src/routes/v2-routes.js \
  apps/api/migrations/0026_donation_delivery_stats.sql apps/api/scripts/prune.js \
  scripts/backup.sh scripts/verify-backup.sh scripts/backup-cron scripts/backup-restore.md \
  systemd/clubkit-api.service.d/10-hardening.conf caddy/Caddyfile
scp p0.tgz $VPS:/tmp/
```

## 3. Backup first + stage (VPS)

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
# DB snapshot before anything changes
sudo -u clubkit sqlite3 /var/lib/clubkit/db.sqlite ".backup '/var/lib/clubkit/backups/pre-p0-$TS.sqlite'"
sudo -u clubkit sqlite3 /var/lib/clubkit/backups/pre-p0-$TS.sqlite 'PRAGMA integrity_check;'      # ok
# Rollback copy of every prod file that will be overwritten
sudo mkdir -p /root/p0-rollback-$TS
for f in apps/api/src/app.js apps/api/src/config.js apps/api/src/server.js apps/api/src/lib/auth.js \
         apps/api/src/routes/auth-routes.js apps/api/src/routes/v2-routes.js \
         scripts/backup.sh scripts/verify-backup.sh; do
  sudo install -D -p /opt/clubkit/$f /root/p0-rollback-$TS/$f
done
sudo cp -p /etc/cron.d/clubkit-backup /etc/caddy/Caddyfile /root/p0-rollback-$TS/
# Stage and review: every hunk should be a P0 hunk (a surprise hunk = prod had a hand patch; stop and merge)
rm -rf /tmp/p0 && mkdir /tmp/p0 && tar -xzf /tmp/p0.tgz -C /tmp/p0
grep -rlI $'\r' /tmp/p0 && echo "CRLF found — fix before installing"
for f in apps/api/src/app.js apps/api/src/config.js apps/api/src/server.js apps/api/src/lib/auth.js \
         apps/api/src/routes/auth-routes.js apps/api/src/routes/v2-routes.js; do
  diff -u /opt/clubkit/$f /tmp/p0/$f | less
done
```

## 4. Install the API (VPS) — order matters

```bash
cd /tmp/p0
REF=/opt/clubkit/apps/api/src/app.js          # ownership reference for new files
for f in apps/api/src/lib/rate-limit.js apps/api/src/lib/retention.js \
         apps/api/migrations/0026_donation_delivery_stats.sql apps/api/scripts/prune.js \
         apps/api/src/lib/auth.js apps/api/src/config.js apps/api/src/routes/auth-routes.js \
         apps/api/src/routes/v2-routes.js apps/api/src/app.js apps/api/src/server.js; do
  sudo cp /tmp/p0/$f /opt/clubkit/$f && sudo chown --reference=$REF /opt/clubkit/$f && sudo chmod 644 /opt/clubkit/$f
done
# systemd hardening drop-in (StartLimitIntervalSec=0, MemoryMax=1G, TimeoutStopSec=15, LimitNOFILE=65536)
sudo install -D -m 644 systemd/clubkit-api.service.d/10-hardening.conf /etc/systemd/system/clubkit-api.service.d/10-hardening.conf
sudo systemctl daemon-reload
sudo systemctl restart clubkit-api
journalctl -u clubkit-api -n 30 --no-pager      # expect "applied migration 0026_donation_delivery_stats.sql", "listening on http://127.0.0.1:3000 (bun)"
systemctl show clubkit-api -p MemoryMax -p StartLimitIntervalUSec -p TimeoutStopUSec
```

If the journal says `refusing to start: SESSION_SECRET …` → fix `.env` (step 1) and `systemctl restart clubkit-api`.
If `.env` has `HOST=0.0.0.0`, change it to `HOST=127.0.0.1` (Caddy and brm-api both use 127.0.0.1:3000) and restart.

Smoke (VPS; secrets go into a shell variable, never printed, and loopback curl does not pass Caddy):

```bash
curl -s http://127.0.0.1:3000/health; echo
K=thebasic; S=$(sqlite3 /var/lib/clubkit/db.sqlite "SELECT secret FROM games WHERE game_key='$K'")
curl -s -o /dev/null -w 'v1 %{http_code}\n' "http://127.0.0.1:3000/game/$K?action=ping&secret=$S"
curl -s -o /dev/null -w 'v2 %{http_code}\n' -H "Authorization: Bearer $S" "http://127.0.0.1:3000/game/$K/v2/health"
curl -s -o /dev/null -w 'v3 %{http_code}\n' -H "Authorization: Bearer $S" "http://127.0.0.1:3000/game/$K/v3/health"
unset S
head -c 3000000 /dev/zero | curl -s -o /dev/null -w 'big %{http_code}\n' -X POST --data-binary @- http://127.0.0.1:3000/game/x/v2/health   # 413
journalctl -u clubkit-api -f      # watch a few minutes: kits polling, no 5xx, no crash loop
```

Retention: the first pass runs 10 min after boot (`journalctl -u clubkit-api -g '\[retention\]'`, one line).
Manual pass any time: `cd /opt/clubkit/apps/api && sudo -u clubkit /usr/local/bin/bun scripts/prune.js`.

Optional, at a quiet hour (5–10 s API downtime; kits retry): switch the DB to incremental auto-vacuum
so the prune actually shrinks the file (until then the summary line says `auto_vacuum=0 (incremental off)`):

```bash
sudo -u clubkit sqlite3 /var/lib/clubkit/db.sqlite ".backup '/var/lib/clubkit/backups/pre-vacuum-$(date -u +%Y%m%dT%H%M%SZ).sqlite'"
sudo systemctl stop clubkit-api
sudo -u clubkit sqlite3 /var/lib/clubkit/db.sqlite 'PRAGMA auto_vacuum=INCREMENTAL; VACUUM; PRAGMA auto_vacuum;'   # last line prints 2
sudo systemctl start clubkit-api
```

## 5. Backups (VPS)

```bash
sudo install -m 755 /tmp/p0/scripts/backup.sh /tmp/p0/scripts/verify-backup.sh /opt/clubkit/scripts/
sudo install -m 644 /tmp/p0/scripts/backup-restore.md /opt/clubkit/scripts/
sudo install -d -o clubkit -g clubkit -m 700 /etc/clubkit
sudo touch /var/log/clubkit-backup.log && sudo chown clubkit:clubkit /var/log/clubkit-backup.log
sudo -u clubkit /opt/clubkit/scripts/backup.sh     # expect db: ok, brm: ok, "offsite: SKIPPED — rclone …" until Drive is set up
sudo install -m 644 /tmp/p0/scripts/backup-cron /etc/cron.d/clubkit-backup      # hourly :17, replaces the daily 04:17 line
```

Then: Google Drive via rclone — `scripts/backup-restore.md` §1 (headless `rclone config`, remote name `gdrive`,
scope `drive.file`, token from `rclone authorize "drive"` on your PC). Then the restore drill, §3 — **the P0 gate
needs one drill passed**. Record it.

## 6. Caddy log redaction + purge (VPS)

```bash
sudo cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.pre-p0
sudoedit /etc/caddy/Caddyfile
#   inside `api.hazastudio.id { … }` replace the whole `log { … }` block with the one from
#   /tmp/p0/caddy/Caddyfile (roll_size 20mb, roll_keep 3, roll_keep_for 336h, format filter with the
#   request>uri regexp + Authorization/Cookie delete). Leave the /music/* handle and everything else as is.
diff -u /etc/caddy/Caddyfile.pre-p0 /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
# Prove the redaction on a harmless request:
curl -s -o /dev/null "https://api.hazastudio.id/health?secret=probe-not-a-secret"
sudo tail -n 1 /var/log/caddy/clubkit-api.log | grep -o '"uri":"[^"]*"'       # -> /health?secret=REDACTED
```

Purge the lines already written with real secrets (owner decision 2). Only after the reload above, so new
lines are clean. This permanently deletes the old access logs:

```bash
ls -la /var/log/caddy/
sudo truncate -s 0 /var/log/caddy/clubkit-api.log
sudo find /var/log/caddy -maxdepth 1 -name 'clubkit-api-*' -print -delete        # rotated .log / .log.gz
sudo grep -rlE 'secret=(rbx|soc)_|/webhook/[a-z]+/[^/]+/wh_' /var/log/caddy/ 2>/dev/null; echo "files still holding secrets: above (expect none)"
sudo zgrep -lE 'secret=(rbx|soc)_' /var/log/caddy/* 2>/dev/null
```

The Caddy purge does not reach copies elsewhere (old VPS snapshots, any log shipped off the box). Game-secret
rotation stays scheduled after P5, as decided.

## 7. After deploy

- 48 h gate: no rise in 5xx (`journalctl -u clubkit-api --since -48h | grep -c ' 500'` is rough; the Caddy log has `"status":5..`), API suite green, drill passed.
- Webhook rate limit is log-only. After ~7 days: `journalctl -u clubkit-api --since -7d | grep -c 'rate_limited'`; if 0 or only abuse, set `WEBHOOK_RATE_LIMIT_MODE=enforce` in `.env` and restart.
- `journalctl -u clubkit-api | grep webhook_conflict` = a provider re-sent a known transaction with a different amount/name; the stored row was kept. Worth a look each time.
- Retention can be tuned or disabled per table in `.env` (`RETENTION_*_DAYS`, `RETENTION_ENABLED=0`) + restart.

## 8. Rollback

```bash
TS=<the timestamp from step 3>
for f in $(cd /root/p0-rollback-$TS && find apps scripts -type f); do sudo cp -p /root/p0-rollback-$TS/$f /opt/clubkit/$f; done
sudo rm -f /opt/clubkit/apps/api/src/lib/rate-limit.js /opt/clubkit/apps/api/src/lib/retention.js /opt/clubkit/apps/api/scripts/prune.js
#   0026 stays applied and its file may stay: the old code never reads the new table (additive).
sudo rm -f /etc/systemd/system/clubkit-api.service.d/10-hardening.conf && sudo systemctl daemon-reload
sudo systemctl restart clubkit-api
sudo cp -p /root/p0-rollback-$TS/clubkit-backup /etc/cron.d/clubkit-backup
sudo cp -p /root/p0-rollback-$TS/Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy   # only if Caddy misbehaves; redaction is harmless to keep
```

Deleted rows (pruned acks/webhook events/beacons/commands, compacted deliveries) come back only from a
backup; the per-donation counts are kept in `donation_delivery_stats`.
