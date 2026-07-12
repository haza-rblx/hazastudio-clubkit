# Upgrade v2.4.11 -> v2.4.12

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio -> Club Kit Packager -> **Check Update** -> **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- **Join Community always shows** - modal still opens when the player is already in the group; CTA becomes **Already joined** and dismisses (no `PromptJoinAsync`). Non-members keep **Join Community**.
- **Join greeting ~7s** - toast CountDownBar hold/fade totals ~7 seconds (was ~15s).

## Breaking / behavior changes

- **Behavior:** players already in the community see the Join Commun modal again (with Already joined) instead of skipping it.
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync (template comment only - `PromptJoinCommunityOnLoad` no longer means skip-for-members).

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig.JoinCommunity` / PromptJoinCommunityOnLoad | flag | Semantics: show modal after load when enabled; members get Already joined CTA |
| Engine `Config.JoinGreeting` holds | MESSAGE_HOLD / WELCOME_HOLD | Defaults ~7s total; buyers using ClubKitConfig overrides keep their values |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.12** after Update Engine
- [ ] Join greeting toast visible ~7s (not ~15s)
- [ ] Non-member: Join Commun shows **Join Community** -> PromptJoinAsync
- [ ] Member: Join Commun still opens; button **Already joined**; dismiss without join prompt
