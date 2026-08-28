# Buyer: AFTER HOURS

Status: **donation data migrated to VPS (164/164, ledger backfilled) 2026-08-28. Owner-side TODO remains: repoint BagiBagi webhook + point the place's ApiUrl.** Last touched 2026-08-28.

**Migration applied 2026-08-28:** imported the 2 missing rows (akom1205 111,111 + Baypeachysparkle 100,000) → **164 donations / Rp 18,663,985 / last 2026-08-26T21:36:07Z**, integrity `ok`. Backfilled the 10 donations that had no `notification_deliveries` row (the 2 new + 8 older) as `displayed` → **164/164 displayed**. Backup: `/var/lib/clubkit/backups/db-pre-afterhours-migrate-20260828.sqlite`.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | AFTER HOURS |
| PlaceId | `122751547822026` |
| UniverseId | `10490544868` |
| Game key | `after-hours` (`games.id = 6` on **both** the old worker and the VPS) |
| Donation provider | **BagiBagi** (every `provider_tx_id` is `bagibagi-*`), not Saweria |

## Engine

Unknown / not inspected — the place has not been opened in Studio this session. Both backends report `kit_build_id = 20260712` and `last_seen_at = 2026-07-13T11:39:50Z`, i.e. **the place has not polled either backend since 13 July** while donations kept arriving through 26 August (a webhook does not need the place running). Either the venue is closed or the kit stopped calling home — worth asking the owner before treating anything else as broken.

## Donation backend — reconciliation done 2026-08-28

Old worker (Cloudflare D1 `donation_db`) vs VPS (`/var/lib/clubkit/db.sqlite`), matched on `provider_tx_id`:

| | donations | total | last `donation_at` |
|---|---|---|---|
| Old worker | 164 | Rp 18.663.985 | 2026-08-26T21:36:07Z |
| VPS | 162 | Rp 18.452.874 | 2026-08-20T23:34:38Z |

**2 missing on the VPS, 0 mismatches, nothing on the VPS that the worker lacks.** Both missing rows are from 26 Aug:

- `bagibagi-08f8e897-0395-4f81-6d96-08df034a9384` — akom1205 — 111.111 — "CISSSSS"
- `bagibagi-50d473b1-ca3d-4fcc-6f7b-08df034a9384` — Baypeachysparkle — 100.000 — "Sukses selalu ka wawa dan team,sorry telat datang"

The 162 already on the VPS came from an earlier bulk import (same shape as the 2026-08-22 backfill), not from live traffic — new donations still land in the old worker.

### Prepared, not yet run

Uploaded to the VPS at `/tmp/afterhours_migrate.sh` + `/tmp/afterhours_import.sql`. `/tmp` does not survive a reboot — if the files are gone, both are trivially rebuilt from the two rows listed above (`INSERT OR IGNORE INTO donations (game_id, provider_tx_id, saweria_name, saweria_name_lc, amount, message, status, received_at, donation_at, raw_payload)`; `received_at` = `2026-08-26T08:41:33.556Z` / `2026-08-26T14:36:07.474Z`). The script prints BEFORE, backs up to `/var/lib/clubkit/backups/db-pre-afterhours-migrate-20260828.sqlite`, applies `INSERT OR IGNORE` for the two rows, then prints AFTER + ledger counts + `pragma integrity_check`.

Run (the write is blocked by the permission classifier from inside the agent session — the user runs it):

```
ssh --% root@103.42.244.55 "sed -i 's/\r$//' /tmp/afterhours_migrate.sh; bash /tmp/afterhours_migrate.sh"
```

Expected after: **164 / Rp 18.663.985 / last `2026-08-26T21:36:07Z`**, integrity `ok`. If `ledger_rows < donations`, backfill `notification_deliveries` as `displayed` the same way night-zone was.

## Open items

- [x] Apply the import on the VPS — done 2026-08-28 (164/164, integrity ok)
- [x] Ledger backfill — done (10 rows → `displayed`, 164/164)
- [ ] Repoint the **BagiBagi** webhook to `https://api.hazastudio.id/webhook/bagibagi/after-hours/<webhook_token>` (route from `apps/api/src/app.js:163`). Token: `ssh --% root@103.42.244.55 "sqlite3 /var/lib/clubkit/db.sqlite 'select webhook_token from games where id=6'"`
- [ ] Point the place's `ClubKitConfig.Donation.ApiUrl` at `https://api.hazastudio.id/game/after-hours`, and check `Donation.ReliabilityV2` is present + `true` (it was **absent**, not just false, on night-zone — nested keys are not fill-forwarded)
- [ ] Seed the dashboard owner account (`seed-owner.js after-hours <username> <password>`) — none exists yet
- [ ] `games.provider_link` is empty on both backends; set it to the venue's BagiBagi page via `PATCH /admin/games/after-hours`
- [ ] Ask the owner why the place stopped polling on 13 July

## Note

Do not confuse `after-hours` (this buyer) with `afterwork-demo` (`games.id = 23`, place `82555748256114`, `bagibagi.co/afterwork`) — a separate demo entry that exists only on the VPS.
