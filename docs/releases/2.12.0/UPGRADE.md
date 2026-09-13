# Club Kit 2.12.0 — Upgrade Guide

**From:** 2.11.x → **2.12.0** · **Date:** 2026-09-12 · **Type:** source sync (Update Engine), **plus optional place data** for three new panels.

Three themes: **your nametag is yours** (any layer or badge can now be switched off for the whole venue), **players can make their own title** (a self-service title panel with a level gate, a quota, and an optional event that unlocks it by donation), and **graphics presets that actually differ** — including a High that stops quietly downgrading itself. Your donation data, config and secrets are untouched.

Nothing here is mandatory: every new feature ships off or at its old behaviour until you turn it on.

---

## How to update

1. Open your place in Studio → **Club Kit** panel → **Update Engine**. Engine folders are replaced wholesale; your `ClubKitConfig` and `Secrets` are merged forward, never overwritten.
2. **Ctrl+S** (publish) — nothing the sync does persists until you save.
3. Playtest: confirm `Server initialized … ready` in the console, donations/leaderboards work, nametags look right.
4. Only if you want the new panels: import the RBXM from the delivery folder and follow **"Optional: the new panels"** below.

HttpService must be on (unchanged since 2.10.0). If your place shows the "Club Kit paused" screen, that is HTTP being off — Game Settings → Security → Allow HTTP Requests.

---

## What changed for you

### Switch a nametag layer or badge off for good

`Overhead.DefaultLayers` and `DefaultBadges` used to be *starting values*: a player could switch the layer back on in Settings, and changing your mind never reached players who already had a record. Each key now takes **three** values:

```lua
ClubKitConfig.Overhead = {
    ShowSupporterChip = true,        -- the generic SUPPORTER chip (ranked "#N <currency>" is separate)
    DefaultLayers = {
        BadgeGroup = "off",          -- off for everyone, always — and its Settings rows disappear
        SpecialStatus = false,       -- hidden to begin with, the player may switch it on
        Rank = true,                 -- shown (default)
    },
}
```

`"off"` is enforced, not seeded: it reaches players whose record predates the change, it beats the viewer's own setting, and it beats the four places the kit itself forces a layer visible (admin title grant, couple forming). Delete the `"off"` later and everybody comes back exactly as they were — nothing stored is rewritten, so there is no migration.

A value that is none of the three is ignored with a warning naming the key. `BadgeGroup = "off"` also hides every per-badge toggle, and an emptied section takes its heading with it.

### Players can create their own title

Off by default. Turn it on with `Features.SelfCustomTitle = true` **and** install the `1000-01-CT-ADDON` GUI (below) — with the flag on and no GUI, the Title row falls back to the old text-only modal.

```lua
ClubKitConfig.CustomTitle = {
    MinLevel = 50,              -- level needed to create a title
    MaxChangesPerWindow = 5,    -- rolling quota
    WindowDays = 7,
    QuotaEnabled = true,        -- false = change it as often as you like
    FreeFirstTitle = false,     -- true = one free creation below MinLevel, then locked
}
```

`FreeFirstTitle` gives a player one creation even below `MinLevel`; after that they are locked until they qualify. A title **an admin gave you** never consumes that slot and its holder keeps editing — including everyone who already holds a title today, which is why upgrading does not strip anyone's edit rights. Removing your own title is free but does not refund the slot.

### An event that unlocks titles by level, Robux or cash

```lua
ClubKitConfig.FreeTitleEvent = {
    Mode = "Any",               -- "Any" | "All" | "Disabled"
    RequiredLevel = 25,         -- 0 = this requirement is off
    MinDonationRobux = 100,     -- lifetime Robux donated
    MinDonationCash = 0,        -- lifetime cash, in your own currency
}
```

A threshold above 0 switches its axis on; `Mode` says how the active ones combine. Players who do not qualify still see the card, showing the one thing they are missing next. The panel's locked sentence is generated from whatever you configured — *"Reach Lv 50, or reach Lv 25 and donate Rp 50.000 to unlock this custom feature."* — so it can never quote a level at someone who needs to donate. Unknown mode, all-zero thresholds, or a negative number all mean "no event" rather than "no requirement".

### Graphics: Low, Balanced and High finally differ

- **Low** switches off `GlobalShadows`, every light's `Shadows` and every part's `CastShadow` across the whole Workspace — tagged or not. Your textures and `SurfaceAppearance` stay as built.
- **Balanced** keeps sun shadows, drops local light shadows.
- **High** is the map as built, and no longer downgrades itself: previously, toggling Shadows off and on again silently left a High player on Balanced's softness with no way back short of re-picking the preset.
- **New players start on Low.** Change it with `Graphics = { DefaultPreset = "Balanced" }`. This only affects players with no saved settings record — anyone who ever touched Settings keeps what is stored for them.
- **Phones** render High as Balanced, without rewriting the player's stored choice.

**Two things the kit cannot do for you, and both matter more than the presets:**

1. `MeshPart.RenderFidelity` cannot be changed at run time — the engine refuses it and keeps the mesh it loaded. A venue whose meshes sit at `Performance` looks low-detail on *every* preset. Fix it in Studio (Edit mode), select the meshes, set `Automatic` or `Precise`, and save. For scale: one buyer venue had 2010 of 3365 meshes at `Performance`.
2. `Lighting.Technology` is not scriptable at all. On `Voxel` there are no shadow maps, so High's soft shadows do nothing. Switch to `Future` by hand in Studio if you want the full look.

The kit also reads (never writes) the player's own Roblox quality slider and mentions it once per session when it is very low — that slider caps everything above.

### Membership: run 3, 2 or 1 tier

`Membership.TierN.Enabled = false` now really removes a tier: the shop card, the gift tab, the gift selector button, the Admin Hub menu and the server's gamepass sync all follow it. Players who already hold a disabled tier stop showing it (leaderstats Rank, chat tag, badge) but nothing is deleted — re-enable and it comes straight back.

### Smaller things

- The topbar pill reads **"Close Menu"** while open instead of a bare "X".
- The daily streak popup now actually appears — it had been animating on an invisible frame.
- Donation panel no longer repaints on every server echo; image preloading now reports real results (it had been scoring every asset as failed).
- The donation leaderboard's last-known-good cache now serves during a DataStore hiccup instead of throwing.
- Donor messages can no longer inject RichText markup into the donation panel.

---

## Optional: the new panels (place data, from the RBXM)

Import `HazastudioClubKit_Package_v2.12.0.rbxm` and take only what you want:

| Install | Where | Then |
|---|---|---|
| `1000-01-CT-ADDON` | `StarterGui` | set `Features.SelfCustomTitle = true` |
| `ADDON-FreeTitleEventTrigger` | inside your own `IconGroup` | set `FreeTitleEvent.Mode` |
| `99-NotificationCenterV2` | `StarterGui` | nothing — the kit picks V2 over V1 automatically |

Keeping your old `99-NotificationCenter` is fine: V1 places behave exactly as before.

---

## If something breaks

- **Nametag layer missing that you did not switch off** — check `Overhead.DefaultLayers` for a stray `"off"`, and the console for `[ConfigBootstrap] Overhead.DefaultLayers.X is not true, false or "off"`.
- **Title panel does nothing / opens the old modal** — the `1000-01-CT-ADDON` GUI is not in `StarterGui`; the console warns when the flag is on without it.
- **Free Title card never appears** — `FreeTitleEvent.Mode = "Disabled"`, every threshold is 0, or the frame is not inside your `IconGroup`. Also check nothing full-screen in your place sits above it: place-owned overlays with a high `DisplayOrder` swallow clicks on kit panels.
- **High still does not look high** — mesh `RenderFidelity` and `Lighting.Technology` (both above), then the player's own Roblox quality slider.
- **Rolled back?** Update Engine is forward-only; restore from your own place version history (File → Version History) — your data and config are untouched either way.
