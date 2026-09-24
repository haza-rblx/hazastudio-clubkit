# ADR 0013 — Donation world effects are one themed model, repainted at runtime

**Status:** Proposed — 2026-09-18 (owner decisions taken; not yet implemented)

## Context

Buyers report that the donation world effects look like every other Roblox club. They do, and the
reason is not subtle: `ReplicatedStorage.WorldEffects` is a third-party VFX pack. It draws on
**138 unique assets from 65 creators**; exactly one of them is ours (the giant's animation,
`93040740783271`, `hazatargz`). The original author's placeholder text is still baked into the
billboards — `@JamerLF DONATED` → `TO @JamerLofranco12345` — along with their `Strtoke` typo.
Ownership itself was already audited on 2026-08-08 in
[`docs/audits/ASSET_OWNERSHIP_AUDIT.md`](../audits/ASSET_OWNERSHIP_AUDIT.md) and is not reopened
here; this ADR is about how far we can change the *look* without touching those assets.

Four facts, measured on 2026-09-18 against THE BASIC TEST, shape the answer.

**1. `WorldEffects` is not in the repo.** `default.project.json` maps `src/ReplicatedStorage` to
ReplicatedStorage and the folder is not there. The models live only inside the place and the
packaged `.rbxm`. So **nothing that edits the model can ride a normal source-sync release** — not
an added attribute, not a recoloured emitter, not a deletion. Only code reaches existing buyers.

**2. `Smite4` is not a recolour rule, it is hand-painted — but it collapses cleanly.** Diffing
`Smite3` against `Smite4` node by node: **351 nodes identical**, 91 differing, of which **75 differ
only in colour/texture**. The hue shift ranges +135° to +300° and is not consistent, and one source
colour lands on three different targets, so no hue rotation reproduces it. However, grouping nodes
by the *pair* (Smite3 colour, Smite4 colour) yields **21 roles covering all 73 coloured nodes, with
zero unpaired**. Three of those roles are identity. One node (`DiamondHammer/Effects/Trails/
HandleTrail`) carries a 5-keypoint gradient and needs per-keypoint handling.

Roles defined this way reproduce **both** palettes exactly, because they are literally how the pack
author grouped the work. The only structural difference between the two models is the head ornament:
`Smite3` has `CORONA` (MeshPart), `Smite4` has `Crown` (Part + SpecialMesh).

**3. `Smite3` is dead in the shipped config.** `WorldEffectTiers` maps 100k→`Nuke`,
250k→`Smite4`, 500k+→`BlackHole`. `Smite3`/GreenHammer is never reached by any buyer running the
default tiers. So "collapse the two models into one" must keep **`Smite4`** — the one people
actually see — and drop `Smite3`, which is the larger of the two anyway (582 descendants vs 371,
the difference being 215 nodes of stored `KeyframeSequence` authoring data).

**4. `WorldEffectTiers` is in `ARRAY_REPLACE_KEYS`.** A buyer who has that array in their config —
and the shipped template does — gets their array used **wholesale**. Adding a `theme` field to the
schema's tier entries would therefore reach no existing buyer at all, silently. This kills the
obvious design of "per-tier theme as a field inside the tier row".

A related correction landed with this investigation: `ClubKitConfigSchema.fillForward` *does*
recurse into nested tables and fill missing nested keys. The note in
[`docs/buyers/night-zone.md`](../buyers/night-zone.md) claiming otherwise was wrong; the real rule
is "the key must exist in the schema defaults".

## Decision

1. **One base model, repainted on the clone.** `Smite4` stays as the single base. The effect script
   clones it as it always did, then a new `Client/Effects/EffectTheme` module walks the clone and
   writes colours before it is parented. The stored model is never modified, so this ships through
   ordinary source sync and reaches every existing buyer on Update Engine.

2. **`Smite3` is pruned at runtime, not from the pack.** The server destroys
   `ReplicatedStorage.WorldEffects.Smite3` at boot, behind a flag that defaults on, saving **582
   replicated instances** per place without an `.rbxm` re-export. The 21-role map is extracted from
   the two models *before* this lands and checked into the repo as generated data, because once
   `Smite3` is gone the mapping cannot be re-derived.

3. **Themes are named presets that resolve to the 21 roles.** `blossom` reproduces today's `Smite4`
   exactly and is the default, so an untouched buyer sees no change whatsoever. `nature` reproduces
   `Smite3`'s greens (minus the `CORONA` ornament, which does not exist on the `Smite4` base and is
   accepted as lost — nobody is running `Smite3` today). Further presets are ours to author, plus a
   raw-palette escape hatch for buyers who want their own brand colour.

4. **Theme is chosen per effect name, never inside `WorldEffectTiers`.** New nested section
   `Donation.EffectTheme = { Default = "...", ByEffect = { Smite4 = "..." } }`. Because each tier
   row already names an effect, keying by effect name gives per-tier control without touching the
   array-replace trap in fact 4. `Default` gives the kit-wide brand palette the owner asked for;
   `ByEffect` keeps the tiers visually distinct so a 500k donation still reads as bigger than 250k.

5. **GreenHammer and Blossom merge into one script.** They are 80% identical (396 differing lines
   out of 2,042), and Blossom is strictly the better copy — it has `cleanup`, `safeDestroy`,
   `spawnAbortable` and `trackMarker`, which GreenHammer lacks. Blossom becomes the surviving
   script; `"Smite3"` as an effect name keeps working and simply selects the `nature` preset.

## Consequences

- Buyers on the default config see **no visual change** until they set a theme; `blossom` is
  byte-identical to today. That is the safety property that makes this shippable without an RBXM.
- **−582 replicated instances** per place, and **~950 duplicated lines** removed from the client.
- Third-party asset risk is unchanged — this ADR recolours, it does not replace assets. That risk
  is real and already realised: `SoundAssetSanitizer` blocks two Smite sounds today
  (`8578316223` "not approved for requester", `9009370950` "file not found"), and `9009370950`
  still resolves fine through `GetProductInfo`, so a resolving asset is not a playable one.
  Replacing assets is a separate, larger piece of work and stays in the audit's action plan.
- `CORONA` is lost. Acceptable because no shipped config reaches the model that carries it.
- New config surface: one nested section. It fills forward for existing buyers (fact 4's
  correction), so no buyer file is edited — consistent with ADR 0001.
- Only Smite is themed in this pass. `BlackHole` and `Nuke` keep their current look; `BlackHole`
  in particular mutates global `Lighting` (`ClockTime`, `FogColor`) and needs its own role map.

## Alternatives rejected

- **Hue rotation instead of a role map.** Measured and refuted: the Smite3→Smite4 transform is not
  a rotation, and one source colour maps to three targets.
- **Tagging roles as attributes inside the model.** Self-describing and editable in Studio, but
  fact 1 makes it unshippable — model edits cannot reach existing buyers.
- **`theme` field inside each `WorldEffectTiers` row.** Reads better, but fact 4 means it would
  reach zero existing buyers and fail silently.
- **Keeping `Smite3` as the base.** It carries the editable animation source and the `CORONA`
  ornament, but it is the unused model and the larger one; keeping it would change what every
  buyer currently sees.
