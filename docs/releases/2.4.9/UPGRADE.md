# Upgrade v2.4.8 → v2.4.9

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Ensure `HttpService.HttpEnabled`
5. For primary Join Commun path: keep `Secrets.GameDataApiSecret` + GameKey `the-basic` (unchanged from 2.4.8)

## What's new

- **Skip roproxy when worker OK** - successful game-data `/community` resolve no longer also hits `MEMBER_INFO_URL` / `MEMBER_USERS_URL`; quieter 429 (DEBUG + short backoff) when roproxy is still needed.
- **CounterLeft** - badge = `memberCount - 8` when known and > 8; display capped at `+99` (no k/M/B on badge).
- **Body with names** - up to 3 display names + compact remaining others (`BODY_WITH_NAMES`).

## Breaking / behavior changes

- **Behavior only:** CounterLeft no longer uses compact k/M/B (uses `+99` cap). Body remaining count still uses compact k/M/B.
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `BODY_WITH_NAMES` | Replaces prior `BODY_WITH_EXTRA` wording; engine default via Update Engine |
| Buyer `Secrets` / `ClubKitConfig` | — | No required merge for this patch |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.9** after Update Engine
- [ ] With worker OK: Join Commun does not fall through to roproxy (no extra 429 WARN spam)
- [ ] CounterLeft shows remainder after 8 thumbs, max `+99`
- [ ] Body shows up to 3 names + compact others when samples exist
- [ ] Already-in-group: Join Commun still skipped
