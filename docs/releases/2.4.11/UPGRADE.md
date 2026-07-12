# Upgrade v2.4.10 → v2.4.11

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)
4. Optional: redeploy game-data-api worker if you need `/community` for non-allowlisted `gameKey`s (already allow-all after auth)

## What's new

- **Double Join Greeting fixed** - server `evaluationInFlight` lock before yielding `getPayload`; client ignores duplicate remotes per joiner for the session.
- **NukeWorldPosition for EffectDonate** - LocalNuke / BlackHole / GreenHammer / Blossom use `Config.Donation.NUKE_WORLD_POSITION` (from `ClubKitConfig.Donation.NukeWorldPosition`); `workspace.NukeModel` optional launch pad only.
- **game-data `/community` allow-all** - worker accepts any authenticated `gameKey` (empty allowlist); secret auth unchanged.

## Breaking / behavior changes

- **Behavior only:** world EffectDonate stages follow `NukeWorldPosition` instead of hardcoded spawn; rocket no longer requires `NukeModel`.
- DataStore / remotes: unchanged.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync (template comments only — buyers keep their `NukeWorldPosition` / `GameKey`).

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig.Donation.NukeWorldPosition` | Stage Vector3 | Now honored by active LocalNuke / related EffectDonate (was ignored before) |
| Buyer `ClubKitConfig.GameDataApi.GameKey` | string | No longer needs community allowlist entry; must still match worker secret |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.11** after Update Engine
- [ ] Join greeting: one RoyaleSpender toast per joiner (no double-fire ~1s apart)
- [ ] Donate LocalNuke impact lands at `NukeWorldPosition`; works without `workspace.NukeModel`
- [ ] BlackHole / GreenHammer / Blossom anchors align with same config position
- [ ] Join Commun with non-allowlisted gameKey works after worker redeploy (if applicable)
