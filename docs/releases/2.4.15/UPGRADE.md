# Upgrade v2.4.14 → v2.4.15

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. **Optional enable:** di buyer `ClubKitConfig`, set `Features.VipOnCommunityJoin = true` (default off — tanpa merge, behavior lama tetap)

## What's new

- **VIP on community group join** — when `Features.VipOnCommunityJoin = true` and `Group.GroupId > 0`, players already in the community group get Tier1 VIP (`membershipBadge`, same grant path as shop). After JoinCommun `PromptJoinAsync`, client fires `CommunityVipRecheck`; server re-verifies `IsInGroup` and grants if eligible.

## Breaking / behavior changes

- **Default off:** no VIP grant until buyer enables the flag in `ClubKitConfig`.
- New remote `CommunityVipRecheck` (engine creates it). No DataStore key changes.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync — merge flag manual.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | `Features.VipOnCommunityJoin` | Add / set `true` to enable (template default `false`) |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.15** after Update Engine
- [ ] With flag **false**: join group does **not** grant VIP
- [ ] With flag **true** + GroupId set: in-group player gets Tier1 VIP on join / after PromptJoinAsync
- [ ] ClubKitConfig + Secrets unchanged by Update Engine (except your manual flag merge)
