# Buyer: NotCyrus (place name TBD — Studio calls it "PROJECT 1")

Status: **setup complete from form, not yet Published**. Last touched 2026-08-25.

No `PlaceName`/branding/logo/Discord given in the form (all left blank — "kosong = pakai
default kit"). Group name on Roblox is "Scargiver Studio" — may be a dev/studio group
rather than a public-facing venue name; ask if that matters before go-live.

## A. Place identity

| Field | Value |
|---|---|
| PlaceId | `121416685929057` |
| UniverseId (GameId) | `10759994649` |
| OwnerRobloxName | NotCyrus |
| OwnerUserId | `3345151382` — matches the Roblox group's actual `Owner.Id` (`havook999`) fetched via `GroupService:GetGroupInfoAsync`, so NotCyrus/havook999 are presumably the same person/account |
| GroupId | `486227935` ("Scargiver Studio") — confirmed via `game.CreatorId` before the form arrived |
| ContactDiscord | not given |

## B. ClubKitConfig — Branding

Form left every Branding field blank. `Branding.GameName` set to `"Club"` (the kit's
documented default) — **this was previously a placeholder string I wrote
("NotCyrus (placeholder — real branding TBD)") in an earlier pass; now reset to the real
kit default** since the form explicitly left it blank rather than asking to keep the
placeholder. Logo, WelcomeMessage, Greeting, DiscordInvite all still kit defaults.

## C. Group

- `Group.GroupId = 486227935`, `Group.OwnerUserId = 3345151382`, `Group.OwnerGroupRank = 255`
- No `ExtraAdminUserIds` given

## D. Shop

| Tier | GamePassId | GiftId | Price |
|---|---|---|---|
| Tier1 (VIP) | `100` | `3709779864` | 100 |
| Tier2 (VVIP) | `200` | `3709779908` | 200 |
| Tier3 (Supreme) | `399` | `3709779948` | 399 |

**Flagged, not fixed:** the three `BuyGamePassId` values (`100`/`200`/`399`) look like
placeholders, not real Roblox GamePass IDs — real ones are large (Hierapolis's were in the
1.8-billion range). These exactly match the `Price` values, which smells like a form
data-entry mix-up. Set as given per the form, but self-buy purchases will very likely fail
until these are confirmed/replaced with real Creator Dashboard GamePass IDs. `GiftId`
values and `PaidBroadcast.ProductId` look like real Developer Product IDs by contrast (same
shape as Hierapolis's), so probably fine.

## E. Paid Broadcast

`PaidBroadcast.ProductId = 3709780213`, enabled (no separate feature flag — implied by a
non-zero ProductId).

## F/G. Donation + Community backend — clubkit-infra

Same self-hosted backend as Hierapolis (`103.42.244.55` / `api.hazastudio.id`).

Registered as game key **`notcyrus`** (done in the prior pass, before this form arrived):

- `Donation.ApiUrl = "https://api.hazastudio.id/game/notcyrus"`
- `Donation.Provider = "bagibagi"`, `Donation.ProviderLink = "https://bagibagi.co/Notsuperman"`
  (updated from the placeholder empty value once the form came in)
- `GameDataApi.GameKey = "notcyrus"`
- `Secrets.DonationApiSecret` / `Secrets.GameDataApiSecret` set in Studio
  (`ServerScriptService.Hazastudio_ClubKitSecrets.Secrets`) — **values not duplicated
  here**; re-fetch via `GET /admin/games/notcyrus` on the VPS (needs `ADMIN_TOKEN`) if ever
  needed again.
- Form marked Section G "isi bersama Hazastudio" (deferred) — same as Hierapolis, this was
  already wired up and confirmed working before the form arrived, so left as-is rather than
  reverted to blank.
- **TODO (buyer-side):** paste the Saweria/Bagi-Bagi webhook URL into the Bagi-Bagi
  dashboard for Notsuperman — `https://api.hazastudio.id/webhook/bagibagi/notcyrus/<webhook_token>`
  (same `GET /admin/games/notcyrus` call returns the current token).

**Dashboard owner login** (`customer.hazastudio.id`, table `owner_users`):
- username `NotCyrus`
- password: set directly by the user, not recorded here.

## License

Bound during playtest 2026-08-25, before the form arrived:
```
license_status: active
license_enforced: true
universe_id: 10759994649
place_id: 121416685929057
```

## Playtest notes (2026-08-25, before this form's changes)

No `invalid_secret` errors — got the secret field mapping right on the first try this time
(learned from the Hierapolis swap bug: verify against raw `.Source` text with
`string.match`, never `require()` — `require()` returns a **stale cached module** across
separate `execute_luau` calls within the same Edit-mode session on this bridge; confirmed
twice now, once here and once on Hierapolis).

Two things surfaced, unrelated to this setup pass, **not yet investigated**:

- [ ] A large number of `The experience doesn't have access permission to use asset id ...`
      warnings (animations/sounds/models) — this experience likely hasn't been granted
      access to Hazastudio's shared asset library yet.
- [ ] Real error: `Utils is not a valid member of Folder
      "...PlayerScripts.Hazastudio_ClubKit.Client.Effects"`, thrown from
      `EffectDonate.Blossom.init` (line 12) and `EffectDonate.GreenHammer.init` (line 14) —
      looks like a broken require path in those two donation-effect scripts.

## Open items / not done

- [ ] Place not yet Published
- [ ] Confirm the three `BuyGamePassId` placeholder-looking values (see Shop section above)
- [ ] Real `Branding.LogoImage`, `WelcomeMessage`, `Greeting`, `DiscordInvite`
- [ ] `ContactDiscord` not given
- [ ] Paste Bagi-Bagi webhook URL into the Bagi-Bagi dashboard (see above)
- [ ] Investigate the asset-permission warnings and the `EffectDonate` `Utils` error above
