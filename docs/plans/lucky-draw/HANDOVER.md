# Lucky Draw (random pick a player): handover, 2026-10-19

This is an experiment. It lives only in the Studio place **"hazastudio Experiment Area"** (placeId 75916114543452). Nothing is in `src/` yet. The prototype sources are copied into [`prototype/`](prototype/) for reference.

## What it is
An admin opens **Lucky Draw** from the Admin Hub (Admin Spotlight) and presses **Spin**. The server picks a random player and broadcasts the result. Every client then sees:
1. **Panel** (host): a horizontal reel slides and lands with the winner centred.
2. **Toast** (everyone): "<host> is spinning!", a mini reel, then "<winner> won!".
3. **3D world effect** on the winner's character (3 variants, not chosen yet).

## Current state in the place
| Thing | Where (place) | Status |
|---|---|---|
| Static GUI (owner's manual design) | `StarterGui.LuckyDrawGui` | In Edit, `Spotlight` beams removed (2026-10-19). **Owner must Ctrl+S.** |
| Server | `ServerScriptService.LuckyDrawServer` + `ReplicatedStorage.LuckyDrawRemotes` (`Request`, `Broadcast`) | In Edit |
| Client binder | `StarterPlayerScripts.LuckyDrawClient` | In Edit, identical to `prototype/LuckyDrawClient.luau` (2026-10-19) |
| Winner 3D FX | `ReplicatedStorage.LuckyDrawWinFx` (ModuleScript) | In Edit, identical to `prototype/WinFx.luau` (2026-10-19) |
| Admin Hub option | `AdminHubController` (`ACTIONS` + `handleAction` branch) and `AdminSpotlightUI` (`ACTION_META` + `ACTION_ORDER`) | Edited **in the place only** (engine scripts). Overwritten by the next repo sync |
| Old experiments (parked) | `ServerStorage._GachaExperiment_old`, `ServerStorage._GachaExperiment_v2parked` | Can be deleted |

### Apply to Edit: done 2026-10-19, save pending
Client, WinFx and the beam removal were applied via `ScriptEditorService:UpdateSourceAsync`. Remaining:
- **Save the place (Ctrl+S).**
- Optional: attribute `WinFxVariant` (1–3) on `ReplicatedStorage.LuckyDrawRemotes` (defaults to 1).

Hot-load trick (Play, no stop): serve the folder at `127.0.0.1:8765` → Server DM `HttpService:GetAsync` → StringValue → client destroys the old `LuckyDrawClient`, `Open`/`TestWinFx` events and `Strip*`/`Idle*` tiles, then creates the script with `.Source`. **Never swap mid-spin**: the old script has detached the `Rows` `UIListLayout`, and the new one then finds none (tiles pile up on the left). Repair from the StarterGui design (layout + `Face.Size`) before swapping.

## Design decisions (owner, this session)
- Visual language = the **Custom Title panel** (`1000-01-CT-ADDON`): card `#070707` r32, stroke `#1a1a1a`, header pill, Inter, purple gradient CTA `#6214FF→#110042`, root UIScale **0.88** (phone 0.55, as in `MobileScaleService`).
- Take only the **layout** from references, never copy them exactly. A full-screen takeover and five generic modals were both rejected as ugly.
- Reel is **horizontal**: 3 tiles, centre tile emphasised (60 face, white ring), sides smaller and dimmed **by colour, not transparency** (thin transparent text looks broken).
- The **flat 2D spotlight cone** was liked, then removed ("beam nya ilangin"). Currently there is no beam.
- **No scale-in/out** on spawn. Panel slides up into the **centre**, toast drops in **top-centre**.
- No text below ~12 px on screen. Avoid nested UIScale.
- Progress is not a bottom bar. It was tried as the toast cone filling, then the cone was removed. **There is currently no progress indicator.** Revisit.
- **Photo only until the result** (2026-10-19): no names in idle or while spinning. On landing, **only the winner's** display name and @username fade in (0.35 s) while that tile glides up so photo plus names are centred. After the restore, the panel keeps the winner's names in the centre; the sides stay photo only.
- **Photos 1.3×** (`FACE_SCALE`), side:centre ratio kept. Panel 44→57 / 60→78, toast 40→52 / 54→70.
- While spinning, every photo is centred on the reel line (tiles are top-aligned, so Y is computed per frame from the face size).
- **Idle panel = slow drift**: equal-size photos (side size), no names, moving left at `IDLE_SPEED` 24 logical px/s; a tile re-entering on the right takes the next player. Stops when a spin starts; restarts each time the panel opens. In solo Studio it shows only real players (repeats your face); the spin pool is padded with friends. Idle→spin is a hard swap (no ramp-up yet).

## Server rules (`LuckyDrawServer`)
- Admin gate: `GetRankInGroup(Config.Group.GROUP_ID)` → `OverheadDomain.resolveRole` → `PermissionDomain.canUseAdminPanel`. In Studio, `game.CreatorId` is allowed. *(When porting: use the kit's `overheadService:getEffectivePayload` like `CinematicDockController`.)*
- Rejects while a spin is in flight, 1 s cooldown. Pool = `Players:GetPlayers()`. **In Studio it is padded to 12 with the host's friends** (`fake=true`). The FX fall back to the local character for fakes.
- Broadcast `{type="spin", host, pool, winnerIndex, seed, startAt = GetServerTimeNow()+0.35, duration = 4.6}`. Clients animate in sync from `startAt`.

## Session 2026-10-19 (later): playtest only, NOT in Edit yet
- **Toast header removed** (owner): `Toast.Title`, `CloseWrapper`, `Icon` → `Visible=false`; `MiniReel.Position` `{0,8},{0,8}`; `Toast.Size` `{0,300},{0,168}` (was 208). Apply to `StarterGui.LuckyDrawGui.Toast` in Edit (or delete those three).
- **WinFx = 5 cinematic variants** (`prototype/WinFx.luau`, tested in playtest, no errors): 1 Crown Descent, 2 Supernova, 3 Club Takeover, 4 Ascension Vortex, 5 Time Freeze. Shared layer: Scriptable camera shot per variant, letterbox, 0.6 s eased hand-back, 6.5 s. Known flaw: Time Freeze greys the Highlight too (ColorCorrection is full-screen). Old 3 variants kept as `prototype/WinFx_old3.luau`.
- Owner then asked for **spotlight-only** effects → `prototype/WinFx_spotlight5.luau` (UNTESTED): 1 Follow Spot, 2 Sweep & Lock, 3 Halo Truss, 4 Backlight Fan, 5 Runway. Same API and cinematic layer. Next: hot-load into playtest, owner picks.
- Test UI: a temporary `PlayerGui.WinFxTester` (5 buttons → `TestWinFx:Fire(n)`), playtest only.
- Edit still has the **old 3-variant** `LuckyDrawWinFx`. Apply the chosen file with `UpdateSourceAsync` after stopping Play.

## Installed in NIGHT ZONE (placeId 140556013758180), 2026-10-19
First real venue install, right after the NZ 2.10 → 3.0 upgrade. Copied from hazastudio Edit: `LuckyDrawGui`, `LuckyDrawRemotes`, `LuckyDrawServer`, `LuckyDrawClient`, plus the Admin Hub row (AdminHubController/AdminSpotlightUI identical to hazastudio). NZ-only differences:
- `LuckyDrawWinFx` = **mixed5** (`prototype/WinFx.luau`), default variant 1 (Crown Descent); switch with attribute `WinFxVariant` 1–5 on `ReplicatedStorage.LuckyDrawRemotes`.
- Toast header removed in Edit (Title/CloseWrapper/Icon hidden, MiniReel `{0,8},{0,8}`, Toast `{0,300},{0,168}`).
- Server admin gate prefers `player:GetAttribute("_LKG_Role")` (the kit's effective role, set server-side by OverheadService: covers `/setrole` and spender roles), and falls back to the group rank. Port this to hazastudio and to `prototype/LuckyDrawServer.luau`.
- Playtest: spin broadcast OK, toast shows and hides, camera Scriptable for about 5.5 s then back to Custom, no RuntimeGuard or ForeignGui flags. Not yet done: an on-screen check of the Admin Hub row, a 2-player test, a non-admin rejection test.

## Winner 3D FX (`WinFx.play(variant, character)`): pick one
- **V1 Stage Spot**: tapered Beam from above, SpotLight, floor discs, the world dims (ColorCorrection).
- **V2 Ascension Pillar**: Beam pillar rising white→purple, Highlight, sparkles. Shockwave discs are barely visible (known weak spot).
- **V3 Searchlight Sweep**: 3 searchlights sweep and lock onto the winner, multi-colour confetti, "WINNER" billboard (visibility not confirmed; it overlaps the kit nameplate).
- Assessment: V3 is the most dramatic and V1 the calmest. V1/V2 shafts still read a bit flat from the front.
- Test hook: `PlayerGui.LuckyDrawGui.TestWinFx:Fire(n)`.

## Open issues / next steps
1. Owner picks a WinFx variant (or iterates).
2. Save the place (Edit is already applied).
2b. **Toast flicker, top-left, at spin start** (owner report, parked to save tokens). Per-frame probes found nothing out of place: no ghost tiles, toast children stable from frame 1, only frame 1 shows an empty reel. Next: get the owner's frame-stepped recording (Win+Alt+R), or cheaply prepare the reel (`beginReel` + one `stepReel`) before `toast.Visible = true`.
3. Admin Hub row: in code, but **not seen on screen yet** (the Spotlight builds rows when opened). Test it manually.
4. Decide a progress indicator for the toast.
5. Multi-player test (2+ clients): sync, toast for spectators, non-admin rejected.
6. **Porting to the repo** = non-trivial, so run grill-with-docs first:
   - The Admin Hub edits go into `AdminHubController`/`AdminSpotlightUI` (watch the register budget, ADR 0002; add no top-level locals).
   - Remote names → `Config` + `Init/EarlyRemotes.luau`. Server controller via `ServerModuleBag` (not new locals in `Main.server`).
   - GUI: the static `LuckyDrawGui` is place data (same pattern as the CT addon) → release surface = RBXM/manual, plus a binder that tolerates missing refs.
   - No DataStore, no buyer-file changes so far.
7. Delete the parked `_GachaExperiment_*` in ServerStorage.

## Files
- `prototype/LuckyDrawClient.luau`: client binder (latest = Edit copy; centre/top-centre spawn, logical-unit geometry, ghost-tile fix, WinFx hook, photo-only reel with winner-only names, 1.3× photos, idle drift).
- `prototype/LuckyDrawServer.luau`: server.
- `prototype/WinFx.luau`: 3D effects.
- `prototype/BuildStaticGui.luau`: builder for the **original** round-2 static GUI. It does **not** include the owner's manual edits (horizontal reel and so on). The real design is `StarterGui.LuckyDrawGui` in the place.
- Scratch history: `.tmp/gacha-ct/` (gitignored).
