# Buyer: Zenith Aquatic — place "[KASMARAN💞] LANGIT SORE."

Status: **reinstalled at 2.12.0 on 2026-09-23 — NOT saved yet** (see section H). The 2026-09-06
install below was never saved, so the place came back without the kit.

## H. Reinstall 2026-09-23 (2.12.0)

Place now named `[🌈 A SAFE SPACE] ZENITH AQUATIC [ALPHA]` (same PlaceId/universe). Owner staged
the 2.12.0 buyer-place pack (`collectMode = buyer_place`, no `Lighting` bucket) in Workspace.
- `PackagerCore.unpack` over dev-serve, `replaceExisting = false`: 38 placed; skipped (kept the
  map's own) `ServerStorage/{DonationEffects,DonationSounds,Tools}` and `Workspace/hazastudioBoard`.
  Staging model deleted afterwards (its Scripts would run from Workspace).
- No source sync (pack is already 2.12.0); no fill-forward (repo HEAD keys are unreleased).
- Config repointed exactly as section C (the 2.12.0 pack carried `GameKey "the-basic"`, the old
  workers.dev `ApiUrl`, `Provider "bagibagi"` and the-basic product IDs).
- Secrets filled from the VPS row via a local `.tmp` file read over dev-serve, then deleted.
- Playtest: banner `v2.12.0 · build 20260912`, `License verify on boot {status=active}`, VPS row
  `kit_version 2.12.0` / `last_seen_at 2026-09-23T15:00`. Warnings only the expected ones.
- Dashboard owner account `zenith` (game 31) — created by the owner with `seed-owner.js`.
- Owner request: no Auto / Lead Dance topbar pills here. Place carries the unreleased
  `Features.AutoDance` / `Features.LeadDanceTopbar` switches (anchored diffs on 5 files), both
  `false` in this config. A future engine update keeps them off (buyer config wins).

Owner-operated place under Hazastudio's own Roblox account (`hazatargz`), not a third-party
buyer — no buyer-side TODO list, but the same licence + registration path as any venue.

## A. Place identity

| Field | Value |
|---|---|
| PlaceId | `112604088858627` |
| UniverseId (GameId) | `9998697204` |
| Creator | `hazatargz` (`8842050215`), CreatorType User — no group |
| Game key (VPS) | `zenithaquatic` |
| StreamingEnabled | **true** (see the daily-board note below) |
| Kit version installed | 2.11.0 |

## B. What was installed

1. `HazastudioClubKit_Package_v2.9.2.rbxm` (newest full pack in `deliver/`) was already staged
   in Workspace as `HazastudioClubKit_Package`; unpacked with `PackagerCore.unpack` loaded over
   dev-serve — **`replaceExisting = false`, and the `Lighting` bucket deleted from the staging
   model before unpack** (see the incident note below). 53 items placed, 0 skipped, 0 replaced.
2. Engine source-synced 2.9.2 → **2.11.0**: 46 files applied (33 drifted + 13 new), verified
   **429/429 hash match** against the repo. No GUI-only work needed — 2.10.0 and 2.11.0 changed
   Luau only, so the 2.9.2 pack plus the source sync is a complete 2.11.0 install.
3. `ConfigPatchCore.patchBuyerConfig` fill-forward: added `Features.HierapolisCustom` (1 key).
   At boot `ConfigBootstrap.fillForward` fills 9 more in memory (LegacyAliases ×4,
   `Announcement.RateLimits`, CommandAliases ×4) — normal, not an error.

## C. ClubKitConfig — what was changed

The 2.9.2 pack ships **the-basic's** config values, not a blank template. Everything below had
to be repointed or this place would have polled another venue's endpoint:

| Key | Was (from the-basic) | Now |
|---|---|---|
| `Branding.GameName` | `"thebasic"` | `"Zenith Aquatic"` |
| `Donation.ApiUrl` | `…/game/thebasic` | `https://api.hazastudio.id/game/zenithaquatic` |
| `GameDataApi.GameKey` | `"thebasic"` | `"zenithaquatic"` |
| `Group.OwnerUserId` | `0` | `8842050215` |
| `Donation.Provider` | `"sociabuzz"` | `""` (no cash provider yet) |
| `Donation.ProviderLink` | `https://sociabuzz.com/hazatargz` | `""` |
| `Shop.Products.Tier1–3` `GiftId`/`BuyId` | the-basic Developer Products (`3608406587`/`…626`/`…664`, `3608406407`/`…452`/`…486`) | `0` |
| `PaidBroadcast.ProductId` | `3503700307` | `0` |

Left alone: `Group.GroupId = 0` (no group yet — owner's call), `Currency = "IDR"`,
`Branding.LogoImage = rbxassetid://79426970537296` (still the default kit logo),
`ExternalAdmin.Provider = "None"`.

Monetization IDs were zeroed rather than left in place because Developer Products are
universe-scoped: the-basic's IDs can only fail if a player presses buy here. Boot warns loudly
about each `0` until the real Creator Dashboard IDs land, which is the intended reminder.

## D. Backend — clubkit-infra (`103.42.244.55` / `api.hazastudio.id`)

Registered via `POST /admin/games` + `PATCH /admin/games/zenithaquatic/license`
(script run from the repo, response captured to a local file and deleted after use):

```
games.id            31
game_key            zenithaquatic
name                Zenith Aquatic - LANGIT SORE
currency            IDR
universe_id         9998697204
place_id            112604088858627
license_status      active
license_enforced    1
maintenance_until   (empty)
```

`Secrets.DonationApiSecret` (= `games.secret`) and `Secrets.GameDataApiSecret`
(= `games.social_secret`) were written into
`ServerScriptService.Hazastudio_ClubKitSecrets.Secrets` directly from the API response —
**values are not recorded here or anywhere in the repo**; re-fetch with
`GET /admin/games/zenithaquatic` (master `ADMIN_TOKEN`) if ever needed.

Webhook URL for whenever a cash provider is set up:
`https://api.hazastudio.id/webhook/{saweria|bagibagi|sociabuzz}/zenithaquatic/<webhook_token>`
(token from the same `GET`).

## E. Playtest verification (2026-09-06)

- Banner: `v2.11.0 · build 20260830`, `Universe 9998697204`.
- `[LicenseService] License verify on boot | {status=active}` — gate reachable, secret correct.
- `[TamperGuard] TamperGuard armed | {kick=true, brick=false}`.
- `CommandLibraryController … role=Owner` — `Group.OwnerUserId` resolves.
- VPS row updated by the beacon: `kit_version 2.11.0`, `kit_build_id 20260830`,
  `last_seen_universe_id 9998697204` — licence bind proven end to end.
- Expected warnings only: shop/broadcast IDs `0`, `Group.GROUP_ID invalid`, default LogoImage,
  `DataStore scope: LIVE production keys from Studio`.

### Daily-board warning is a streaming artifact, not a break

`[Client.WorkspaceLeaderboards] DailyDonationsWrapper SurfaceGui not found` fires once for
`DailyDonations` / `…Cash` / `…Robux`. The map has StreamingEnabled and those boards sit
279–347 studs from spawn, so they had not replicated when the controller first resolved.
All three exist with the right `DailyDonationsWrapper` SurfaceGui, and
`renderDailyDonations` re-resolves on every payload, so they bind on the next refresh.
Note `CanvasGroupBudgetService` culls SurfaceGuis past `cullDistance = 250`, which covers all
three — they are culled at distance by design.

The map already carried a `Workspace/hazastudioBoard` folder with all 14 board parts
(`RobuxDonationBoard`, `SaweriaDonationBoard`, `LikesLeaderboard`, `Top1–3Cash/Robux`,
`DailyDonations*`, `CommunityDonationBoard`, `LiveChatDonations`) built in, so no board
placement was needed; unpack tagged 5 donation display roots.

## F. Incident: map Lighting lost

The first unpack ran with the installer default `replaceExisting = true`, which **destroyed
the map's `ColorCorrection`, `DepthOfField`, `Sky` and `Atmosphere`** and put the kit's
showcase versions in their place. A Ctrl+Z then removed the kit's clones without restoring
the originals, and neither `ChangeHistoryService:Undo()` nor `Redo()` brought them back
(the whole first unpack was reverted by that undo as well).

Lighting now holds only the map's surviving `Blur` + `SunRays`. Owner chose to carry on and
rebuild lighting by hand rather than reopen the place; **`Sky`, `Atmosphere`,
`ColorCorrection` and `DepthOfField` still need to be recreated.** Lighting's own properties
were untouched (`Ambient 1, 0.933, 0.878`, `OutdoorAmbient 0.922, 0.573, 0.220`,
`Brightness 2`, `ClockTime 17`, `ExposureCompensation -0.6`).

**Rule for the next fresh install onto a finished map: delete the `Lighting` bucket from the
staging package before unpack, and pass `replaceExisting = false`.** That is what the second,
successful pass did.

## G. Open items

- [ ] **Ctrl+S in Studio + Publish** — nothing above is persisted until then
- [ ] Rebuild `Sky` / `Atmosphere` / `ColorCorrection` / `DepthOfField` (section F)
- [ ] Dashboard owner account — not yet created; `hazatargz` is free as a username:
      `cd /opt/clubkit/apps/api && bun scripts/seed-owner.js zenithaquatic hazatargz '<password>'`
- [ ] `Group.GroupId` once a Roblox group/community exists (rank-based roles stay off until then)
- [ ] Real `BuyGamePassId` / `GiftId` per tier + `PaidBroadcast.ProductId` from this universe's
      Creator Dashboard
- [ ] `Branding.LogoImage`, `WelcomeMessage`, `Greeting`, `DiscordInvite` still kit defaults
- [ ] Cash donation provider + link, then paste the webhook URL (section D) in the provider dashboard
- [ ] The pack ships `Kohl's Admin` + `Adonis_Loader` into ServerScriptService; both are inert
      (`ExternalAdmin.Provider = "None"`) but they still load their own systems — remove if unwanted
