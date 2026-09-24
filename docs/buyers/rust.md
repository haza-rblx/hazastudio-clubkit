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

## 2026-09-19 — baseline before a cherry-picked engine update

**Nothing has been written to the place.** Everything below is read-only observation, recorded so
the pre-update state is recoverable if the selective update goes wrong.

**Place renamed since the last visit.** The Studio window now reports
`[Rap/Rnb/HipHop] BACKHOME` (file title `Place1`); `PlaceId` is unchanged at `85501880339890`,
and the kit still identifies as RUST (`Branding.GameName = Rust Warehouse`,
`Donation.ApiUrl = https://api.hazastudio.id/game/rust`).

**Engine as found:** `KitProduct.KitVersion = 2.9.2`, **400** LuaSourceContainers across
`ReplicatedStorage` / `ServerScriptService` / `StarterPlayerScripts` / `ReplicatedFirst`.
There is **no `ClubKitManifest`** in this place — it postdates 2.9.2 — so `KitProduct` is the only
version marker here. `ServerStorage.Hazastudio_ClubKit` does not exist.

**The owner has already pasted newer GUIs in, and the old ones are still beside them.**
StarterGui holds both copies of three surfaces:

| New GUI (pasted in) | Old GUI still present | Engine support at 2.9.2 |
|---|---|---|
| `04-AdminPanelv3` | `04-AdminPanel`, `04-AdminHub` | **Missing** — no `AdminTitleV3Controller`, no `AdminPanelV3UI` |
| `99-NotificationCenterV2` | `99-NotificationCenter` | **Missing** — no `NotificationCenterGui`, no `GuiFade` |
| `AvatarContextMenuV2` | `AvatarContextMenu` | Present (`AvatarContextUI`, `InventoryChromeAnimator`) |
| `07-MenuGUI` | — | Present (`MenuShellUI`, `MenuGuiRefs`, `SettingsMenuUI`, `MenuSettingsCore`) |
| `MobileFreecam` | — | Present (`MobileFreecamController`, `FreecamConfig`) |

So only **two** of the pasted GUIs are actually dead: `04-AdminPanelv3` and
`99-NotificationCenterV2`. Two copies of one surface both living in StarterGui is its own problem
(both clone into PlayerGui) and is worth cleaning once the new ones are proven.

**Distance to the repo:** 2.9.2 → `v2.12.0` is **79 files of 447** (28 added, 51 modified).
RUST already carries 3 of the 28 (`GroupMotionPolicy`, `CanvasGroupBudgetService`, `GroupMotion`)
from the 2026-08-27 pass, so 25 are genuinely absent.

**The repo working tree is not a valid source for this place.** It sits on branch `ui-motion`
with ~99 dirty files of unreleased work (UI motion, music v3 web-only, donation effect theming).
Any sync to RUST must come from tag **`v2.12.0`** (`aaca1f9`).

### Owner decision (2026-09-19): two clusters only, not the full update

Take the Title v3 and Notification clusters — what the pasted GUIs need — and leave the
integrity / anti-abuse cluster (`RuntimeGuard`, `MovementGuard`, `TamperGuard`,
`IntegrityTripwire`, `AvatarPolicy`, `MovementPolicy`, `SaveInstanceGuardService`,
`BootHaltedNotice`, `Notice`) out.

**Verified cut line — it is clean.** None of the 13 modified support files reference any of the
9 skipped anti-abuse modules. The only extra file dragged in is `OverheadLayerPolicy` (ADR 0009),
named by `OverheadDomain`, `ConfigBootstrap` and `OverheadUI`.

Planned scope: **32 files** — 28 copied verbatim from `v2.12.0`, and **4 wiring files hand-merged**
(`Main.client`, `Main.server`, `ClientModuleBag`, `ServerModuleBag`), because 2.12.0 interleaves
both clusters' wiring in the same files: `Main.client`'s +96 lines carry
`SaveInstanceGuardService` and `BootHaltedNotice` (ADR 0006) right next to
`AdminTitleV3Controller`. Those hunks are deliberately skipped.

**Known cost, accepted:** the result is a mixed build that no release note describes.
`KitProduct.KitVersion` will be neither 2.9.2 nor 2.12.0 honestly, and the next Update Engine run
cannot infer what is here. This section is the record that makes it recoverable.

### Two defaults that would change behaviour if the FULL update were ever taken

Not in scope now, but do not rediscover them later: `Overhead.GuiType = "V4"` and
`Graphics.DefaultPreset = "Low"` are new schema defaults that fill forward into existing buyers.
The new *features* all default off (`AdminPanelV3 = false`, `SelfCustomTitle = false`,
`HierapolisCustom = false`), so nothing switches itself on.

### Outcome (2026-09-19) — applied to the place, NOT yet saved

**69 engine files written**, all verified by reading `Source` back and comparing length; 1 new
(`WorldGraphicsService`), 68 overwritten. Playtest after: **0 module-load errors**.

Scope grew from the planned 32 to 69 for a reason worth keeping. The first attempt shipped 33
files and **crashed on boot**: `ConfigBootstrap:463: attempt to call a nil value`, because 2.12.0
calls `GraphicsQuality.resolvePreset` and RUST still had the 2.9.2 `GraphicsQuality`. My closure
check had verified every dependency **existed** — it never checked that the existing module had
the *functions* the new code calls. A sweep for that class of skew found four more candidates
(`GroupMotion.scaleTarget` real; `MovementGuard.stampTeleport` and `LicenseService.reportTamper`
comment-only). The fix was to stop hand-picking: take **all 79 changed files minus the 9
anti-abuse ones**, which removes the whole failure mode instead of patching instances of it.

Excluded by choice (9): `RuntimeGuard`, `MovementGuard`, `TamperGuard`, `IntegrityTripwire`,
`AvatarPolicy`, `MovementPolicy`, `SaveInstanceGuardService`, `BootHaltedNotice`, `Notice`.
Their wiring was cut by hand from `Main.client`, `Main.server` and `ServerModuleBag`; verified
absent from the place afterwards. (`Icon.Elements.Notice` shows up in a name search and is
TopbarPlus's, not the kit's.)

`WorldGraphicsService` had to come in after all: `SettingsController` requires it outright.

**`KitProduct.KitVersion` now reports 2.12.0** — nearly true, and more useful to a future Update
Engine run than 2.9.2 would be. What it overstates is exactly the 9 files above.

**Buyer config edited (targeted, not replaced):** `AdminPanelV3 = true` and
`ImageCustomTitle = false` inserted into `ClubKitConfig.Features`. `AdminHub` stays `true`, so the
Hub keeps the topbar icon and its "title panel" action opens v3 — that is the engine's intended
arbitration (`adminPanelV3Owns` is false whenever the Hub is on), not a misconfiguration.

**Image titles locked, verified both sides.** Client: on a fresh clone of the owner's GUI,
`_imageLocked = true`, `setTab("text")` leaves `LockedState.Visible = false`, `setTab("image")`
raises it to `true`, and back again. On the live panel the owner's frame — which ships
`Visible = true` in StarterGui — was `false` after boot, proving the patch runs. Server:
`FeatureFlags.ImageCustomTitleEnabled = false` and both gates present in the running
`AdminController`.

**Not proven:** the server refusal was confirmed by flag and by source in the live build, not by
firing the remote end to end.

#### Overhead switched to V5 (2026-09-19)

`ClubKitConfig.Overhead = { GuiType = "V5" }` added as a new top-level section - the buyer file
had no `Overhead` block at all, so fill-forward had been handing it the V4 default.

**Safe here because both templates are installed.** `OverheadGUIMainTemplateV4` *and*
`OverheadGUIMainTemplateV5` already sit in this place's ReplicatedStorage (the templates are place
data, not repo files). That check matters: the config's own note warns that a version you have not
installed falls back, and V5 is the only variant that carries the image row.

**V5 is V4 plus `02-AddOnCustomImageBadge`, and that row hides itself when no image is set** -
`OverheadUI` computes `imageVisible = imageId ~= nil and ...`. So with `Features.ImageCustomTitle`
off, V5 renders exactly what V4 did: no empty gap, no layout shift. The two settings are coherent
rather than contradictory - the capability is installed and the door stays shut until the add-on
is sold for this venue.

Verified in a playtest: `Overhead.GUI_TYPE = V5`, `Template.TEMPLATE_NAME =
OverheadGUIMainTemplateV5`, the nametag on the character is a `OverheadGUIMainTemplateV5`
BillboardGui adorned to `Head`, its image row present with `Visible = false` and `Image = ""`, and
the visible rows are the expected `02-BadgeGroup, 03-Level, 08-DisplayNameAndMembership`.
`OverheadService`/`OverheadController` log normal payload builds and broadcasts, no errors.

**Not verified visually.** Screenshots came back black: the test character spawns at `y = 0.33`,
apparently under the map, and brightening Lighting did not help. The evidence above is structural.
#### Rebranded RUST -> BACKHOME (2026-09-19)

The place was already renamed `[Rap/Rnb/HipHop] BACKHOME`; the kit still said Rust. A sweep of
StarterGui, Workspace, ReplicatedStorage, ServerScriptService, ServerStorage, StarterPlayer,
Lighting and Teams found the identity lives **only** in `ClubKitConfig` - everything else that
matched "rust" was a false positive (`Thruster`, `Trusted`, Kohl's Admin's "Rust" paint swatch,
`BodyThrust`). There are no Teams in this place.

**Changed (3 display strings):** `Branding.GameName` -> `BACKHOME`, and `WelcomeMessage` /
`Greeting` -> `Welcome to BACKHOME, %s`. Verified live: `Config.Branding.GAME_NAME`,
`Config.Loading.PRIMARY_GREETING` and `Config.Loading.WELCOME_DISMISS_FORMAT` all read BACKHOME.

**Deliberately NOT changed (3 backend keys).** These are plumbing, not display, and renaming them
is a VPS migration rather than an edit:

| Key | Value | Why it stays |
|---|---|---|
| `GameDataApi.GameKey` | `rust` | Must match `SECRET_<GAME_KEY>` on the backend. |
| `Donation.ApiUrl` | `.../game/rust` | The VPS game slug: licence, webhook token and ~435 donations hang off it. |
| `Donation.ProviderLink` | `saweria.co/rustwarehouse` | The venue's real Saweria page. Only change it if the owner actually moved the page, otherwise donations break. |

Nothing player-facing shows the game key, so leaving it is free. Nine derived `Config.Donation.*`
/ `Config.GameDataApi.*` strings still read `rust` for the same reason - they are computed from
those three.

**Player data was never at risk:** DataStore names are fixed literals (`Profile_v1`,
`Settings_v1`, ...) with only an optional `Studio_` prefix. They do not derive from GameName or
GameKey, so a rename cannot orphan saves.

**Licence still active after the rename** - `status = active`, `enforcementActive = true`.

**Probe trap worth remembering:** `execute_luau` (either Studio MCP) has its **own module cache**,
so `require(LicenseService).getState()` through it returns a *fresh* module reading
`status = unknown, checkedAt = 0` - which looks exactly like a dead licence. Only
`eval_server_runtime` / `eval_client_runtime` share the live VM's cache. Read live service state
through those, never through `execute_luau`.

**The logo: found by looking, then superseded by the owner.** A text sweep cannot see a logo, so
`Branding.LogoImage` was checked by asset instead: `rbxassetid://95233556749869`, whose asset name
is literally "logo rust fix" and whose thumbnail is the RUST wordmark. It is applied **at runtime
from config**, so no instance references it statically and searching the place for "rust" never
surfaces it. **Superseded the same day:** the owner swapped `LogoImage` to
`rbxassetid://87764442247415` (a texture their group uploaded 2026-09-19 10:48), and the loading
screen now renders the BACKHOME wordmark. Nothing left to do here.

**Side finding, not acted on:** there are two Secrets modules -
`ServerScriptService.Hazastudio_ClubKitSecrets.Secrets` and a nested
`...Hazastudio_ClubKitSecrets.Model.Secrets`. Both carry non-empty 36-character values. The nested
one looks like leftover packaging from an `.rbxm` insert; worth deleting once it is confirmed
nothing requires that path.
#### Final verification playtest (2026-09-19) - all green

| Check | Result |
|---|---|
| Module-load errors | **0** |
| `KitProduct.KitVersion` | 2.12.0 |
| `Branding.GAME_NAME` / `Loading.PRIMARY_GREETING` | BACKHOME / `Welcome to BACKHOME, %s` |
| `AdminPanelV3Enabled` / `AdminHubEnabled` | true / true |
| `ImageCustomTitleEnabled` | false (locked) |
| `Overhead.GUI_TYPE` -> template | V5 -> `OverheadGUIMainTemplateV5` |
| Nametag on character | `OverheadGUIMainTemplateV5`, image row present and `Visible = false` |
| Licence | `active`, `enforcementActive = true`, no error |
| `Donation.API_URL` | still `.../game/rust` (deliberate) |
| 9 new client modules | all present, all `require` without error |
| Anti-abuse modules | none leaked in |
| Topbar | 13 icons |

**The notification cluster was exercised, not just inventoried:** calling `NotifService.success`
took the visible node count from 34 to 35 and the text rendered into
`GeneralNotificationCenter.NotificationWrapper.NotificationDescription`. Both cherry-picked
clusters are therefore proven live, not merely installed.

**StarterGui went 29 -> 26 children during the session.** The owner deleted `99-NotificationCenter`,
`04-AdminPanel` and `AvatarContextMenuV2` by hand (confirmed). The first two were the superseded
duplicates. `AvatarContextMenuV2` was inert anyway - `Features.AvatarContextMenuV2` is `false`, so
the kit keeps using v1 `AvatarContextMenu`; running ACM v2 would need both the GUI reinstalled and
the flag turned on. A copy is in `Desktop\RUST-backup-2026-09-19\RUST-guis-PRE-UPDATE.rbxm`.
#### Loading screen was skipping: `LoadingBootstrap` had `Disabled = true` (2026-09-19)

Owner reported the loading screen going straight past. Config was innocent -
`Features.LoadingScreen = true`, `INTRO_MIN_DURATION = 5`, `MINIMUM_DURATION = 2`, the
`00-LoadingScreen` GUI complete, and `LoadingBootstrap` logged none of its two failure warnings.

Config could not settle it, so it was **measured**: a temporary probe in `ReplicatedFirst`
timestamped the boot. `00-LoadingScreen` only reached PlayerGui at **17.1 s**, already
`Enabled = false`, and never turned on - that is ordinary StarterGui replication, not the
bootstrap's own clone. The giveaway: `LoadingBootstrap` clones the template and then does
`template.Parent = nil`, yet `StarterGui.00-LoadingScreen` was still present, so the clone branch
was never reached.

Cause: **`ReplicatedFirst.Hazastudio_ClubKit.LoadingBootstrap.Disabled = true`** - the only
disabled script in the whole kit. Not from this session's sync: that file does not differ between
2.9.2 and 2.12.0, so it was never in the 69 files written, and the sync only ever assigned
`.Source`, never `Disabled`. It predates this work.

Fixed by setting `Disabled = false`. Verified by screenshot: the loading screen renders, showing
the BACKHOME logo and **"Welcome to BACKHOME, bangbasobang"** with its tip line. The temporary
probe was removed.

**Lesson for the next one:** a disabled script produces no error and no warning. It looks exactly
like a feature that was configured off. Check `Disabled` on the entry-point scripts before
trusting the config.
#### Join Community GUI is empty: the social worker is down, not the place (2026-09-19)

Owner saw the community GUI empty and the kit falling back to roproxy. **The kit's config is
correct and nothing here needs changing.** Probed from Edit mode (no playtest, so no live
DataStore writes), with the secret used but never printed:

| Probe | Result |
|---|---|
| `/social/game/rust/community/763632944` (correct secret) | **502** `{"ok":false,"error":"roblox_unavailable"}`, 3/3 tries |
| same, group `1` (Roblox's own) | 502 `roblox_unavailable` |
| same, group `504061531` (NIGHT ZONE) | 502 `roblox_unavailable` |
| same, deliberately wrong secret | **401** `unauthorized` |
| `https://api.hazastudio.id/social` bare | 404 JSON |

Auth and routing are fine - a wrong secret is rejected and a right one gets past it, so
`GameKey = "rust"` and `GameDataApiSecret` are both valid on the social service. The failure is
the **worker's own upstream call to Roblox**, and it fails for *every* group, so it is not
group-specific, not key-specific, and nothing to do with the BACKHOME rename. **It will be hitting
every buyer that uses this endpoint, NIGHT ZONE included.** Look at the Open Cloud key (expired /
revoked / wrong scopes) or VPS egress.

**The roproxy fallback is dead too, upstream:**

| Endpoint | Result |
|---|---|
| `groups.roproxy.com/v1/groups/763632944` | **429** rate limited (this is the member-count source) |
| `.../groups/763632944/users?limit=10` | **400** "The user is invalid or does not exist" - Roblox retired this route |
| `.../groups/763632944/roles` | 200, works fine |

So the member *samples* that fill the GUI's profile photos have no working source at all: the
worker 502s and the roproxy route that used to supply them no longer exists on Roblox's side.
That makes the VPS worker the only viable path, and `Config.GameDataApi.MEMBER_USERS_URL`'s
default is pointing at a route that cannot come back. Worth revisiting kit-side once the worker
is healthy.
#### Still open

- [ ] **Owner: Ctrl+S.** Every change above lives only in this edit session.
- [ ] **VPS: fix the `/social` community worker** (502 `roblox_unavailable` for every group). Affects all buyers, not just this one.
- [ ] Kit: `MEMBER_USERS_URL` defaults to a Roblox route that now returns 400; the roproxy fallback for member samples can no longer work.
- [ ] Eyeball one nametag in a lit spot to confirm V5 looks like V4 did.
- [x] BACKHOME logo supplied by the owner (`rbxassetid://87764442247415`); loading screen shows it.
- [ ] Decide whether the VPS game record should be *displayed* as BACKHOME (its key stays `rust`).
- [ ] Confirm the Saweria page is still `saweria.co/rustwarehouse` under the new brand.
- [ ] Remove the duplicate nested `Hazastudio_ClubKitSecrets.Model.Secrets` if nothing requires it.
- [x] Duplicated old GUIs removed by the owner (`04-AdminPanel`, `99-NotificationCenter`).
- [ ] Backups sit at `Desktop\RUST-backup-2026-09-19\` (engine + GUIs as `.rbxm`).
- [ ] This is a mixed build. A future full update should take the 9 anti-abuse files as one step.
