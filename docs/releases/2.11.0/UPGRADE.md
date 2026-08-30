# Club Kit 2.11.0 — Upgrade Guide

**From:** 2.10.x → **2.11.0** · **Date:** 2026-08-30 · **Type:** source sync (Update Engine). No RBXM re-import needed.

Two themes in this release: **role customisation** (multi-colour gradients, a name chip above the head, per-role permissions inside one staff group, and an Admin Hub role picker that finally knows your own roles) and **anti-cheat** (a runtime guard that watches for injected sounds/scripts, flying/speed-hacking, and laser-sized avatars). Your donation data, config, and secrets are untouched.

Nothing in this release requires a `ClubKitConfig` change — everything new is optional and off by default.

---

## How to update

1. Open your place in Studio → **Club Kit** panel → **Update Engine**. Engine folders are replaced wholesale; your `ClubKitConfig` and `Secrets` are merged forward, never overwritten.
2. **Ctrl+S** (publish) — nothing the sync does persists until you save.
3. Playtest: confirm `Server initialized … ready` in the console, donations/leaderboards work, and nametags look right.

HttpService must be on (unchanged since 2.10.0). If your place shows the "Club Kit paused" screen, that is HTTP being off — Game Settings → Security → Allow HTTP Requests.

---

## What changed for you

### Roles look better — multi-colour gradients
A role can now carry up to 5 gradient colours instead of two. In `ClubKitConfig`, on any role in `RoleCategories` / `SystemRoles` / `SpenderRoles`:

```lua
roleColor = { stops = { "daad18", "ffed2a", "fdff90", "daad18", "f4e628" } },
```

The name/rank text above the head is painted with that gradient. Chat colours are taken from the first and last stop automatically (you can still set `primary` / `secondary` yourself). 2 to 5 colours, `#` optional; a malformed list is ignored and the role simply keeps the old look.

### Role name chip above the head
Add `chip = true` to a role's `specialRank` and the role name shows as a **pill in the chip row above the nametag**, painted with the same gradient:

```lua
specialRank = { text = "THE MINISTER", gradient = true, chip = true },
```

While a player holds that role their `#N ROBUX` / `#N cash` / SUPPORTER chips are hidden (the chip row shows their role instead), and the rank line under the name shows the role's `chatTag`. An admin-set custom status still wins over both.

### One staff group, different powers
A role can now override its category's permissions:

```lua
{ key = "Echoborn", label = "The Echoborn", chatTag = "DPC",
  privileges = { canGift = false, adminPanel = false }, ... }
```

So you can put four differently-powered staff roles under one visible label (one shows "DPC" in chat and the player list, while one can only play music and another has full admin). Roles without `privileges` behave exactly as before.

### Admin Hub "Set role" knows your roles
The set-role picker used to be a hardcoded list (Co-Owner / Staff / Moderator / DJ …), so renamed or extra roles could only be given with `/setrole` in chat. It is now built from your own catalogue, in your order, with the category name as subtitle. (Admin Hub is still behind `Features.AdminHub`.)

### Anti-cheat: runtime guards (new)
Running on every server, no configuration needed:

- **Rogue audio** — any sound that appears at runtime with an id that was not in your place at server start is logged and reported to Hazastudio. This is the "a random guest played laughing audio for everyone" attack. Default is **log only**; set `Config.RuntimeGuard.SOUND_ENFORCE = "block"` to also stop and delete them.
- **Injected scripts** — a script created at runtime outside the kit (a backdoor's payload) is logged and reported. Legitimate admin loaders (Kohl's, Adonis) are ignored.
- **Movement cheats** — flying, speed hacks, noclip, teleporting and infinite jump are detected from server-side position samples. Kit states are exempt first (gravity float, carry, server teleports, seats, spawn, high ping, Owner/Co-Owner).
  **This release ships in "log" mode**: the player gets a warning toast at 3 strikes and everything is reported, but **nobody is kicked yet**. That is deliberate — the rules have not yet met your custom teleport pads, lifts and vehicles, and a wrong kick costs you a paying guest. After a week of clean reports we flip the default to kicking. To enforce immediately in your place: `Config.MovementGuard.ENFORCE = "kick"`.
  If you have teleport pads or elevators that move players by script, call `MovementGuard.stampTeleport(character)` right before you move them (seated players are already exempt).
- **Laser / oversized avatars** — accessories bigger than 10 studs, characters over 14×10 studs, and accessories spamming beams/trails/lights are trimmed or capped server-side, so everyone sees a normal avatar. The player is notified once; nobody is kicked.

### Loading screen: places with a custom one
If you run your own loading screen (`Features.LoadingScreen = false`), the kit now publishes its boot state on the player (`ClubKitBootProgress`, `ClubKitBootSettled`, `ClubKitGameplayReady`), and will wait for you: set `ClubKitExternalLoading = true` on the player and the kit holds the join-community prompt and greetings until you clear it (5-minute safety net). Kit music now lives in a `ClubKitMusic` sound group that is muted while your loading screen is up, so your loading track plays alone. Places using the kit's own loading screen see no change.

---

## If something breaks

- **A staff role lost a power it used to have** → check whether that role now has its own `privileges` block; a role-level entry wins over the category.
- **Gradient not showing** → fewer than 2 valid colours in `stops`, or a typo in a hex code; the role falls back to its old colours.
- **A guest reports being warned for "modified movement" while using your lift/teleporter** → seats are exempt automatically; for script-driven teleports call `MovementGuard.stampTeleport(character)`, or set `Config.MovementGuard.ENABLED = false` while you sort it out. Nobody is kicked in this release's default mode.
- **Music silent after adding a custom loading screen** → your pack left `ClubKitExternalLoading = true`; clear it when your screen closes.

See [`CHANGED_FILES.md`](CHANGED_FILES.md) for the exact file list, and [`CHANGELOG.md`](../../../CHANGELOG.md) `[2.11.0]` for full technical detail.
