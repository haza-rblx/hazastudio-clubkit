# Upgrade v2.4.2 ? v2.4.3

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio ? Club Kit Packager ? **Check Update** ? **Update Engine**
2. Save place
3. Confirm place has **HttpService.HttpEnabled** (needed for random community member samples)
4. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- **Random community member samples** — social strip picks a random sample from a ~40-member Http pool (1 page), with 300s server cache and O(k) pick; client prefers server sample (skips mass `IsInGroupAsync` when full)
- **Join community headline** — VIP incentive restored on title/subheadline; only the member strip uses community-join wording

## Breaking / behavior changes

- None (DataStore / remotes unchanged). Sample fill is more efficient; headline copy returns VIP framing (vs v2.4.2 community-only title).

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `POOL_SIZE` / `CACHE_TTL` | 40 / 300s — single Http page + cache |
| Engine `Config.JoinCommunityPrompt` | `TITLE` / `SUBHEADLINE` | VIP incentive copy on modal open |
| Place setting | `HttpService.HttpEnabled` | Required for roster Http |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.3** after Update Engine
- [ ] Join Commun: title/subheadline show VIP incentive; strip body still community-join wording
- [ ] Avatar strip shows up to 8 random community members (not only online) when Http enabled
- [ ] Http disabled / empty pool: graceful fallback (online IsInGroup and/or empty body copy)
- [ ] Already-in-group: Join Commun still skipped as before
