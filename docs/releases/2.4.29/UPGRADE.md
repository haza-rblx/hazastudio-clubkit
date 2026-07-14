# Upgrade v2.4.28 → v2.4.29

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- One-shot Display Name heal: after UserService resolve, kit persists `displayNameVerified` to leaderboard metadata so `displayName == username` no longer re-fetches every rebuild/TTL
- Identity lookups go through HttpApi (admission + shared cache when enabled)
- Future OneTimeLeaderboardSeeder / live donation metadata writes set verified=true

## Breaking

Tidak ada.

## Config changes

Tidak ada (schema metadata menambah field opsional `displayNameVerified`).

## QA

- [ ] Kit 2.4.29
- [ ] Robux board shows correct Display Names
- [ ] After first successful board paint, Server log does not keep repeating heal failures
- [ ] Players whose Display Name truly equals Username still look correct
