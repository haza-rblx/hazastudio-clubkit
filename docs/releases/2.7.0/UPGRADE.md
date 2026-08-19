# Upgrade v2.6.7 → v2.7.0

**Date:** 2026-08-19

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

No config changes are forced — both features are **opt-in**. Fill-forward adds the new keys to your config automatically (in-memory); your existing values are preserved.

## What's new

### 1. Enterprise-grade donation notification reliability (opt-in)

Turn on with one line in `ClubKitConfig.luau`:

```lua
ClubKitConfig.Donation = {
	-- ... your existing keys ...
	ReliabilityV2 = true, -- NEW: never silently lose a donation notification
}
```

When enabled, every cash donation notification is tracked end-to-end in a durable Cloudflare D1 ledger: the server registers each online recipient, the client confirms receipt, the server retries players who don't confirm, and anything undeliverable lands in an auditable dead-letter queue instead of vanishing. Also removes the old client behavior that silently discarded small donations when the queue got full.

**Verified under load:** 60/60 notifications delivered + confirmed on a 60-donation burst (2× a real incident), 0 silently lost.

Requires the donation-api Worker ≥ v3 (already deployed — no action needed if you use the hosted `hazastudio-donation-api`).

Optional knobs (engine defaults shown, override via `Config.Donation` only if needed — most buyers never touch these):
- `NOTIF_ACK_RETRY_AFTER_SECS = 8` — seconds before re-firing to an unconfirmed player
- `NOTIF_ACK_MAX_ATTEMPTS = 20` — attempts before reporting to the dead-letter queue
- `NOTIF_BACKLOG_HARD_FLOOR_SECS = 2` — shortest display time when the queue is deep

Ops/audit (game or master admin token):
- `GET /admin/games/:key/delivery-report` — per-donation registered/acked/pending/dlq counts
- `GET /admin/games/:key/dlq` — deliveries needing manual attention

### 2. Per-role-group `/announce` cooldown (buyer-configurable)

```lua
ClubKitConfig.Announcement = {
	MinMembership = "Tier2", -- your existing key
	RateLimits = {           -- NEW (optional)
		Leadership = { Max = 10, Window = 60 }, -- Staff+: 10 per minute
		Spender    = { Max = 5,  Window = 60 }, -- top donors
		Member     = { Max = 3,  Window = 60 }, -- members ≥ MinMembership
		Player     = { Max = 1,  Window = 60 }, -- everyone else who can announce
	},
}
```

- Set only the groups you want to change — the rest keep engine defaults.
- **If you omit `RateLimits` entirely, nothing changes** — the legacy single budget (`RATE_MAX=2` / `RATE_WINDOW=30`) stays in effect. Fully backward compatible.
- Applies equally to `/announce` chat and to announces via your external admin (Adonis / Kohl's).

## Config changes

| Key | Where | Default | Notes |
|-----|-------|---------|-------|
| `Donation.ReliabilityV2` | ClubKitConfig | `false` | Opt-in delivery ledger |
| `Announcement.RateLimits` | ClubKitConfig | _(absent)_ | Per-group budgets; absent = legacy |

## QA after upgrade

1. Place loads with no red errors in Output.
2. (If `ReliabilityV2 = true`) server log shows `DonationService reliability v2 wired` on boot.
3. `/announce test` twice quickly — second one rate-limited per your group budget (or legacy 2/30 if you didn't set `RateLimits`).
4. A real/test cash donation shows the notification and (with ReliabilityV2) appears in `delivery-report` as `acked`.
