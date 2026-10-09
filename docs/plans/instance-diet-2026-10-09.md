# Instance diet — plan (2026-10-09)

**Goal (owner):** cut instance counts hard ("menurunkan instances brutal"). The owner accepts cutting non-essential features for performance.
**Status:** planned. No code changed yet.
**Executor notes:** this plan is written so a fresh agent can execute it phase by phase. Do the phases in order and finish each one's acceptance check before starting the next. Ask the owner only where the text says **ASK**.

---

## 0. Read this first

### 0.1 The metric

The number the owner sees in F9 (Developer Console) is **`Stats.InstanceCount`**. `#game:GetDescendants()` is a different number and must not be quoted on its own.

Measured in an Experiment Area solo playtest, 25 s after Play:

| | Client | Server |
|---|---|---|
| `Stats.InstanceCount` | **67,540** | **79,799** |
| `#game:GetDescendants()` | 24,755 | 37,031 |
| gap (outside the tree walk) | ~42,800 | ~42,800 |

- The gap is made of nil-parented instances, engine internals and protected CoreGui. How much of it the kit owns is **unknown** until Phase 0 measures an empty place.
- In Edit mode the gap is only about 1.5k.
- Earlier in the same conversation, a session used `GetDescendants` and derived per-player numbers such as "575k at 100 players". **Those numbers are wrong. Do not reuse them.**

Facts that matter for the maths:

- **PlayerGui**
  - Each client holds only **its own** PlayerGui.
  - The **server** holds a PlayerGui copy for **every** player: about 5,755 instances each in Experiment Area. So that cost grows with player count on the server.
- **PlayerScripts** exist only for the local player. They are not a cost per other player.
- **Per other player on a client** (the snowball):
  - Live PARKLAB: about **1,050** per player (140–148k at about 57 players, read from F9 via computer use, 2026-10-09 earlier session).
  - Empty place (Place1): about **400** per player, which is the bare avatar.
- **Tools** (`RoleToolService`) are cloned into **both** Backpack and StarterGear, so each grant exists twice.
  - Guests with no role folder get none.
  - The owner in Studio gets about 211 instances per container.
  - Whether other players' Backpacks replicate to every client is **unverified**. Phase 1 answers it.

### 0.2 Owner decisions (2026-10-09)

- **Q1 target**
  - Client solo `InstanceCount` ≤ **40k**.
  - Cost per other player ≤ **600**.
  - This target is provisional. If Phase 0 shows that an empty place already sits near 40k, **re-state the target as "empty-place floor + kit budget" and tell the owner**. Do not chase an impossible number.
  - **Re-stated 2026-10-09 (Phase 0):** the empty place (Place1) floor is client 48,325 / server 46,085 `InstanceCount`, which is above 40k, so the 40k target is withdrawn. Proposed: client solo `InstanceCount` ≤ floor + **N** (kit + experiment budget). Experiment Area is at 73,867 client, about 25.5k above the floor today (this includes place-only experiment GUIs such as DJGUI).
  - **Decided 2026-10-10 (owner delegated the call: "all yours"):**
    - **Primary target: cost per other player ≤ 600** (unchanged). This is the cost that grows at 57–100 players. Phase 1 telemetry measures it.
    - **Solo: N = 23,000**, so Experiment Area client solo ≤ ~71.3k (−2.5k). This is about what Phases 2–4 can remove in a solo test. In Studio the tester is an admin, so admin-panel savings only show for non-admins.
    - **Stretch: N = 16,000** (≤ ~64.3k). This needs the leaderboard-board backlog item (about 7.4k on every client, the biggest single lever), which the owner deferred. Raise it with the owner once Phase 1 data is in.
    - Re-check N after the first Phase 1 data.
- **Q2 telemetry:** yes. It is temporary and must be toggleable: one engine flag turns it off, and the buyer's `ClubKitConfig.Telemetry.Enabled` still has the last word.
- **Q3 cuts**
  - **Sticker is removed completely**: code, GUIs, remotes and config.
  - Also delete the **backup folders** in Experiment Area's ServerStorage.
  - Every other feature cut is **deferred** ("lainnya nanti dulu").
- **Q4 tools:** approved. Tools stop filling the Backpack and are granted when used. This is gated on Phase 1 data.
- **Q5 release surface** (moving GUIs out of StarterGui means a manual or RBXM step for buyers): **decided later**. Do the lazy-GUI work anyway ("di-lazy-in sekalian"). Phase 3 is designed so that it needs **no buyer GUI edits**.

### 0.3 What already exists — do not rebuild

`Config.ClientFootprint` (Config.luau ~L4545), built 2026-10-07:

- `TRIM_STARTER_GUI`: StarterGuiTrimService empties StarterGui templates on the client after boot.
- `TRIM_LEADERBOARD_ROWS`
- `LAZY_PANEL_ROWS`: generated rows are built on first open.
- `DEFER_EFFECT_SOUNDS`

Also on: `Config.Overhead.ENABLE_LAZY_ROWS` (overhead rows pooled while hidden).

`Server/Net/BudgetTelemetry.luau` already POSTs aggregates to `{ApiUrl}/v3/telemetry` through `BackendClient`, using `kind = "budget"` every 15 min. Phase 1 copies its pattern.

### 0.4 Hard rules and traps

- **Buyer-owned files.** Never edit a buyer's `ClubKitConfig.luau` or `Secrets.luau` (ADR 0001).
  - The repo copy `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` is the **template**. Edit it only together with `ClubKitConfigSchema`.
  - Retired buyer keys go into `ClubKitConfigSchema.RETIRED_KEYS` (~L812).
- **Register budget** (ADR 0002). New modules go through `Server/Init/ServerModuleBag.luau` or `Client/Init/ClientModuleBag.luau`. Run `.\tools\count-locals.ps1` after touching `Main.server` or `Main.client`.
- **DataStore keys.** Do **not** delete or rename `StickerCollection_v1`. Leave the data in place and only stop reading it.
- **Experiment Area is "full feature" and has place-only edits.**
  - Do not strip GUIs there except where this plan says so.
  - Some GUIs there are owner experiments and **not kit**: `DJGUI` (1,736 instances), `17-OnboardingGUI`, and others. Exclude them when attributing kit cost.
  - See memory `experiment-area-place-only-edits.md`.
- **No multi-client Studio playtests** (owner rule, memory `no-multiplayer-playtest.md`). Per-player growth comes from live telemetry, never from solo extrapolation.
- **Writing `Config.luau` into Studio.** The file is larger than 200k chars, so `.Source =` is refused. Use `ScriptEditorService:UpdateSourceAsync`. For the repo→place sync recipe, see memories `delivery-pack-recipe.md` and `studio-mcp-classifier-behavior.md`.
- **Studio MCP**
  - `Roblox_Studio` (execute_luau, start_stop_play) is the working bridge.
  - `robloxstudio` was not connected on 2026-10-09.
  - Stop every playtest you start.
- **Destructive place edits.** The owner must Ctrl+S before you delete anything in a place, because script deletes are not in Undo. Say what you will delete and wait for an OK.
- Do not commit unless the owner asks. Add entries under `CHANGELOG.md [Unreleased]` and the `UPGRADE_PROGRESS.md` file table **as you go**, not batched at the end.

---

## Phase 0 — Baseline and engine floor (no kit change)

**Why:** the ~42.8k hidden instances decide whether the Q1 target is reachable.

### 0.A Probe snippet

Run the probe with `Roblox_Studio.execute_luau`, once with `datamodel_type="Client"` and once with `"Server"`, during a solo playtest, after `task.wait(25)`.

```lua
local S = game:GetService("Stats")
local function cnt(i) local n = 1 for _ in ipairs(i:GetDescendants()) do n += 1 end return n end
local d = #game:GetDescendants()
local out = { ("InstanceCount=%d GetDescendants=%d gap=%d"):format(S.InstanceCount, d, S.InstanceCount - d) }
local lp = game.Players.LocalPlayer -- nil on the server
local pl = lp or game.Players:GetPlayers()[1]
if pl then
	table.insert(out, ("PlayerGui=%d Backpack=%d Character=%d"):format(
		cnt(pl:FindFirstChildOfClass("PlayerGui")), cnt(pl.Backpack), pl.Character and cnt(pl.Character) or 0))
end
local t = {}
for _, c in ipairs(workspace:GetChildren()) do table.insert(t, { c.Name, cnt(c) }) end
table.sort(t, function(a, b) return a[2] > b[2] end)
for i = 1, math.min(5, #t) do table.insert(out, ("  WS %s: %d"):format(t[i][1], t[i][2])) end
return table.concat(out, "\n")
```

### 0.B Run it in three places

1. **Empty place.** The owner had `Place1` open on 2026-10-09; it is now closed. **ASK** the owner to open any empty baseplate. This gives the **engine floor**.
2. **Experiment Area.** Re-baseline. List the place-only experiment GUIs present (DJGUI, onboarding sketch, …) and their counts, so they can be subtracted.
3. *(optional)* Any clean kit place the owner can open.

### 0.C Record and re-state the target

Write the results into §Results below. If the empty-place floor is ≥ ~35k, re-state Q1 as **"kit-owned ≤ N above the floor"** and confirm N with the owner.

**Acceptance:** the §Results table is filled in, and the target is re-confirmed or re-stated.

---

## Phase 1 — Instance telemetry (temporary, toggleable)

**Why:** this is the only way to measure growth per player at 30–100 players without multi-client tests. It also answers whether other players' Backpacks replicate (Q4 gate).

### 1.A Config (engine; not a buyer key)

Add to `Config.Telemetry` in `Config.luau`, next to `BUDGET_INTERVAL_SEC`:

```lua
-- Instance-diet probe (docs/plans/instance-diet-2026-10-09.md). Temporary; flip to false to stop.
INSTANCES_ENABLED = true,
INSTANCES_SAMPLE_SEC = 60,      -- client + server sample cadence
INSTANCES_CLIENT_BATCH_SEC = 300, -- one client → server RemoteEvent per 5 min
INSTANCES_FLUSH_SEC = 900,      -- one POST per 15 min (HTTP budget rule, ADR 0007)
```

The probe runs only when **all** of these hold:

- `INSTANCES_ENABLED == true`
- `Config.Telemetry.ENABLED == true` (which `ClubKitConfig.Telemetry.Enabled` feeds)
- `BudgetTelemetry.isEnabled()` is true

### 1.B Server module

New file `Server/Net/InstanceTelemetry.luau`, `--!strict`, registered in `ServerModuleBag`.

- **Server sample, every `INSTANCES_SAMPLE_SEC`:**
  ```lua
  { t = os.time(), players = #Players:GetPlayers(), serverIC = Stats.InstanceCount, serverMemMb = Stats:GetTotalMemoryUsageMb() }
  ```
- **Client batches** arrive over **one** RemoteEvent, `InstanceProbeReport`, created in Main.server's remotes block next to the others.
  - Validate the batch: it is an array of at most 10 entries, every field is a finite number in a sane range, and there is a per-player rate limit (one batch per 240 s).
  - Drop anything else **silently**.
- **Flush every `INSTANCES_FLUSH_SEC`:** POST `{ kind = "instances", kit_version, payload }`.
  - `payload.server` is the list of samples.
  - `payload.clients` aggregates the client samples into buckets of `othersCount`, giving count, median and max for each field.
  - Keep the body under 32 KB.
- Copy `BudgetTelemetry.send` and change only `kind`. **Do not refactor BudgetTelemetry.**
- **No UserIds, no names.** Aggregates only (ADR 0007 privacy rules).

### 1.C Client sampler

New file `Client/Services/InstanceProbeClient.luau`, `--!strict`, registered in `ClientModuleBag` and started from Main.client.

Sample every `INSTANCES_SAMPLE_SEC`:

```lua
{
  clientIC = Stats.InstanceCount,
  memMb = Stats:GetTotalMemoryUsageMb(),
  others = #Players:GetPlayers() - 1,
  othersBackpack = Σ #p.Backpack:GetDescendants() over other players,   -- answers Q4 gate
  othersCharacter = Σ #p.Character:GetDescendants() over other players, -- avatar + kit adornments
  ownPlayerGui = #LocalPlayer.PlayerGui:GetDescendants(),
}
```

- Use `pcall` around each other-player read. Those players can leave mid-loop.
- Send one batch of samples per `INSTANCES_CLIENT_BATCH_SEC` through `InstanceProbeReport`.

### 1.D VPS

`/v3/telemetry` has been live since ADR 0007 phase A, and `kind = "budget"` is already accepted.

- **Checked 2026-10-09 (read-only, infra checkout):** `handleTelemetryIngest` in `apps/api/src/routes/v3-routes.js` accepts any `kind`, and `telemetry_events` has no CHECK on `kind`. So `kind = "instances"` needs no VPS change and no deploy for this item.

- **Verify** that the ingest accepts `kind = "instances"`. If it whitelists kinds, add the new one. The infra repo location and deploy recipe are in memory `clubkit-vps-ops.md`.
- **ASK** before any VPS deploy.
- Read the data back with an SQL file + scp, the way `maintenance-until-kill-switch.md` does.

### 1.E Analysis (to write back here)

- Fit `clientIC ≈ a + b·others` and `serverIC ≈ c + d·players`.
  - `b` is the true cost per other player on a client (target ≤ 600).
  - `d` is the per-player cost on the server.
- `othersBackpack > 0` means other players' Backpacks replicate. That makes Phase 4 worthwhile; record `othersBackpack / others`.
- `othersCharacter / others`, minus about 400 (bare avatar), gives the adornments the kit adds to each character.

### 1.F Verification in Studio

- In a solo playtest, temporarily set `INSTANCES_FLUSH_SEC` to 60 and log the JSON body instead of POSTing it.
- Check its shape and size. Then restore the value.
- With `INSTANCES_ENABLED = false`, nothing is sampled and no remote fires.
- **Done 2026-10-10, without editing the place.** A fresh copy of the module was run from `execute_luau`'s own module cache, so the live game and Config were untouched.
  - **Setup:** sample every 2 s, flush every 10 s, `BackendClient.request` swapped for a capture (nothing was POSTed), and a test remote. The client fired one batch: 2 samples plus an unknown `userName` field.
  - **Request:** `POST donation:v3/telemetry`, `auth=donation`, `priority=bulk`. The body was `{kind="instances", kit_version="3.0.0", payload={server, clients, clientSampleCount, interval}}`, 744 bytes.
  - **Contents:** `clients` held one bucket per `others` value (3 and 5), each field as `[median, max]` rounded to 0.1. The unknown field was not stored. There were no names and no UserIds. Later flushes held only server samples (~530 bytes).
  - **`INSTANCES_ENABLED = false`:** checked by reading the code. `start()` returns before any loop or listener on both server and client.

### 1.G Ship

Engine-only, through source sync. After that, the data comes from live servers (PARKLAB and others) once they update.

**Acceptance:**
- The solo check passes.
- `count-locals` is OK.
- The CHANGELOG and UPGRADE_PROGRESS entries are added.
- ADR 0007 gets a one-line note under Phases: "instances probe (temporary) rides phase B".

---

## Phase 2 — Remove Sticker completely

**Why:** owner decision Q3. Stickers also put a server-built `ShoulderStickerGUI` BillboardGui on **every character** (`StickerService.luau` ~L57). That is a cost per other player on every client, on top of the panel.

### 2.A Engine deletions (files)

- `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/StickerService.luau`
- `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/StickerController.luau`
- `src/ServerScriptService/Hazastudio_ClubKit/Server/Repositories/StickerRepository.luau`
- `src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Controllers/StickerController.luau`
- `src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/Client/Utils/StickerBillboardAnimator.luau`

### 2.B Engine edits

Line numbers are as of 2026-10-09. Re-grep `(?i)sticker` before editing.

- **`Server/Init/ServerModuleBag.luau`:** remove `createStickerService` (L44), `createStickerController` (L76) and `StickerRepository` (L92).
- **`Client/Init/ClientModuleBag.luau`:** remove `StickerController` (L36) and `StickerBillboardAnimator` (L66).
- **`Server/Main.server.luau`:**
  - Remove the 5 `ensureRemoteEvent(... Config.Sticker.REMOTE_*)` lines (L264–268).
  - Remove the `stickerService` creation (L481–~490).
  - Remove the `if Config.FeatureFlags.StickersEnabled` controller block (L1133–~1156), including the `_profileLoader = sharedProfileLoader` fold. Check that `SharedProfileLoader` has no other sticker hook.
  - Remove the "StickerService and StickerController also start here" comment (L1157).
  - Remove `Sticker` from the boot log string (L1453).
- **`Main.client.luau`:**
  - Remove `trackClientLifecycle("StickerBillboardAnimator" …)` (L696).
  - Remove the Sticker Billboard block (L1092–~1100).
  - Remove the hotbar sticker wiring: L1692–1693, the `ensurePlayerGuiChild(… Config.Sticker.GUI_NAME …)` at L1695, the `stickerCtrl` create/init and the `MobilePanelManager.register("sticker" …)` at L1697–1711, `binder:bindStickerRequested(...)` at L1712–~1723, and the wrapper-visibility lines at L1742–1743.
  - Remove `reg("background", Config.Sticker, …)` (L2309).
- **`Client/UI/HotbarUIBinder.luau`:** remove `bindStickerRequested` and the sticker button handling (22 hits).
- **`Client/UI/HotbarGuiRefs.luau` — TRAP.** L204–213 returns `ok = false` when `StickerButtonWrapper` is missing. **That kills the whole hotbar.**
  - Remove the sticker lookup and the `stickerButtonWrapper` and `stickerButton` fields from the type and the result.
  - Buyer places that still contain the wrapper must keep working. Ignore it, or hide it if it is present.
- **`Client/Services/InventoryChromeAnimator.luau` — TRAP.**
  - L25 `HOTBAR_FRAME_NAMES` and L150–200 wrap `HotbarWrapper` **and** the sticker wrapper under one root, and L163–164 bail out when the sticker wrapper is missing. That would silently disable the hotbar chrome animation.
  - Make it wrap `HotbarWrapper` alone. If the sticker wrapper exists in an old buyer GUI, hide it (`Visible = false`).
- **`Client/Services/MobileScaleService.luau`:** drop `"StickerButtonWrapper"` from L22 and the `[Config.Sticker.GUI_NAME]` entry at L34.
- **`Client/Services/StarterGuiTrimService.luau`:** drop the sticker keep (L28–32) and update the header comment.
- **`Shared/Constants/Config.luau`:**
  - Remove `Config.Sticker` (L1419–1469) and `Config.StickerAnim` (L1470–1494).
  - Remove `FeatureFlags.StickersEnabled` (L1533).
  - Remove `Hotbar.STICKER_WRAPPER_NAME` and `STICKER_TRIGGER_NAME` (L1352–1353).
  - Remove `MobileScale.STICKER_GUI` (L4130).
  - Fix the `ClientFootprint` comment (L4553).
  - Then grep the whole `src` for `Config.Sticker`, `StickerAnim` and `StickersEnabled`. There must be zero hits.
- **Buyer config path**
  - `Shared/Config/ClubKitConfigSchema.luau`: remove `Stickers = true` (L619) and the `{ key = "Stickers", label = "Stickers" }` row (L679). Add this to `RETIRED_KEYS`:
    ```lua
    ["Features.Stickers"] = "3.x: the sticker system was removed (instance diet, docs/plans/instance-diet-2026-10-09.md)",
    ```
  - `Shared/Config/ConfigBootstrap.luau`: remove the `Stickers = "StickersEnabled"` mapping (L753).
  - Template `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`: remove `Stickers = true,` (L939).
- **Leave alone:**
  - `Shared/Utils/CharacterReady.luau`: `findAdornee` is generic.
  - `TitleImageDomain`, `MotionPresets` and `ImageSwap`: they only mention stickers in comments. Edit those comments only if they would now mislead.
  - DataStore `StickerCollection_v1`: the data stays as it is.

### 2.C Leftover GUIs in buyer places (no buyer action needed)

Buyers will not delete `11-StickerSystemGUI` or the hotbar's `StickerButtonWrapper` themselves. Without action, the leftover GUI would still be copied to every PlayerGui.

- Add a tiny server step that runs **at the very top of server boot**, before players spawn:
  - destroy `StarterGui["11-StickerSystemGUI"]` if present;
  - destroy any `StickerButtonWrapper` inside the hotbar ScreenGui template in StarterGui.
- Put the name list in `Config` as `RETIRED_GUI_NAMES = { "11-StickerSystemGUI" }`, so future retirements reuse it.
- This is runtime-only. The buyer's place file is not changed.

### 2.D Experiment Area place edits

These are owner-approved. Ctrl+S first.

- **Status 2026-10-10:**
  - **Steps 1–2 (deletes): not done.** The owner approved the list (steps 1–2, plus the 5 sticker ModuleScripts found in the place), but the auto-mode permission classifier refused the Studio delete twice ("Irreversible Deletion"). Still in the place: `11-StickerSystemGUI`, the hotbar `StickerButtonWrapper`, the 5 backup folders, and the 5 sticker ModuleScripts. They are harmless: the boot sweep removes both GUIs at runtime, and nothing requires the modules any more. They wait for the owner to delete them by hand, or for a permission rule.
  - **Step 3 (sync): done.** 19 files were synced: 14 replaced, 3 created, plus Config and the schema.
    - A three-way merge (HEAD base, repo working tree, live place source) kept the place-only `STYLE = "cinematic"` in Config.
    - The schema's `WutwutDance = false` was the place lagging behind commit `5d1d5a9`, not an experiment, so the repo version won.
    - Before writing, 1,132 place scripts were scanned for the removed Config keys: 0 hits.
    - Every file was read back and matched exactly.
    - Pre-sync copies of the 5 drifted files are in `.tmp/sync-place/`.
    - The owner saved the Experiment Area (Ctrl+S) on 2026-10-10.

1. Delete `StarterGui["11-StickerSystemGUI"]` and the `StickerButtonWrapper` in the hotbar GUI.
2. Delete the 5 backup folders in `ServerStorage`:
   - `LeaderboardRedesignBackup_20260923` (2,030)
   - `EventTabWireBackup_20260924` (504)
   - `TopMenuWireBackup_20260924` (297)
   - `EventTabRenameBackup_20260924` (116)
   - `CoverSyncBackup_20260923` (8)
3. Sync the engine changes into the place. Use `UpdateSourceAsync` for Config.
4. **Do not delete** other experiment GUIs.

### 2.E Verify

- In a solo playtest:
  - no errors or warnings mention sticker, hotbar or chrome;
  - the hotbar shows and tools work;
  - the inventory chrome animation still plays;
  - the mobile emulator scales the hotbar.
- Run the Phase 0 probe again and record the delta.
- Test a place that still has the sticker GUI: the Experiment Area copy taken before step 2.D, or re-insert the GUI. The runtime sweep must remove it and the hotbar must not break.
- **Result 2026-10-10 (Experiment Area, solo, after the sync).** The place still had both sticker GUIs in StarterGui, so the sweep was tested for real.
  - **Sweep:** `11-StickerSystemGUI` and `StickerButtonWrapper` are gone from PlayerGui and from the server's runtime StarterGui. `ShoulderStickerGUI` is gone from the character.
  - **Hotbar:** shows with 11 buttons. Equip and unequip of a Backpack tool work.
  - **Logs:** no error or warning mentions sticker, hotbar, chrome or the new modules. The errors that did appear were animation asset permissions and a Roblox CoreScript TopBar timeout at client boot (CorePackages Rodux, not kit code).
  - **Chrome:** on desktop it never animates by design. `MobilePanelManager.init` returns early on desktop, and `HOTBAR_IDLE_HIDE_ENABLED = false`. So a fresh `InventoryChromeAnimator` was driven against the live hotbar instead. `notifyHide`/`notifyShow` built `HotbarChromeRoot`, wrapped `HotbarWrapper` with no sticker wrapper present, slid it out (scale 0.96) and back (scale 1.0).
  - **Mobile emulator: not run.** The `robloxstudio` bridge was down: its plugin v3.2.0 does not match MCP server v3.1.6 (HTTP 426).
  - **Probe delta:** see §Results.

### 2.F Docs

- `CHANGELOG [Unreleased]`: a **Removed** entry plus a breaking note. The buyer key is retired and the GUI is optional to delete.
- `UPGRADE_PROGRESS.md`: list the deleted and edited files.
- Upgrade-guide note: "Sticker panel is gone; you may delete `11-StickerSystemGUI` (optional — the kit removes it at runtime)".

**Acceptance:**
- No sticker hits in `src` except comments that are still accurate.
- The playtest is clean.
- The probe delta is recorded.
- `count-locals` is OK.

---

## Phase 3 — Server-granted lazy GUIs (no buyer GUI edits)

**Before coding:** write **ADR 0020 "Server-granted lazy GUIs"**. It is hard to reverse, it changes how every gated GUI reaches players, and the alternatives below are real. Get an owner OK on the ADR.

### 3.A Idea

At server boot, a server step **moves** chosen ScreenGuis from `StarterGui` into a server-only holder, `ServerStorage.Hazastudio_LazyGui`. That has three effects:

- Roblox no longer copies them into every PlayerGui on spawn.
- They no longer replicate to clients through StarterGui.
- The server clones a template into **one** player's PlayerGui only when that player needs it. A server clone in PlayerGui replicates only to its owner.

Buyers keep editing their GUIs in StarterGui as before. Nothing in the place file changes, which is why Q5 can stay open.

### 3.B Alternatives the ADR must address

- **Templates in ReplicatedStorage, cloned on the client.** This saves only server copies; every client still holds every template.
- **Keep everything in StarterGui (status quo).**
- **Buyers move GUIs by hand.** This is the Q5 path.

### 3.C Mechanics and traps

- **Boot race.** The move must run before the first character spawns.
  - Put it in the earliest server boot step, in the same place as the 2.C sweep.
  - Add a fallback: if a player already received a copy and is not entitled, destroy that copy.
- **ResetOnSpawn.** Granted clones need `ResetOnSpawn = false`. Main.client already hardens templates to false, but server clones bypass that, so set it on the clone.
- **ForeignGuiGuardService — TRAP.** `ForeignGuiGuardService.luau` ~L169–171 treats a post-boot PlayerGui child as kit-owned only if `StarterGui:FindFirstChild(name)` exists. Moved GUIs would be flagged as foreign.
  - Add the lazy names to its kit-owned list (~L34), or check the replicated lazy-name list.
- **Client side.**
  - A helper `LazyGui.await(name, timeoutSec)` fires the request remote and waits on `PlayerGui:WaitForChild(name, timeout)`.
  - Every controller of a converted GUI must init when the GUI arrives, not at boot. Convert **one GUI per step** and playtest after each.
- **Request remote.** One RemoteEvent, `LazyGuiRequest(name)`. On the server:
  - check `name` against a whitelist;
  - check entitlement;
  - rate-limit it;
  - make it idempotent (already granted → no-op).
- **Release.** Optionally destroy a granted copy after it has been closed for N minutes. Make this a config flag, default **off** at first.

### 3.D Conversion order

Cheapest and safest first. Measure with the probe after each step.

1. **`04-AdminHub` (625) while `FeatureFlags.AdminHubEnabled == false`.** The default is false, so it is never granted, needs no controller work, and the saving is immediate.
2. **The unused admin-panel variant.**
   - `04-AdminPanelv3` (299) while `AdminPanelV3Enabled == false`.
   - Or `04-AdminPanelv2` while v3 is on.
   - `Config.Admin` ~L2343–2348 has the names.
3. **Admin panels for non-admins.**
   - Grant on entitlement, and again when a player is promoted mid-session.
   - Memory `perf-100-players-audit.md` says "role-based admin GUI removal saves nothing because the template must stay for promotions". That was true for client-side removal only. A server-side template removes that objection.
4. **`CommandLibraryGUI` (239)**, then the general panels on first open, one at a time: `02-ShopGUI`, `01-CoupleSystemGUI`, `03-GiftSystemGUI`, `12-CinematicDockGUI`.
   - **ASK** the owner before doing the general panels: the first open gets a short delay.
5. **Not kit, skip:** `DJGUI` (an Experiment Area owner experiment, memory `dj-panel-exploration.md`).

**Config:** add `Config.ClientFootprint.LAZY_GUIS = { ... }`, holding the names plus each entry's grant rule, and a master flag `SERVER_GRANTED_GUIS = true`. With the flag false, behaviour must be exactly today's.

**Acceptance per GUI:**
- Not present in a non-entitled player's PlayerGui on the client or the server.
- Opens correctly when entitled or requested.
- Survives respawn.
- No ForeignGuiGuard report.
- The probe delta is recorded.

---

## Phase 4 — Tools on demand (gated on Phase 1)

**Start only if** Phase 1 shows `othersBackpack / others` is material, about ≥100. If it is not, tell the owner and skip this phase.

**Today:** `RoleToolService` (`_cloneFolderTools`, ~L330–357) clones the whole role folder into **both** `Backpack` and `StarterGear`. The custom hotbar (`HotbarUIBinder`) lists tools from the Backpack.

**Sketch.** Run a short grill round with the owner before building:

- The server keeps the player's entitled tool **names** as data (an attribute or manifest), not as instances.
- The hotbar renders slots from that manifest, with icons from the template's `TextureId`.
- Clicking a slot fires `EquipToolRequest(name)`. The server validates entitlement, clones **one** tool straight into the character, and destroys the previous one.
- Unequip destroys the tool.
- StarterGear is no longer filled.

**Check first:**
- Which kit features are themselves Tools (Carry? Dance?).
- `Config.Hotbar` slot count.
- Mobile hotbar behaviour.
- The RuntimeGuard allowlist (`RuntimeGuard.luau` ~L184–189), which trusts tools in Backpack and StarterGear.

---

## Backlog (owner: "nanti dulu" — do not start)

- **Leaderboard boards** (`Workspace.hazastudioBoard`): about **8k instances on the server and on every client** at runtime (1,356 in Edit). This is the biggest fixed kit cost. Options: fewer boards, fewer rows, rows built only near the player.
- **Admin consolidation:** AdminHub, AdminPanelv2/v3 and Kohl's Admin (2,474 in ServerScriptService) overlap.
- **The hidden ~42.8k:** if Phase 0 shows the kit owns part of it (nil-parented pools, kept templates), audit pools such as the overhead lazy-row pool and any `Parent = nil` caches.
- **Other feature cuts:** owner to decide later.

---

## Results (fill in as phases land)

| Date | Place | Phase | Client IC | Server IC | Notes |
|---|---|---|---|---|---|
| 2026-10-09 | Experiment Area | baseline | 67,540 | 79,799 | solo, +25 s; includes place-only experiment GUIs (DJGUI 1,736) |
| 2026-10-09 | Experiment Area | 0 (re-run, same session) | 73,867 | 79,744 | solo, task.wait(25); GetDescendants 30,989 (client) / 36,976 (server); gap 42,878 / 42,768; client PlayerGui 7,832, Backpack 212, Character 402; server PlayerGui 5,755, Backpack 212, Character 395; client WS: hazastudioBoard 7,439, hazatargz 402, RunningText 27 x2, CCTV 6; server WS: hazastudioBoard 8,762, hazatargz 395. Client PlayerGui top: DJGUI 1,736, 07-MenuGUI 799, 06-MusicPlayerGUI 743, 04-AdminHub 625. Experiment GUIs: DJGUI 1,736 (PlayerGui) / 791 (StarterGui); 17-OnboardingGUI 12 / 12. StarterGui total top: DJGUI 791, 06-MusicPlayerGUI 681, 07-MenuGUI 680, 04-AdminHub 625 |
| 2026-10-09 | empty place (Place1) | 0 | 48,325 | 46,085 | solo, task.wait(25) before client probe; Edit pre-check: name Place1, 0 Hazastudio_ClubKit hits. GetDescendants 5,535 (client) / 3,325 (server); gap 42,790 / 42,760; client PlayerGui 3, Backpack 1, Character 343; server PlayerGui 3, Backpack 1, Character 334; client WS: hazatargz 343, Camera 3, SpawnLocation 2, Baseplate 2, Terrain 1; server WS: hazatargz 334, Baseplate 2, SpawnLocation 2, Terrain 1, Camera 1. Counts include the container itself (Backpack 1 = empty). Gap matches Experiment Area re-run (42,878 / 42,768), so the hidden gap is engine floor, not kit. Floor 48,325 is above the 40k Q1 target: 0.C re-statement needed, owner confirms N |
| 2026-10-10 | Experiment Area | 2 (after sync) | 67,710 | 79,619 | solo, +25 s. Sticker GUIs still in StarterGui (deletes blocked) and swept at boot. Client: GetDescendants 24,911, gap 42,799, PlayerGui 7,879, Character 400 (402 before). Server: PlayerGui 5,693 (5,755 before, −62 per player), Character 391 (395 before, −4 per character: ShoulderStickerGUI), IC −125 vs the re-run. Client IC varies about ±6k between runs: the 73,867 re-run had 30,989 GetDescendants against 24,911 here, while PlayerGui and boards were equal. Most likely StarterGuiTrimService timing at +25 s. So solo client deltas under ~6k are noise; compare PlayerGui, Character and server numbers instead |
