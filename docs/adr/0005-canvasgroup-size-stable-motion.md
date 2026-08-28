# ADR 0005 — CanvasGroup motion is size-stable (no scale pops on rasterized groups)

**Status:** Accepted
**Date:** 2026-08-27

## Context

Buyers (diagnosed on RUST, kit 2.8.0) report CanvasGroup-based GUIs going **blank** or **flickering** — random per session, but reproducible across devices. The Roblox `CanvasGroup` reference states three facts that together explain it:

1. A group is rasterized into a GPU texture sized by its `AbsoluteSize`; "it's recommended to use CanvasGroup with **static sizes**, otherwise a **new texture** would need to be created to accommodate new sizes."
2. Texture quality/memory is capped by the client's `QualityLevel`; "when exceeding the memory cap, CanvasGroup will render as a **blank** texture."
3. Flattening only happens under `ZIndexBehavior.Sibling` (all kit GUIs already are).

Nearly every animated kit surface is a CanvasGroup driven by a `UIScale` pop: `AnimationHelper:presentCenterPanel` (Shop, Gift, Admin, Music, Couple, Donation, Menu modals, Sticker, Carry, Dance panel, Paid Broadcast, Join Community), the broadcast/greeting/donation toasts, and the overhead nametag pop. A UIScale on the group **or on any ancestor** changes the group's `AbsoluteSize` every frame of the tween → a texture reallocation per frame per group. On a client near its texture budget (RUST additionally carries ~48 MB of always-visible poster groups, and the client ran at `QualityLevel1`) an allocation that fails draws blank for that frame — the flicker — and a persistent failure is the blank panel.

Constraint from the owner: CanvasGroups stay (group fade, rounded clip, single-pass gradient are part of the product's look). Converting to Frames is not an option.

Alternatives considered:
- **Move the UIScale to a parent Frame** — does nothing: an ancestor scale still resizes the group.
- **Scale the content inside a fixed-size group** — needs a runtime "scale host" wrapper inside every group, which breaks every `GuiRefs` path lookup (`expect(mainWrapper, "3-NowPlayingFrame")`) and the card's own background would not pop. Too invasive for a buyer-reshaped GUI tree.
- **Keep scale, lower texture pressure only** — helps blank, does nothing for the per-frame reallocation.

## Decision

Scale animation is a *policy* decision made per target, not a hardcoded motion:

- `Shared/UI/GroupMotionPolicy.luau` (pure, headless-tested) classifies a target by shape — `isCanvasGroup`, `hasCanvasGroupAncestor`, `hasCanvasGroupDescendant` — and returns `"scale"` or `"stable"`. Anything that rasterizes through a group is `"stable"`; plain Frame trees keep the pop.
- `Client/Utils/GroupMotion.luau` builds that shape from an `Instance` and exposes `isStable(inst)` / `scaleTarget(inst, desired, resting?)`.
- In `"stable"` mode: `AnimationHelper` swaps the UIScale pop for a `GroupTransparency` fade (group targets) or the existing dialog snap/settle travel (Frames wrapping a group); toast controllers and the overhead pop route every UIScale keyframe through `scaleTarget`, which collapses to the resting scale so `AbsoluteSize` never moves. Existing `UIScale` instances are **never mutated** in stable mode (mobile scaling lives there).
- Opt-out: `Config.UIMotion.CANVAS_GROUP_SIZE_STABLE = false` (engine `Config.luau`, not `ClubKitConfig`) restores the legacy pop. A missing/junk value defaults to **stable** — an older engine config must never silently re-enable per-frame reallocation.

### Texture-budget guard (second half of the decision)

Reproduced live on RUST during this work: after a few open/close cycles the dance panel's CanvasGroups rendered **blank with every property healthy** — `Visible`, `GroupTransparency = 0`, correct `AbsoluteSize`, every child opaque. Toggling `Visible` or nudging `GroupTransparency` did not recover it. Disabling the 20 poster/board `SurfaceGui`s in Workspace (~48 MB of group textures, all allocated at spawn while 190–370 studs away) and re-toggling the panel rendered it instantly; re-enabling the posters afterwards kept everything rendering. So the failure is an allocation that fails once and is never retried while the budget is held by textures nobody is looking at.

The engine therefore owns the budget instead of relying on buyer cleanup: `Client/Services/CanvasGroupBudgetService` disables any Workspace `SurfaceGui` containing a CanvasGroup while its part is beyond `Config.CanvasGroupBudget.SURFACE_CULL_DISTANCE` (250 studs, edge distance) and re-enables it inside `DISTANCE - HYSTERESIS`. It culls only GUIs it saw enabled, restores only GUIs it culled, and honours a per-GUI opt-out attribute (`ClubKitKeepSurfaceGui = true`). Verified on RUST at the original 180: 17/20 released at spawn, all six posters restored when the camera walks up to them.

The default was raised 180 → 250 on 2026-08-28 after measuring NIGHT ZONE: its four leaderboard boards sit 194–219 studs from spawn and were therefore blank to anyone standing at spawn — a board a player is meant to read is not the same case as a decorative poster. 250 keeps those alive and still releases the far poster ring (246–318 studs there, 190–370 on RUST), which is where the bulk of the texture weight sits.

## Consequences

- Workspace posters/boards vanish beyond 250 studs (they are a few pixels tall there anyway); a buyer who wants a specific board visible from anywhere sets the opt-out attribute or raises the distance.

- Panels that are CanvasGroups open with a fade instead of a 0.96→1 scale pop; at rest they are pixel-identical. Toasts keep their slide + fade; the 0.84→0.9 scale is held at 0.9.
- One decision table for the whole client: a new animation site calls `GroupMotion.scaleTarget` instead of inventing its own guard.
- Regression seam: `.tmp/test_group_motion_policy.luau` (lune) for the policy; runtime check is "AbsoluteSize changes per frame on a visible CanvasGroup during open/close == 0".
- Not covered here (place-level, goes in UPGRADE guidance): texture budget itself — duplicate poster sets, `PixelsPerStud`, GUI duplicates, `ViewportFrame` inside a CanvasGroup, and nested groups inside `ScrollingFrame`s.
