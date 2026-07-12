# Upgrade v2.4.3 → v2.4.4

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Http to `groups.roblox.com` is **no longer required** for the Join Community avatar strip (Roblox blocks Http to own domains anyway)

## What's new

- **Join community roster fix** — stop calling `groups.roblox.com` via HttpService. MemberCount stays on `GroupService:GetGroupInfoAsync`; avatar strip samples an in-experience pool of community members seen in this place (PlayerAdded + online warm), with optional MemoryStore cross-server share. Client online in-group merge unchanged.

## Breaking / behavior changes

- **Behavior:** Join Commun avatar strip no longer fetches remote group roster pages over Http. Samples come from members who have been seen in this experience (local server pool ± MemoryStore). Early after a cold start / low traffic, the strip may be thinner until the pool fills — MemberCount / body copy still use GroupService.
- DataStore / remotes / buyer config: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `POOL_SIZE` / `CACHE_TTL` | 40 / 300s — in-experience pool cap + MemberCount cache |
| Engine `Config.JoinCommunityPrompt` | `MEMORY_STORE_ENABLED` / `MEMORY_STORE_TTL` / `MEMORY_STORE_NAME` | Cross-server pool (default on, TTL 86400; name nil → KitProduct prefix) |
| Place setting | `HttpService.HttpEnabled` | **Not required** for Join Commun roster anymore |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.4** after Update Engine
- [ ] Join Commun opens without Http errors related to `groups.roblox.com`
- [ ] MemberCount / body copy still populate via GroupService
- [ ] Avatar strip fills from online in-group + in-experience pool (grows as members visit)
- [ ] Already-in-group: Join Commun still skipped as before
