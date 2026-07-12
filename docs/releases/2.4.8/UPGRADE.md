# Upgrade v2.4.7 → v2.4.8

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Ensure `HttpService.HttpEnabled`
5. For the **primary** Join Commun path (game-data worker): set `Secrets.GameDataApiSecret`, use GameKey **`the-basic`** (allowlisted), and ensure the game-data-api worker is deployed with the `/community` endpoint (already deployed separately for this release)

## What's new

- **Join Commun via game-data worker** - preferred source is now `GET /game/:gameKey/community/:groupId` (Open Cloud + cache): `memberCount`, `members[]`, optional `emblemUrl` in one call. Allowlist: `the-basic` (+ `nuwa`).
- **Thumbs HTTP 400 hardening** - roproxy fallback: Asc sort (not Desc), valid limit clamp (no POOL_SIZE=40), retries, then roles/`roleSetId`/users fallback; richer fail log (`url`, `statusCode`, `body`, `kitVersion`).

## Breaking / behavior changes

- **Behavior:** with `GameDataApiSecret` + deployed worker, Join Commun prefers the worker over roproxy. Without secret, Studio still falls back to `MEMBER_INFO_URL` / `MEMBER_USERS_URL` (DEBUG skip log).
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `Secrets` | `GameDataApiSecret` | Required for primary worker path; merge manually if missing |
| Buyer `ClubKitConfig` | GameDataApi / GameKey | GameKey `the-basic` for this place; review template notes if needed |
| Engine `Config.JoinCommunityPrompt` | community preference | Engine default; no buyer merge required for sync |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.8** after Update Engine
- [ ] With secret + HttpEnabled: Join Commun uses worker (`/community`) — thumbs + count populate
- [ ] Without secret: falls back to roproxy; no hard fail
- [ ] Huge group (e.g. 3996161): no HTTP 400 empty thumbs on fallback path
- [ ] Already-in-group: Join Commun still skipped
