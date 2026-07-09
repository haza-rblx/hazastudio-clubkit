# Import full Saweria history for `nuwa`

Goal: **288 donations** in D1 → leaderboard + notifications history in game.

Web URL is the **checklist** (same data Roblox polls). When web shows donors, game is fed.

## Path A — D1 SQL (recommended, one shot)

1. SQL file already generated:
   `backups/nuwa-saweria-transaction-import-2026-01-2026-05.sql`

2. Cloudflare Dashboard → **D1** → **donation_db** → **Console**  
   Paste/run the file, **or** terminal:

```powershell
cd tools/donation-api
npx wrangler login
# Add account_id to wrangler.toml if wrangler asks
npx wrangler d1 execute donation_db --remote --file=backups/nuwa-saweria-transaction-import-2026-01-2026-05.sql
```

3. Verify (browser):

`https://hazastudio-donation-api.hazastudio.workers.dev/game/nuwa?secret=YOUR_SECRET&action=leaderboard&type=alltime&limit=5`

Must **not** be `[]`.

## Path B — Admin API (no wrangler, needs deploy once)

1. Deploy worker (includes `import-donations`):

```powershell
npm run cf:deploy
```

2. Export JSON from Excel:

```powershell
python scripts/import-saweria-transaction-xlsx.py nuwa "C:\path\to\report.xlsx" --json-out backups/nuwa-donations.json
```

3. Push:

```powershell
$env:ADMIN_TOKEN="<from Cloudflare Worker secrets>"
node scripts/push-full-donation-history.mjs nuwa backups/nuwa-donations.json
```

## After import

- Play server in Studio → wait one leaderboard poll (~2 min) or `/refreshleaderboard all`
- Saweria board + posters should match web totals
- New live donations still arrive via Saweria webhook (no re-import needed)

## Not enough: seed-only script

`push-nuwa-leaderboard-seed.py` only sets **totals per donor** (legacy_seed).  
For **full transaction history**, use Path A or B.
