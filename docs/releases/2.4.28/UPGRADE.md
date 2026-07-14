# Upgrade v2.4.27 → v2.4.28

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- Hotfix: Robux / likes / community boards refresh Display Name from UserService when metadata had `displayName == username` (e.g. after OneTimeLeaderboardSeeder). No re-seed of Robux amounts needed.
- OneTimeLeaderboardSeeder identity resolve uses UserService (for future seeds)

## Breaking

Tidak ada.

## Config changes

Tidak ada.

## QA

- [ ] Kit 2.4.28
- [ ] Robux board shows real Display Name (not duplicate of @username) where they differ
- [ ] Users whose Roblox Display Name truly equals Username still look correct
- [ ] No flood of UserService errors in console
