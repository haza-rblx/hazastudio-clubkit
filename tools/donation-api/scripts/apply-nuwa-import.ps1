# Push nuwa Saweria history SQL to production D1, then verify leaderboard is non-empty.
# Run from tools/donation-api after: npx wrangler login

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$sqlFile = "backups\nuwa-saweria-transaction-import-2026-01-2026-05.sql"
if (-not (Test-Path $sqlFile)) {
    Write-Error "Missing $sqlFile — run import-saweria-transaction-xlsx.py first."
}

Write-Host "Checking game nuwa exists in remote D1..."
npx wrangler d1 execute donation_db --remote --command "SELECT id, game_key, name FROM games WHERE game_key = 'nuwa';"

Write-Host "Donation count BEFORE import:"
npx wrangler d1 execute donation_db --remote --command "SELECT COUNT(*) AS donation_count FROM donations WHERE game_id = (SELECT id FROM games WHERE game_key = 'nuwa');"

Write-Host "Applying import SQL (288 donations)..."
npx wrangler d1 execute donation_db --remote --file=$sqlFile

Write-Host "Donation count AFTER import:"
npx wrangler d1 execute donation_db --remote --command "SELECT COUNT(*) AS donation_count FROM donations WHERE game_id = (SELECT id FROM games WHERE game_key = 'nuwa');"

Write-Host "Done. Open leaderboard in browser:"
Write-Host "https://hazastudio-donation-api.hazastudio.workers.dev/game/nuwa?secret=YOUR_SECRET&action=leaderboard&type=alltime&limit=5"
