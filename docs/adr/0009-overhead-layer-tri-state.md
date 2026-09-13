# ADR 0009 — Tri-state values in the overhead layer config table

**Status:** Accepted
**Date:** 2026-09-12

## Context

`ClubKitConfig.Overhead.DefaultLayers` / `DefaultBadges` carried one boolean per nametag layer and badge, meaning a *default*: it seeded a player's first `Overhead_v1` record, and Settings → *Name Tag Details* could switch the layer back on afterwards. Buyers also need the other meaning — a layer that is not part of their venue at all: off for everyone, with its Settings row gone rather than sitting there inert. Both meanings are wanted, per key, in the same place.

Alternatives: (a) a second table (`Overhead.Layers` / `Badges`) holding the hard-off set, leaving `DefaultLayers` untouched; (b) redefine `false` as hard-off, so one boolean keeps covering it; (c) keep one table and widen the value to three states.

(b) was rejected on a fact rather than taste: the kit itself ships `CoupleName = false` in both `Config.Overhead.DEFAULT_LAYER_VISIBLE` and the buyer template, so redefining `false` would hard-hide the couple row on **every existing place** at update time — and it would fight the three kit paths that deliberately force `CoupleName = true` (`CoupleDomain.applyCouple`, `OverheadController`, the client `SettingsController` relationship patch). (a) works, but asks the buyer to keep two tables in agreement and gives no single place to read what a layer does.

## Decision

One table, three values per key, read by pure `Shared/Domain/OverheadLayerPolicy`:

- `true` — shown; the player may still hide it from Settings.
- `false` — hidden to begin with, the player may switch it on. A **default**, seeding the first stored record only. Unchanged from before this ADR.
- `"off"` (also `"disabled"`; case and surrounding spaces forgiven) — **hard-off**: off for everyone, always, with the layer's Settings row hidden.

`ConfigBootstrap` projects the table into `Config.Overhead.DEFAULT_*_VISIBLE` (booleans, what seeds a record) plus `DISABLED_LAYERS` / `DISABLED_BADGES` (the hard-off sets), filling those two **in place** before `table.freeze(Config)`. A value that is none of the three is ignored with a warning naming the key; an unknown key is ignored without inventing a layer, as before.

Hard-off is **enforced**, never merely seeded — `OverheadDomain.buildPayload` forces those keys false on both public maps, so it reaches players whose stored record predates the change — and it beats every kit override: the four force-true paths each consult `OverheadDomain.isLayerDisabled` first. Stored values are never rewritten, so deleting the `"off"` restores every player exactly as they had it.

## Consequences

- **This shape is now effectively permanent.** `ClubKitConfig.luau` is buyer-owned and never overwritten (ADR 0001), so once a buyer has written `"off"` the kit must keep reading that string indefinitely. Moving to a separate table later is not a refactor — it is a config-patcher migration plus backward reading forever. Do not "tidy" the string out of a boolean table.
- A string now lives in a slot whose schema default is a boolean. `ClubKitConfigSchema.fillForward` does not type-check (the buyer value wins whenever the types differ) and neither does `ConfigBootstrap.deepMerge`, so the value survives both merges. Verified, and load-bearing — a future type check on fill-forward would silently drop every `"off"`.
- `false` keeps its old meaning, so no existing buyer config changes behaviour on update.
- A hard-off reaching existing players is a deliberate asymmetry with `true` / `false`, which never reach back. Both behaviours are spelled out in the buyer template, because the difference is otherwise surprising.
- Enforcement is spread over nine sites rather than one. The payload build is authoritative; the renderer, the Settings row filter, the settings write filter and the four override guards exist so a hard-off cannot be worked around locally, by a crafted remote, or by an admin action. A new path that forces a layer visible must consult `isLayerDisabled` too — that is the rule to remember, and the reason the checks live behind one policy module instead of inline booleans.
