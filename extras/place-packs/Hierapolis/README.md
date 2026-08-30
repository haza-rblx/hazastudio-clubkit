# Hierapolis — place-specific add-on (not Club Kit engine)

Everything that makes `[SOFT OPENING] HIERAPOLIS THEATER` (place `124816875861754`, buyer key
`hierapolis`) different from a stock kit install, packaged so it can be switched **on** (apply)
and **off** (revert) in one command each. Not in Rojo, not in Update Engine, not in the buyer
changelog. Engine features it relies on ship with the kit (2.10 + unreleased): `roleColor.stops`,
per-role `privileges`, `specialRank.chip`, the external loading contract.

| Path | Purpose |
|---|---|
| `apply.luau` | **Toggle ON.** Runs `apply-config.luau`, creates the per-role tool folders, installs/enables `ReplicatedFirst.CinematicLoading`. Idempotent. |
| `apply-config.luau` | Buyer `ClubKitConfig` patch: Leadership (Co-Owner) / **DPC** (Emperor, Echoborn, Minister, Senator) / Content; chip flags; aliases; `Features.LoadingScreen = false`. Only the role/alias/loading spans are rewritten — Branding, Group, Donation, Shop stay as the buyer has them. |
| `revert.luau` | **Toggle OFF.** Stock catalog from `ClubKitConfigSchema.defaults`, `LoadingScreen = true`, CinematicLoading disabled. Tool folders left in place. |
| `HierapolisToolFolders.rbxm` | Export of `ServerStorage.Tools/{CO-OWNER, THE EMPEROR, THE ECHOBORN, THE MINISTER, THE SENATOR}` for a fresh place (apply.luau clones them from OWNER/STAFF/LEAD DANCE when those exist instead). |
| `../CinematicLoading/` | The loading screen this add-on turns on (`CinematicLoadingUI.rbxm` + bridge script). |

## What the catalog is

| Role (kit key) | Rank row / chat tag | Overhead chip + special-rank row | Privileges | Tool folder |
|---|---|---|---|---|
| The President (`Owner`) | OWNER | THE PRESIDENT, gold stops | owner | `OWNER` |
| The Archon (`CoOwner`) | CO-OWNER | THE ARCHON, black→white stops | Leadership (full) | `CO-OWNER` |
| The Emperor (`Emperor`, Scripter) | DPC | THE EMPEROR, red ramp | full | `THE EMPEROR` |
| The Echoborn (`Echoborn`, Operational) | DPC | THE ECHOBORN, purple stops | announce + teleport + music (no gift / admin panel) | `THE ECHOBORN` |
| The Minister (`Minister`, Admin) | DPC | THE MINISTER, orange stops | full | `THE MINISTER` |
| The Senator (`LeadDance`, Lead Dancer) | DPC | THE SENATOR, violet→red stops | music + announce | `THE SENATOR` |

Group `COMA Studio` (`1068114138`) only has Member / Dev / Admin / Owner ranks, so all of these are
`/setrole` roles (`/setrole <user> president|archon|emperor|echoborn|minister|senator`).

## Turning it on (Studio, Edit mode)

1. Start `tools/ClubKitPackagerPlugin/dev-serve.ps1` (serves the repo at `http://127.0.0.1:8798/repo/`).
2. Command Bar / MCP:
   ```lua
   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/apply.luau"))()
   ```
3. First time only: insert `../CinematicLoading/CinematicLoadingUI.rbxm` and parent the `LoadingUI`
   ScreenGui under `ReplicatedFirst.CinematicLoading`.
4. Sync the engine as usual (Update Engine, or the MCP drift sync). **Ctrl+S.**

## Turning it off

```lua
loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/revert.luau"))()
```
Stock kit roles come back (Staff / Moderator / DJ / Lead Dance / …), the kit loading screen
returns, the cinematic script is disabled but kept. Stored `/setrole` data for Hierapolis keys
(`Emperor`, `Echoborn`, `Minister`) will no longer resolve until the add-on is applied again.

## Gotchas

- The place is **Team Create**: a collaborator with a stale `ClubKitConfig` editor tab can commit
  over the applied config (happened 2026-08-30). Re-run `apply.luau`; it is safe to repeat.
- Do not hand-edit the role spans in `ClubKitConfig` while the add-on is on — edit `apply-config.luau`
  and re-apply, or the next apply will overwrite the hand edits.
- Emperor's red gradient was derived from the old place's accent (`#DE3B20`); replace the stops in
  `apply-config.luau` when the buyer sends real colors.
