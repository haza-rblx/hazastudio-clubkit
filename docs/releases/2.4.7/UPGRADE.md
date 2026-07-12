# Upgrade v2.4.6 → v2.4.7

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Ensure `HttpService.HttpEnabled` if you want group member thumbs via `MEMBER_USERS_URL`

## What's new

- **Thumbs API limit fix** - default `MEMBER_USERS_URL` uses `limit=50` (Roblox Groups users API only accepts 10/25/50/100; `limit=40` caused HTTP 400 and empty remote thumbs).
- **Clamp** - any template `limit=` in the URL is clamped to the nearest valid page size.
- **Clearer fail logs** - failed users requests log a truncated response body once (`RequestAsync`).

## Breaking / behavior changes

- **Behavior:** remote thumbs should populate when HttpEnabled (previously empty due to invalid limit).
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `MEMBER_USERS_URL` | Default `limit=50`; custom URLs with other limits are clamped |
| Buyer `ClubKitConfig` | — | No required merge for this release |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.7** after Update Engine
- [ ] With HttpEnabled, Join Commun avatar strip fills (`remoteUsers` > 0 in logs)
- [ ] Invalid/custom `limit=` in URL still works (clamped)
- [ ] Failed users request shows truncated body once (not silent empty)
- [ ] Already-in-group: Join Commun still skipped
