# ExternalAdminBridge — place-specific pack (not Club Kit engine)

Bridge between Club Kit and an external admin system (**Adonis** and/or **Kohl's Admin — new kohl.gg loader only, NOT Legacy**). Not part of Rojo `default.project.json`, not part of Update Engine, and **not** included in buyer changelog.

When active: the chosen admin gains `:ck…` / `;ck…` chat commands that run **through Club Kit's own services** (permission gates intact), and Club Kit staff role changes (`/setrole`) mirror into the external admin's ranks live (session-only).

## What owns what

| Concern | Owner |
|---------|-------|
| Ban / kick / mute / moderation logs | **Adonis or Kohl's** (buyer choice) |
| Gift / setrole / overhead / shop / announce / AdminHub | **Club Kit** |
| Staff rank mirroring | Club Kit `/setrole` → external rank (this pack) |
| Membership (VIP/VVIP/Supreme) + Spender roles | **Club Kit only — never synced** to external ranks |

## Folder contents

| Path | Purpose |
|------|---------|
| `ExternalAdminBridge.rbxm` | Drag-in bundle of both bridge modules + selector (rebuild: `rojo build build.project.json -o ExternalAdminBridge.rbxm`) |
| `ExternalAdminSelector.server.luau` | Boot gate: only the `Provider`-chosen admin's loader runs (total off for the other, UI included) |
| `adonis/Server-ClubKitBridge.luau` | Adonis server plugin — `:ck*` commands + rank sync |
| `adonis/Settings.snippet.luau` | Adonis Settings checklist (ranks, G_API, de-noise) |
| `kohls/ClubKitAddon.luau` | Kohl's addon — `;ck*` commands + rank sync |
| `kohls/Settings.snippet.luau` | Kohl's Settings snippet (de-ads + role map) |
| `README.md` | This guide |

## 1. Pick a provider (ClubKitConfig)

In `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`:

```lua
ClubKitConfig.ExternalAdmin = {
	Provider = "None", -- "Adonis" | "Kohls" | "None"  ← pick ONE
	SyncStaffRoles = true,
	SyncContentRoles = false,
	RankMap = {
		Owner = { adonis = 900, kohls = "creator" },
		CoOwner = { adonis = 300, kohls = "superadmin" },
		Staff = { adonis = 200, kohls = "admin" },
		Moderator = { adonis = 100, kohls = "mod" },
	},
}
```

- `"None"` (default) → bridge fully inactive (commands return `disabled`, no sync). Installed admins still work standalone.
- The engine warns at server start when the chosen provider isn't detected in the place (and when both are detected).
- **Both admins installed?** Supported, but bridge one provider only. Recommended: pick one for moderation and remove the other to avoid double dashboards/prefixes.

## 2. Install the admin (official sources only — fake models exist)

- **Adonis**: loader <https://www.roblox.com/library/7510622625/> → `ServerScriptService.Adonis_Loader`.
- **Kohl's Admin**: official model via <https://docs.kohl.gg/docs/getting-started/installation> (**new loader**, not Legacy).

## 3. Install the bridge module

Fast path: drag **`ExternalAdminBridge.rbxm`** into the place — it contains both bridge modules + the selector script; move each to its slot below (delete the one you don't use). Or paste the `.luau` sources manually.

| Provider | Action |
|----------|--------|
| Adonis | `adonis/Server-ClubKitBridge.luau` → ModuleScript named exactly **`Server-ClubKitBridge`** in `Adonis_Loader > Config > Plugins` |
| Kohl's | `kohls/ClubKitAddon.luau` → ModuleScript named **`ClubKitAddon`** (no "Client"/"Server" in the name) in Kohl's **`Addons`** folder |
| Both/neither | `ExternalAdminSelector.server.luau` → Script **`ExternalAdminSelector`** directly in `ServerScriptService` |

Then apply the matching `Settings.snippet.luau` checklist (Adonis: ranks + `G_API = true`; Kohl's: **de-ads** + role tables).

## 3b. Hard on/off per provider (ExternalAdminSelector)

Without the selector, a non-chosen admin still boots standalone (its topbar/dashboard UI and its own commands stay available). With the selector installed, **`ClubKitConfig.ExternalAdmin.Provider` is the only switch**: the chosen admin boots, the other stays fully off — no UI, no commands — without deleting anything from the place.

1. Install `ExternalAdminSelector.server.luau` → Script **`ExternalAdminSelector`** directly in `ServerScriptService`.
2. Recommended (the Club Kit template ships this way): leave **both** loader Scripts at `Disabled = true` in Edit —
   - `ServerScriptService.Adonis_Loader.Loader.Loader`
   - `ServerScriptService."Kohl's Admin".Loader`

   If you skip this (e.g. fresh loader insert, which ships Enabled), the selector still disables the non-chosen loader at runtime and prints a warning — but the unwanted admin may boot for that one session (script start order is not guaranteed). Setting `Disabled = true` once in Edit makes every boot deterministically clean.

`Provider = "None"` boots neither admin. Switching provider applies on the **next server start** (the selector gates boot, not runtime). Engine detection is selector-aware: a Disabled loader is not reported as installed.

## 4. Commands (external admin chat)

| Command | Action | Club Kit gate |
|---------|--------|---------------|
| `cksetrole <player> <role>` | `GiftService.giveRole` | canGift / isAdminUser |
| `ckunsetrole <player>` | `GiftService.removeRole` | canGift / isAdminUser |
| `ckgift <player> <tier>` | membership grant (vip/vvip/supreme) | canGift / isAdminUser |
| `ckungift <player> <tier>` | membership remove | canGift / isAdminUser |
| `ckannounce <message>` | Club Kit broadcast | canAnnounce + 2/30s rate limit |
| Kohl's native `message` / `m` / `msg` | **overridden** → Club Kit broadcast (exact semantic match: transient broadcast) |
| Kohl's native `announce` | **overridden** → Club Kit broadcast (Kohl's persistent banner intentionally replaced; delete the override block in `ClubKitAddon.luau` to restore native behavior for either command) |

Adonis: registered at **AdminLevel "Admins"**. Kohl's: group **"Administration"**. An external admin **without** a kit-side privileged role gets `no_perm` — being admin in Adonis/Kohl's does **not** grant Club Kit rights (reverse bridge intentionally not included).

## 5. Live rank sync (Club Kit → external)

- `/setrole <player> Staff` → mapped external rank applied (Adonis temp level / Kohl's non-persistent role).
- `/unsetrole` → rank removed.
- Only roles in `RankMap` with its class toggle on (`SyncStaffRoles` / `SyncContentRoles`). Membership/Spender roles are hard-blocked even if added to the map.
- Session mirror only: **Club Kit's DataStore is the source of truth**; external ranks are re-applied per server.

## Verify (playtest)

1. `Provider = "Adonis"` (or `"Kohls"`), bridge module installed → server log: facade initialised, no mismatch warning.
2. As Owner: `:cksetrole <p2> Staff` → p2 overhead updates **and** p2 has the mapped external rank.
3. As an external admin with **no** Club Kit role: `:ckgift <p2> vip` → fails with `no_perm` (gate holds).
4. `Provider = "None"` → `:ck*` fails with `disabled`; external admin still works standalone.
5. Delete the bridge module → engine boots silently, zero errors.

## Maintenance

- This pack is **custom**; admin-system bugs are not universal kit bugs.
- Kohl's version skew: new loader only. If Kohl's changes its Auth/Registry API, fix points are isolated in `kohls/ClubKitAddon.luau` (and the engine-side detector in `ExternalAdminFacade.luau`).
- Engine↔pack contract = `ServerScriptService.Hazastudio_ClubKit.Server.ExternalAdminFacade` (facade methods + `onRoleChanged`).
