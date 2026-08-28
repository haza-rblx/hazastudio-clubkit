# Buyer: RUST Warehouse

Status: **migrated to clubkit-infra (VPS) + updated to 2.9.2, place not yet saved/published by owner at time of writing.** Last touched 2026-08-27.

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | [Rap/Rnb/HipHop] RUST WAREHOUSE MUSIC |
| PlaceId | `85501880339890` |
| UniverseId (GameId) | `9962470719` |
| GroupId (Community) | `763632944` |
| `Branding.GameName` | `Rust Warehouse` |

## Engine

- Updated **2.8.0 → 2.9.2 + unreleased CanvasGroup fixes** (ADR 0005) on 2026-08-27 via the dev-serve `/repo/` bridge + the plugin's own `SourceSyncCore` (32 files drifted, config fill-forward: 0 keys added). Owner must **Ctrl+S**.
- Place-level CanvasGroup budget notes (see `UPGRADE_PROGRESS.md`): two identical poster sets (`Workspace.Top*` and `hazastudioBoard.Top*`), duplicate `04-AdminPanel`/`DancePanelGUIWrapper*` GUIs. Engine now culls far SurfaceGuis (17/20 released at spawn), but deleting the duplicate set is still worth doing.

## F/G. Donation + Community backend — clubkit-infra (self-hosted VPS)

Same backend as Hierapolis/NotCyrus (`103.42.244.55`, `api.hazastudio.id`, DB `/var/lib/clubkit/db.sqlite`, service `clubkit-api` on bun).

Game key **`rust`** (`games.id = 2`) was already registered on the VPS with a data snapshot up to 2026-08-20; the place itself still pointed at the retired Cloudflare worker until 2026-08-27.

Done 2026-08-27:
- `ClubKitConfig.Donation.ApiUrl`: `https://hazastudio-donation-api.hazastudio.workers.dev/game/rust` → **`https://api.hazastudio.id/game/rust`** (only value changed in the buyer file). `Donation.ReliabilityV2 = true` was already set → `/v3/deliveries|delivery-ack|delivery-display|delivery-dlq` active; runtime confirmed `RELIABILITY_V2_ENABLED=true`, live poll `200`.
- `Secrets.DonationApiSecret` / `GameDataApiSecret` were **already valid on the VPS** (same values as the old worker registration) — no secret change. `GameDataApi.GameKey = "rust"` unchanged.
- **Data migration (delta):** reconciled by `provider_tx_id` — VPS had 430 of the old worker's 434 rust donations, 0 amount mismatches, 0 stray rows. Imported the 4 missing (2026-08-22: Ryzzol 100,708; Suebetdah 50,354; utramennnnn_816 2×50,354) with `INSERT OR IGNORE`. After: **434 donations / Rp 40,381,041 / last_at 2026-08-22T14:05:22Z**, `pragma integrity_check = ok`. Backup: `/var/lib/clubkit/backups/db-pre-rust-import-20260827-091537.sqlite`.
- **Dashboard owner login** (`customer.hazastudio.id`, `owner_users.id = 12`): username `rust`, password set by owner request (`bun scripts/seed-owner.js rust rust <pw>`).
- **TODO (owner-side, required):** paste the Saweria webhook URL `https://api.hazastudio.id/webhook/saweria/rust/<webhook_token>` into the Saweria dashboard for `saweria.co/rustwarehouse`. Token: `sqlite3 /var/lib/clubkit/db.sqlite "select webhook_token from games where game_key='rust'"` on the VPS (or `GET /admin/games/rust`). **Until this is done, new donations keep landing in the old worker's D1**, which is exactly why the VPS snapshot had drifted.
- Not enabled on VPS for rust: `groups endpoint` (`/social/game/rust/groups/*` → 403 "groups endpoint not enabled for this game"). Kit falls back to `GroupService`; enable via admin API if overhead group-rank lookups are wanted.

## Old worker

`hazastudio-donation-api` (Cloudflare D1 `donation_db`) still runs and still holds rust rows; left untouched as fallback. `provider_link` on the VPS row is `https://saweria.co/rust` while the place config says `saweria.co/rustwarehouse` — cosmetic, but worth aligning via `PATCH /admin/games/rust`.

## Open items

- [ ] Owner: Ctrl+S / publish the updated place
- [ ] Owner: paste Saweria webhook URL (see above)
- [ ] Remove duplicate poster set / duplicate GUIs in the place
- [ ] Align `provider_link` on VPS with `saweria.co/rustwarehouse`
