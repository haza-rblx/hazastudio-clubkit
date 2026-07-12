# Upgrade v2.4.9 → v2.4.10

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Ensure `HttpService.HttpEnabled`
5. Game-data worker for `/community` should already send `memberCount: null` + `memberCountKnown` when Open Cloud omits count (redeployed separately if needed)

## What's new

- **CounterLeft / "others" when count known** - Join Commun restores remainder badge and body "others" when `memberCount` is known.
- **Reject bogus `memberCount` 0 + samples** - inconsistent worker/Open Cloud `0` with member samples is treated as unknown count.
- **Fall through to `MEMBER_INFO_URL`** - when worker OK but count still unknown, kit fetches count via roproxy path (members from worker kept).
- **DEBUG fill log** - client logs once: `memberCount`, `memberCountKnown`, `remainder`, `counterFound`.

## Breaking / behavior changes

- **Behavior only:** successful worker responses with unknown/`0`-bogus count may now also hit `MEMBER_INFO_URL` for count (members still from worker). Opposite of the "never fall through when worker OK" shortcut in 2.4.9 when count was missing.
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `Secrets` / `ClubKitConfig` | - | No required merge for this patch |
| game-data-api worker | `/community` | Prefer redeployed worker that does not coerce missing meta to `0` |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.10** after Update Engine
- [ ] Large community: CounterLeft shows remainder (cap `+99`) when count resolves
- [ ] Body includes names + "others" when count known and samples exist
- [ ] Worker OK + missing count: still gets count via MEMBER_INFO_URL (DEBUG fill once)
- [ ] Already-in-group: Join Commun still skipped
