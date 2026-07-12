# Upgrade v2.4.5 → v2.4.6

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Ensure `HttpService.HttpEnabled` if you want MemberCount + group member thumbs via roproxy (`MEMBER_INFO_URL` / `MEMBER_USERS_URL`)

## What's new

- **Compact counts** - MemberCount / CounterLeft / body use `k`/`M`/`B` (e.g. `10.6M`, `1.2k`).
- **Non-repetitive copy** - subtitle stays qualitative; body shows the compact count once (light alt pool). VIP TITLE/SUBHEADLINE unchanged.
- **Roster thumbs via users page** - one `MEMBER_USERS_URL` page (default roproxy `.../users?limit=40`), O(k) sample of 8, 300s cache; in-experience pool is secondary fill.
- **Quieter logs** - missing GroupService `MemberCount` logs DEBUG once (proxy fallback unchanged).

## Breaking / behavior changes

- **Behavior:** avatar strip prefers remote group users page over in-experience pool when Http works.
- **Behavior:** social copy no longer echoes the same raw MemberCount on subtitle and body.
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `MEMBER_USERS_URL` | Default roproxy group users page for thumbs |
| Engine `Config.JoinCommunityPrompt` | copy / `BODY_EMPTY_WITH_COUNT_ALT` | Qualitative subtitle + body count-once alt pool |
| Buyer `ClubKitConfig` | — | No required merge for this release |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.6** after Update Engine
- [ ] CounterLeft / body use compact k/M/B when count is large
- [ ] Subtitle does not repeat the same raw number as body
- [ ] Avatar strip fills from group users page when HttpEnabled (not only online pool)
- [ ] Missing MemberCount does not spam Output (DEBUG once)
- [ ] Already-in-group: Join Commun still skipped