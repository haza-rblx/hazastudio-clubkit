# Upgrade v2.4.0 → v2.4.1

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Buyer config (source sync does not replace `ClubKitConfig`):**
   - Set `Branding.LogoImage` to your community logo if still on kit default `rbxassetid://79426970537296` (used for loading/poster/boards **and** Join Community `CommunityLogo`)
4. **Tidak** replace `Secrets`

## What's new

- **Join greeting ~15s** — toast CountDownBar / hold timings extended (~5s → ~15s)
- **Join Commun placeholders** — `CommunityLogo` from `Branding.LogoImage`; avatar thumbs from online in-group players + server group roster; live `Subtitle` / `Body` (MemberCount + up to 3 names); `CounterLeft` only when MemberCount > 8

## Breaking / behavior changes

- None (DataStore / remotes additive). Join greeting simply lasts longer. Join Commun modal fills placeholders correctly instead of kit stubs.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync — merge `Branding.LogoImage` manually if needed.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| `ClubKitConfig.Branding` | `LogoImage` | Set to community logo (not kit default) |
| Engine `Config.JoinGreeting` | `MESSAGE_HOLD` / `WELCOME_HOLD` | 8.0 / 6.3 (~15s visible) |
| Engine `Config.JoinCommunityPrompt` | remotes + SAMPLE_LIMIT / CACHE_TTL | New server roster helper |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.1** after Update Engine
- [ ] Join greeting toast stays ~15s (CountDownBar)
- [ ] Join Commun: CommunityLogo matches `Branding.LogoImage`
- [ ] Join Commun: thumbs populate (online members and/or roster); Subtitle/Body live; CounterLeft only if members > 8
- [ ] Place still on kit default logo → modal shows kit logo until buyer sets `LogoImage`