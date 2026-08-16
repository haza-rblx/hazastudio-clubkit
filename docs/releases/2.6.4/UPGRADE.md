# Upgrade v2.6.3 → v2.6.4

**Date:** 2026-08-16

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

## What's new

- **`Donation.Currency = "CASH"`** — a third cash-display option with neutral "Cash" labels (`Top Cash Spender` / `Top Cash` / chip suffix `CASH`) for venues that don't want to name Rupiah or Peso. Display-only; amounts are not converted.

## Config changes

| Field | Change |
|-------|--------|
| `Donation.Currency` | New accepted value `"CASH"` (alongside `"IDR"` / `"PHP"`). Default stays `"IDR"` — nothing changes unless you opt in. Also selectable in the Packager **Donations** currency dropdown (`Cash (neutral)`). |

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] Set `Donation.Currency = "CASH"` → overhead / boards / greetings show "Top Cash" labels
- [ ] Existing `IDR` / `PHP` venues unchanged
