# Upgrade v2.4.4 → v2.4.5

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Optional: set `ClubKitConfig.JoinCommunity.MemberInfoUrl` if you need a custom worker instead of the default roproxy group-info URL
5. Ensure `HttpService.HttpEnabled` if you want real MemberCount / emblem via `MEMBER_INFO_URL` (default roproxy)

## What's new

- **Real MemberCount** - `GroupService:GetGroupInfoAsync` often omits `MemberCount`; kit no longer treats missing/0 as "Be among the first." Resolves real total via optional `MEMBER_INFO_URL` (default `groups.roproxy.com`) or buyer `MemberInfoUrl`. Payload includes `memberCountKnown`; copy uses neutral `BODY_NO_COUNT` when unknown. Never uses online/pool size as community total.
- **JoinCommun logo** - `16-JoinCommunPrompt` `CommunityLogo` prefers live group emblem (`EmblemUrl` / rbxthumb / proxy `emblemUrl`), then Branding, then GUI default. BrandLogoApplier skips JoinCommun; other `CommunityLogo` targets unchanged.

## Breaking / behavior changes

- **Behavior:** Join Commun member total is no longer a false empty claim when GroupService omits MemberCount. Without Http / proxy success, count may stay unknown (neutral copy) instead of "first."
- **Behavior:** JoinCommun logo may show group emblem instead of `Branding.LogoImage` (shop/boards still use Branding).
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `MEMBER_INFO_URL` | Default roproxy group-info JSON for MemberCount + optional emblemUrl |
| Engine `Config.JoinCommunityPrompt` | `BODY_NO_COUNT` / fail TTL | Neutral copy when count unknown |
| Buyer `ClubKitConfig.JoinCommunity` | `MemberInfoUrl` (optional) | Override proxy/worker URL; merge only if you want a custom endpoint |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.5** after Update Engine
- [ ] Join Commun body shows real group member total when Http/proxy works (not online player count)
- [ ] When count unknown: neutral body, not "Be among the first."
- [ ] JoinCommun `CommunityLogo` shows group emblem (not forced Branding stamp)
- [ ] Shop / overhead / boards `CommunityLogo` still follow Branding as before
- [ ] Already-in-group: Join Commun still skipped