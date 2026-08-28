# Buyer: Hierapolis Theatre

Status: **soft opening setup complete, not yet Published**. Last touched 2026-08-25.

Onboarding form (owner-filled) is `HAZASTUDIO CLUB KIT — FORM OWNER` sent 2026-08-25 — not
committed here since it carries contact info; ask the user if it needs to be found again.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | [SOFT OPENING] Hierapolis Theatre |
| PlaceId | `124816875861754` |
| UniverseId (GameId) | `10180011184` |
| OwnerRobloxName | COMAxValGen |
| OwnerUserId | `9075246747` |
| ContactDiscord | ValGen |
| GroupId (Community) | `1068114138` — confirmed via `game.CreatorId` (`CreatorType = Group`); a prior scripter had already set the place to this group, not something we created |

## B/C. ClubKitConfig — Branding & Group

- `Branding.GameName = "[SOFT OPENING] HIERAPOLIS THEATER"`
- `Group.GroupId = 1068114138`, `Group.OwnerUserId = 9075246747`, `Group.OwnerGroupRank = 255`
- `AdminUserIds` (8): XiaoBey4 `9041379923`, ByuuuByuuu `5170798570`, Kinanprmth `8929331384`,
  dboyPKL `8755283537`, Neng_Xyna `9494693960`, Khangmoose `8853397666`,
  COMAxValGen `9075246747` (owner), scoobidoes13 `9486519141`
- `Features.VipOnCommunityJoin = true` — **interpretation call**: the form's Tier1 label was
  "VIP (Join Community Free VIP)"; read as intent to enable this flag rather than literal
  label text (label kept as plain "VIP"). Confirm with buyer if wrong.
- Still kit default, **not real for Hierapolis yet**: `Branding.LogoImage`
  (`rbxassetid://79426970537296`), `PaidBroadcast.ProductId` (`3503700307`), Tier1/Tier2
  `GiftId`, all of Tier3 (Supreme) — none of these will work until real Creator Dashboard
  IDs + a logo are provided and swapped in.

## D. Shop

| Tier | GamePassId | Price |
|---|---|---|
| Tier1 (VIP) | `1841126531` | 100 |
| Tier2 (VVIP) | `1841482598` | 500 |
| Tier3 (Supreme) | unset (kit default) | unset |

## F/G. Donation + Community backend — clubkit-infra (self-hosted, replaced Cloudflare Workers)

VPS: Sumopod host `103.42.244.55`, service `clubkit-api` (systemd) behind Caddy at
`api.hazastudio.id`. Repo lives at `/opt/clubkit` on the VPS; a stale local copy for
reference is at `~/Desktop/ClubKit v2.7.0 Delivery/clubkit-infra` (older snapshot, don't
trust its README status table — the real deploy is newer).

**Found during setup: production `.env` had a blank `ADMIN_TOKEN`** (this VPS deploy was
brand new, same day). Generated a new one, wrote it into
`/opt/clubkit/apps/api/.env`, restarted `clubkit-api`. Anyone rotating that token again
will break `/admin/*` for every registered game until updated.

Registered as game key **`hierapolis`** via `POST /admin/games`:

- `Donation.ApiUrl = "https://api.hazastudio.id/game/hierapolis"`
- `Donation.Provider = "saweria"`, `Donation.ProviderLink = "https://saweria.co/COMAStudio"`
- `GameDataApi.GameKey = "hierapolis"`
- `Secrets.DonationApiSecret` and `Secrets.GameDataApiSecret` are set in Studio
  (`ServerScriptService.Hazastudio_ClubKitSecrets.Secrets`) — **values intentionally not
  duplicated here**; re-fetch from the VPS admin API (`GET /admin/games/hierapolis`,
  needs `ADMIN_TOKEN`) if they ever need to be re-applied.
- **TODO (buyer-side, not yet confirmed done):** paste the Saweria webhook URL
  (`https://api.hazastudio.id/webhook/saweria/hierapolis/<webhook_token>` — same
  `GET /admin/games/hierapolis` call returns the current token) into the Saweria dashboard
  for COMAStudio.
- Note: the form marked Section G (Join Community / GameDataApi) as "isi bersama
  Hazastudio" (deferred), but registering the game on clubkit-infra generated
  `social_secret` too and it's already live — confirmed working in playtest (real
  `memberCount` pulled). This is a **deviation from what the form asked** — flag to buyer.

**Dashboard owner login** (`customer.hazastudio.id`, table `owner_users`):
- username `hierapolis`
- password: set directly by the user in this session, not recorded here — if lost, reset
  via a one-off script pattern (see chat history 2026-08-25, or write a new
  `UPDATE owner_users SET password_hash = ...` using `hashPassword()` from
  `apps/api/src/lib/auth.js`, same approach as `apps/api/scripts/seed-owner.js`).

## License

`KitProduct.LicenseEnforcementEnabled = true` (kit build 20260821) → `LicenseService`
auto-binds on first successful boot verify. Confirmed bound 2026-08-25 via
`GET /admin/games/hierapolis/license`:

```
license_status: active
license_enforced: true
universe_id: 10180011184
place_id: 124816875861754
```

## Playtest verification (2026-08-25)

Full server boot, no errors. Donation polling clean (no `invalid_secret`), community data
pulled live (290 members / 40 sampled), social API working, license banner confirmed
(`found product license · creator type: Group · owner id: 9075246747`).

**Bug caught + fixed during this pass:** first attempt at writing the two secrets into
`Secrets.luau` swapped them (`DonationApiSecret` got the GameData value and vice versa) —
caught because donation polling threw `HTTP 403 invalid_secret` on the first playtest.
Re-applied correctly and reconfirmed via a second playtest before calling it done. Worth
remembering if secrets are ever re-applied by hand again: verify with a real playtest, not
just "field is non-empty".

## Open items / not done

- [ ] Place not yet Published — everything above is live only in the Studio edit session
- [ ] Real Creator Dashboard IDs: Tier1/Tier2 GiftId, all of Tier3, PaidBroadcast.ProductId
- [ ] Real community logo → `Branding.LogoImage`
- [ ] Paste Saweria webhook URL into the Saweria dashboard (see above)
- [ ] Console warning: `asset id 91544177043449` not accessible to the experience —
      unrelated to this setup pass, likely a pre-existing map asset; not yet tracked down
- [ ] `ExternalAdmin.Provider = "None"` even though Kohl's Admin is installed in the place
      (`ExternalAdmin` bridge log: `kohls=true`, inactive) — optional, flip to `"Kohls"` if
      the buyer wants `/setrole` to sync into Kohl's Admin ranks too
- [ ] Confirm buyer is OK with Section G (Join Community) being live already, ahead of
      the form's "isi bersama Hazastudio" note
