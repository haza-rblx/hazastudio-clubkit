# Upgrade v2.3.0 → v2.3.1

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Optional config merge:** add `Features.PromptJoinCommunityOnLoad = true` (or `false` to disable) in buyer `ClubKitConfig` if missing — source sync does **not** replace ClubKitConfig
4. **Tidak** replace `Secrets`

## What's new

- After loading / `enterGameplay`, client prompts Roblox group join (`GroupService:PromptJoinAsync`) for `ClubKitConfig.Group.GroupId` once per session (prompts even if already a member)
- Toggle: `Features.PromptJoinCommunityOnLoad` (default on); skipped when `GroupId` is `0`

## Breaking / behavior changes

- None (additive). Existing places without the Feature key keep engine default **on** via `Config.FeatureFlags.PromptJoinCommunityOnLoadEnabled`.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync — merge Feature flag manually if you want an explicit buyer toggle.

## Config notes

| Path | Field | Default |
|------|--------|---------|
| `ClubKitConfig.Features` | `PromptJoinCommunityOnLoad` | `true` (kit template) |
| Engine `Config.FeatureFlags` | `PromptJoinCommunityOnLoadEnabled` | `true` |

## QA setelah upgrade

- [ ] Plugin shows kit **2.3.1** after Update Engine
- [ ] With `GroupId` set and Feature on: after load, join-community prompt appears once per session
- [ ] Feature `false` or `GroupId = 0`: no prompt
- [ ] Already a group member: still sees prompt (by design)
