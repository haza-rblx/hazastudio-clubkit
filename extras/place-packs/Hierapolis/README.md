# Hierapolis — place-specific add-on (not Club Kit engine)

Everything that makes `[SOFT OPENING] HIERAPOLIS THEATER` (place `124816875861754`, buyer key
`hierapolis`) different from a stock kit install, switched by **one feature flag**:

```lua
ClubKitConfig.Features.HierapolisCustom = true   -- on
ClubKitConfig.Features.HierapolisCustom = false  -- off (stock kit)
```

Same mechanism as every other kit feature (plugin Config panel checkbox "Hierapolis place pack",
fill-forwarded by Update Engine). `ClubKitConfig.luau` is never rewritten by this pack: the catalog
lives in the overlay module below and the engine merges it at boot when the flag is true.
Engine features it relies on ship with the kit (2.10 + unreleased): `Features.HierapolisCustom`,
`roleColor.stops`, per-role `privileges`, `specialRank.chip`, the external loading contract.

| Path | Purpose |
|---|---|
| `HierapolisCustom.luau` | **The overlay.** ModuleScript installed as `ReplicatedStorage.Hazastudio_ClubKitConfig.HierapolisCustom` (buyer-owned folder — Update Engine never touches it). Leadership (Co-Owner) / **DPC** (Emperor, Echoborn, Minister, Senator) / Content catalog, `SystemRoles.Owner` (The President), aliases, `Features.LoadingScreen = false`. Edit this to change the catalog. |
| `install.luau` | **One-time install** (not the toggle): writes the overlay module, clones the per-role tool folders, installs `ReplicatedFirst.CinematicLoading`. Safe to re-run (refreshes sources). |
| `HierapolisToolFolders.rbxm` | Export of `ServerStorage.Tools/{CO-OWNER, THE EMPEROR, THE ECHOBORN, THE MINISTER, THE SENATOR}` for a fresh place (install.luau clones them from OWNER/STAFF/LEAD DANCE when those exist instead). |
| `../CinematicLoading/` | The loading screen this add-on turns on (`CinematicLoadingUI.rbxm` + bridge script). Its bridge reads the merged `LoadingScreen` value, so it follows the flag too. |

## Merge rules (engine: `ConfigBootstrap.applyHierapolisCustom`)

| Overlay section | Applied as |
|---|---|
| `RoleCategories`, `LegacyAliases`, `CommandAliases` | replaced wholesale |
| `SystemRoles.<key>` | that entry replaced wholesale (Owner only here; Guest stays stock) |
| `Features` | merged key by key (`LoadingScreen = false`) |

Flag `true` but module missing/broken → console warn, stock catalog runs. Flag `false` → module ignored.
The packager strips `HierapolisCustom` from product packages and resets the flag in the blank template.

## What the catalog is

| Role (kit key) | Rank row / chat tag | Overhead chip | Privileges | Tool folder |
|---|---|---|---|---|
| The President (`Owner`) | OWNER | THE PRESIDENT, gold stops | owner | `OWNER` |
| The Archon (`CoOwner`) | CO-OWNER | THE ARCHON, black→white stops | Leadership (full) | `CO-OWNER` |
| The Emperor (`Emperor`, Scripter) | DPC | THE EMPEROR, red ramp | full | `THE EMPEROR` |
| The Echoborn (`Echoborn`, Operational) | DPC | THE ECHOBORN, purple stops | announce + teleport + music (no gift / admin panel) | `THE ECHOBORN` |
| The Minister (`Minister`, Admin) | DPC | THE MINISTER, orange stops | full | `THE MINISTER` |
| The Senator (`LeadDance`, Lead Dancer) | DPC | THE SENATOR, violet→red stops | music + announce | `THE SENATOR` |

Group `COMA Studio` (`1068114138`) only has Member / Dev / Admin / Owner ranks, so all of these are
`/setrole` roles (`/setrole <user> president|archon|emperor|echoborn|minister|senator`).

## Install (once, Studio Edit)

1. Start `tools/ClubKitPackagerPlugin/dev-serve.ps1` (serves the repo at `http://127.0.0.1:8798/repo/`).
2. Command Bar / MCP:
   ```lua
   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/install.luau"))()
   ```
3. First time only: insert `../CinematicLoading/CinematicLoadingUI.rbxm` and parent the `LoadingUI`
   ScreenGui under `ReplicatedFirst.CinematicLoading`.
4. Sync the engine as usual (Update Engine adds `HierapolisCustom = false` to the buyer config).
5. Set `Features.HierapolisCustom = true`. **Ctrl+S.**

## Turning it off

Set `Features.HierapolisCustom = false`. Stock kit roles come back (Staff / Moderator / DJ / Lead Dance / …),
the kit loading screen returns, the cinematic script no-ops itself. Nothing else to undo. Stored
`/setrole` data for Hierapolis keys (`Emperor`, `Echoborn`, `Minister`) will not resolve while off.

## Gotchas

- The place is **Team Create**: a collaborator with a stale `ClubKitConfig` editor tab can commit
  over the flag line. The catalog itself is safe now (it lives in the module, not in the config).
- Emperor's red gradient was derived from the old place's accent (`#DE3B20`); replace the stops in
  `HierapolisCustom.luau` when the buyer sends real colors, then re-run `install.luau` (or paste).
