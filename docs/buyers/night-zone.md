# Buyer: THE NIGHT ZONE

Status: **updated to 2.9.2 + CanvasGroup fixes, reliability v3 enabled, data migrated to VPS.** Last touched 2026-08-28.

**2026-08-28 check (place open in Studio):** the engine build **persisted** — `GroupMotionPolicy`, `Client/Utils/GroupMotion`, `CanvasGroupBudgetService` all present, `Config.CanvasGroupBudget` = `{ENABLED = true, 180, 20, 0.5}`, `UIMotion.CANVAS_GROUP_SIZE_STABLE = true`, **0 stale Rojo `init` twins**, `KitProduct.KitVersion = 2.9.2`, `Donation.ApiUrl = https://api.hazastudio.id/game/night-zone`, `ReliabilityV2 = true`. (If this place was opened fresh from the cloud, the owner's Ctrl+S landed; if it is the same Studio session from 2026-08-27, that is still unconfirmed.)

Also ran the ADR 0005 release-gate QA pass here — **0 size violations / 91 CanvasGroups**, ~15 surfaces clean. Detail in [`UPGRADE_PROGRESS.md`](../../UPGRADE_PROGRESS.md).

**New finding:** a leftover **Kohl's Admin** loader is installed in this place. Its dashboard owns the topbar admin slot, and opening it shows a "40% OFF — unlock exclusive commands" purchase upsell to whoever is admin. This is the same leftover-admin-loader problem tracked in the Packager backlog; it also blocked QA of the kit's own admin panel.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | [UPD🌸] NIGHT ZONE |
| PlaceId | `140556013758180` |
| GroupId (Community) | `504061531` |
| `Branding.GameName` | `Night Zone` |

## Engine

- Updated **2.8.9 → 2.9.2 + unreleased CanvasGroup fixes** (ADR 0005) on 2026-08-27 via dev-serve `/repo/` bridge + plugin `SourceSyncCore` (27 files; **15 stale Rojo `init` twins removed**; config fill-forward 0 keys). Playtest clean; budget guard culled 9/10 workspace SurfaceGuis at spawn. Owner must **Ctrl+S**.

## F/G. Donation + Community backend — clubkit-infra (VPS)

Game key **`night-zone`** (`games.id = 5`), already registered with `groups_enabled = 1`, `community_enabled = 1`, license `active`. `Donation.ApiUrl` was already `https://api.hazastudio.id/game/night-zone`; both secrets already valid (poll `200`).

Done 2026-08-27:
- **`ClubKitConfig.Donation.ReliabilityV2 = true` inserted** (key was absent from the buyer file **and** from the schema at that version, so there was no default to fill forward. Corrected 2026-09-18: `ClubKitConfigSchema.fillForward` *does* recurse into nested tables and fill missing nested keys — the rule is "must exist in the schema defaults", not "must be top-level". `ReliabilityV2` is in the schema now.). Enables `/v3/deliveries|delivery-ack|delivery-display|delivery-dlq`.
- **Data migration (delta):** reconciled by `provider_tx_id` — VPS had 85 of the old worker's 86 donations, 0 mismatches. Imported the 1 missing (2026-08-22, VSTxSan_TKAM 15,307). After: **86 donations / Rp 4,791,241 / last_at 2026-08-22T13:26:28Z**, integrity `ok`. Backup: `/var/lib/clubkit/backups/db-pre-nightzone-migrate-20260827-114002.sqlite`.
- Ledger: 7 donations had no `notification_deliveries` row → backfilled as `displayed` (same shape as the 2026-08-22 backfill). Now 86/86 displayed.
- **Dashboard owner login** (`customer.hazastudio.id`, `owner_users.id = 13`): username `nightzone`, password per owner request.
- **TODO (owner-side, required):** paste `https://api.hazastudio.id/webhook/saweria/night-zone/<webhook_token>` into the Saweria dashboard for `saweria.co/lvlcomunity`. Until then new donations keep landing in the old worker's D1.
- VPS `games.provider_link` is empty while config says `https://saweria.co/lvlcomunity` — cosmetic; set via `PATCH /admin/games/night-zone`.

## Same-day note on RUST

While migrating night-zone, the old worker showed **one new rust donation (2026-08-27 10:07, Miebeeone 100,708)** — proof the RUST Saweria webhook had not been moved yet. Imported it too (rust now 435 / Rp 40,481,749) and marked displayed. Same backup covers it.

## 2026-09-18 — support pass (tools, Saweria, emote audit)

Place-only; still **unsaved**, owner owes a **Ctrl+S**. Nothing from this pass changed the repo.

**Role tools were missing for Founder / Co Owner (and more).** `ServerStorage.Tools` still carried
V1-era folder names (`DONOR`, `INFLUENCER`, `MODERATOR`, `TOP DONOR`, …) while the config asked for
the V2 ones. The engine's "folder not found" log is `debug` level, so nothing showed in the console.
Created with a clone of STAFF's 10 tools: `FOUNDER`, `CO OWNER`, `HEAD STAFF`, `GUARD`, `CREATOR`,
`TOP DONATE`, `SPENDER`. Plus `PRIME` ← clone of VVIP and `PRESTIGE` ← clone of SUPREME, because
**`RoleToolService` picks the highest-priority folder *name* before checking the folder exists**, so
the missing `PRIME`/`PRESTIGE` (derived from this buyer's `Membership.Label`) shadowed the working
`VVIP`/`SUPREME` and every Prime/Prestige member had been getting **zero** tools. All 18 role and
membership paths now resolve to an existing folder. **The engine ordering flaw itself is unfixed** —
it bites any buyer who renames their membership tiers. Owner deferred it.

**Saweria notifications: the kit is healthy, nothing is arriving.** `/v2/notifications` returns
HTTP 200, secret and licence fine, `donation_poll` runs every ~6 s. Newest donation on record is
**id 3058, 2026-08-22 13:26 UTC** — 27 days of silence at the time of checking. Owner-side: compare
the webhook URL on `saweria.co/lvlcomunity` with `saweria_webhook` for night-zone in the admin
dashboard, then check `webhook_events` on the VPS for rows after 2026-08-22. Follow `next_cursor`
to the end when reading the API — the list is ascending, so page 1's newest row is not the newest
donation. Side finding: **all 79 donations have `roblox_username = ""`**, so donor→player mapping
has never worked here.

**Emote audit** (owner suspected marketplace revocation): 187 animations, only `Bounce Dance`
(`131474230732063`) fails to fetch. But **zero** of the 187 are owned by the experience owner
Group 504061531 — 122 belong to user `hazatargz`, 61 to unrelated creators, 4 to Roblox. The fetch
test ran in Studio **as the asset owner**, so "Success" there does not prove a live player can play
them; experience-level asset access cannot be queried from Studio. Full TSV was handed to the owner.
Four animation names carry stray spaces (`" Banana Shake"`, `" Belly Twist R"`, `"Cower "`,
`"Atmosfer "`) so they mis-sort and the panel's search cannot find them.

**Buyer config oddity, left alone:** `Group.OwnerUserId = 9867421889, 9094351307,` — valid Lua, but
the second id lands as `Group[1]` and `ConfigBootstrap` only reads a single number, so the second
owner has never been active.

### Still open from this pass

- [ ] Ctrl+S in Studio — the nine tool folders exist only in the edit session.
- [ ] Saweria webhook (owner-side, outside Studio).
- [ ] Prove the dance question with an **alt account in the live game**; if it is asset access,
      the 122 hazatargz-owned animations need re-uploading to the group and the 61 third-party
      ones replaced.
- [ ] Decide whether to fix the `RoleToolService` name-before-existence flaw in the engine.

## Open items

- [x] Owner: Ctrl+S / publish — engine files present in the place as opened on 2026-08-28 (see status note)
- [ ] Remove the leftover Kohl's Admin loader (or confirm the owner wants it), then QA the kit admin panel
- [ ] Owner: paste Saweria webhook URL (see above)
- [ ] Align VPS `provider_link`
