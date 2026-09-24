# ADR 0018 — The trimmed overhead template ships as a new variant, never as an edit to V4

Status: **Accepted** (owner decisions 19–21, 2026-09-24) — designed, not built (production hardening P4b, plan H14, owner decision 18:
"design now, ship later as its own template release"). Design and numbers:
`docs/plans/hardening-2026-09-24/p4b-overhead-template.md`; inventory:
`docs/plans/hardening-2026-09-24/p4b-template-inventory.md`.

## Context

The overhead nametag is a BillboardGui the server clones from a template in `ReplicatedStorage` onto every
player's head (`S/Controllers/OverheadController.luau` `attachGui`). With streaming off, every client holds
every head's copy. `OverheadGUIMainTemplateV4` is 106 instances (18 UIGradient); at 200 players that is
~22,000 GUI instances per client and ~2.8 MB of replication for a client joining a full server. Code cannot
shrink it: the template is **place data, buyer-owned GUI** — source sync never touches it.

Reading the renderer against the template showed only 49 of the 106 instances are the renderer's contract;
17 are overwritten by the kit or never visible, 40 are decoration that properties of kept instances can carry.
The no-feature-loss floor is 49 instances / 6 UIGradients, with four small renderer tolerances.

Two ways to ship a smaller template:

1. **Edit V4 in place** (a Packager action that deletes and restyles instances inside each buyer's V4).
2. **Install a new variant next to V4** and let the buyer switch with the existing `ClubKitConfig.Overhead.GuiType`.

`V5` is already taken (V4 + the image-title row), so the new variant is **V6** = a trimmed V5.

## Decision

1. **New variant, installed alongside.** `OverheadGUIMainTemplateV6` is inserted next to V4/V5 by a Packager
   plugin action that first backs up V4/V5 and never modifies or removes them. The switch is the buyer's own
   `GuiType = "V6"`; the undo is `GuiType = "V4"`. No new buyer config key, no DataStore key.
2. **The renderer learns shapes, not versions.** Four backward-compatible tolerances, each keyed on what the
   template contains, never on the variant name (`renderer` stays inert):
   a row may itself be the TextLabel; a "pick one gradient by name" set may be one UIGradient whose colours
   live in ColorSequence attributes named after the old gradients; the role chip is cloned only when used; a
   missing template falls back (wanted → V5 → V4 → … → V1) instead of blanking every nametag.
3. **The template contract is the list of names the renderer reads** (inventory, class R). Names do not change
   in V6 — including the misspelt `06-VVIPMemberBagde` — so the payload and every other reader stay as they are.
4. **Engine before template.** The engine half (variant entry, fallback, tolerances) ships as an ordinary
   source-sync release first; the Packager action refuses on an engine without `OverheadGuiVariants.V6`, and
   an old engine rejects `GuiType = "V6"` in ConfigBootstrap and stays on V4.

## Consequences

- A buyer's V4 customisations do not carry over by themselves; the Packager ports what it can by name
  (badge art, fonts, colours, gradient colours → attributes) and reports the rest. Buyers with heavy custom
  decoration can stay on V4 indefinitely.
- Every place carries two templates for a while (V4 kept ≥ 2 releases after V6), which costs nothing at runtime
  — only the chosen one is cloned.
- The renderer grows two code paths per tolerance (old shape, new shape) until V4 is retired; each is small
  and covered by the V4/V6 parity harness.
- ≤ 40 instances per head (the plan's figure) is **not** reached without removing features; the plan's 8,000
  per-client budget at 200 players needs either visual cuts plus a badge pool or client-built nametags
  (P4b-client). That choice is left to the owner and is not part of this ADR.
- Rejected, option 1 (edit V4 in place): it destroys the buyer's GUI with no in-place undo, a failed or partial
  run leaves a template the renderer half-understands, and there is no way back short of restoring an RBXM.
