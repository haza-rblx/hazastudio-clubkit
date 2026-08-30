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

## 2026-08-29 — engine 2.9.0 → 2.10.0 (+ unreleased), role catalog, CinematicLoading pack

Done via MCP in the open Studio session (**not saved until the owner presses Ctrl+S / publishes**):

- **Engine** synced to repo HEAD = 2.10.0 + unreleased (`roleColor.stops`, external loading
  contract, Admin Hub dynamic set-role picker). 425/425 engine files hash-match; 15 stale Rojo
  `init` twins removed. HttpService was already on; license `active`.
- **Role catalog** (`ClubKitConfig.RoleCategories` / `SystemRoles.Owner`) rewritten to the
  Hierapolis names — all `/setrole` roles (COMA group only has Member / Dev / Admin / Owner ranks):

  | Kit key | Label | Category | Gradient stops (`roleColor.stops`) | Chat `primary` |
  |---|---|---|---|---|
  | `Owner` (rank 255 / OwnerUserId) | The President | system | daad18 ffed2a fdff90 daad18 f4e628 | #FFD700 (kit default kept) |
  | `CoOwner` | The Archon | Leadership | 000000 2b2b2b 808080 c0c0c0 f1f4f4 | #000000 (first stop, owner's call 2026-08-29) |
  | `Emperor` | The Emperor (Scripter) | Leadership | 7f1d1d b91c1c de3b20 f87171 fca5a5 (ramp derived from old accent #DE3B20 — buyer never sent stops) | #7F1D1D |
  | `Minister` | The Minister (Admin) | Leadership | fa6c14 f18e37 f59b21 f7a640 ffdd00 | #FA6C14 |
  | `Echoborn` | The Echoborn | Content (not staff, per owner call) | 4b0082 8a2be2 e086d1 8a2be2 d388e0 | #4B0082 (first stop) |
  | `LeadDance` | The Senator (Lead Dancer) | Content | 301a9e 5141d7 5fec4c fafa3e **e61b23** (form said `e61b2`, 5 chars — completed from the old accent) | #301A9E (first stop) |
  | `DJ` / `Streamer` / `Influencer` | kit stock | Content | — | stock |

  **Owner refinement (2026-08-29, evening):** Emperor / Echoborn / Minister / Senator live in one
  category **DPC** (category = Admin privileges; per-role `privileges` override: Echoborn no gift /
  admin panel, Senator music + announce only) and share `chatTag = "DPC"` — so the Rank row, chat
  tag and player list read "DPC" — while the unique "THE …" text is shown as the overhead **role
  chip** (`specialRank.chip = true`, stops gradient, rank chips hidden) *and* on the special-rank
  row. President/Archon keep the stock **OWNER / CO-OWNER** label + chat tag (owner call); "THE PRESIDENT" / "THE ARCHON" appear only in the chip and the special-rank row. Re-apply after a Studio crash with
  `.tmp/hierapolis-config-apply.luau` (idempotent; dev-serve `/repo/` + loadstring).

  **Tool folders (2026-08-30):** each role now has its own `ServerStorage.Tools/<toolFolder>`:
  `OWNER` (existing), `CO-OWNER` (cloned from OWNER), `THE EMPEROR` / `THE ECHOBORN` /
  `THE MINISTER` (cloned from STAFF), `THE SENATOR` (cloned from LEAD DANCE). Old `STAFF`,
  `MODERATOR`, `LEAD DANCE` folders are left in place (unused by the catalog) — buyer can prune.

  `Staff` / `Moderator` were dropped; `LegacyAliases` maps stored `Staff`/`Moderator`/`Admin` →
  `Minister`, `Developer`/`Scripter` → `Emperor`, so existing DataStore roles keep working
  (verified: my test account's old `Staff` resolved to `Minister` in playtest). `CommandAliases`
  cover `president/archon/emperor/scripter/minister/admin/staff/echoborn/senator/lead dancer`.
- **Loading**: `Features.LoadingScreen = false`; `ReplicatedFirst.CinematicLoading` (LocalScript +
  `LoadingUI`) installed from `extras/place-packs/CinematicLoading`. Playtest: bar tracks kit boot,
  graphics menu shows with **no** join prompt under it, prompt + kit UI appear after a preset is picked.
- Old place (`backup HIERAPOLIS.rbxl`) untouched; its `ReplicatedFirst.LoadingScreen` is Disabled there.

## Open items / not done

- [ ] The Emperor ramp is derived, not buyer-supplied — swap in real stops if the buyer sends them.
- [ ] Assign the six roles with `/setrole <user> <president|archon|emperor|minister|echoborn|senator>`
      (old place used hardcoded userId lists; the kit persists roles in DataStore instead).
- [ ] `robloxstudio` MCP **client** peer times out in this place during playtest (server/edit fine) —
      unrelated to the sync, but it blocks client-side eval; use the `Roblox_Studio` server's
      screen_capture / mouse input instead.

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
