# Upgrade v2.6.2 → v2.6.3

**Date:** 2026-08-16

## Quick steps (source sync — primary)

1. **Backup** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` and `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
2. Studio → Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine**
3. Save the place, play test, publish

No config changes in this release — nothing to merge.

## What's changed

- **Admin Hub phone scale 0.44 → 0.5** — the Admin Hub is less cramped on phone layouts.
- **Admin Hub Announce box opens empty** — no more default "Welcome to the club!" prefill; the placeholder shows instead.

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] Open Admin Hub on a phone layout → larger than before (scale 0.5)
- [ ] Admin Hub → Announce → message box opens empty with placeholder text
