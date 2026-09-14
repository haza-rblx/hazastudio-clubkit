# ADR 0011 — One UI motion vocabulary, reduced motion honoured everywhere

**Status:** Accepted — 2026-09-14 (owner), implemented on branch `ui-motion`

## Context

Every kit panel opens and closes through `AnimationHelper` (a 0.96→1 scale pop with optional
blur/zoom), and then sits still. The v3 music panel is the exception: `MusicMotion` gave it press
squash, icon pops, wiggles, spins, staggered row fade-ins and a layout-neutral tab slide, and the
owner wants that liveliness on the whole GUI ("fun, fluid, smooth, hidup").

Two facts constrain how that spreads:

- **`GuiService.ReducedMotionEnabled` was read by exactly one module** — `MusicMotion`.
  `AnimationHelper`, `PressFeedback`, `UISpring`, `GuiFade` and ~150 inline `TweenService`
  calls ignore it. A player who asked Roblox for less motion still got every pop.
- Kit designs lay most buttons and rows out with `UIListLayout`/`UIGridLayout`, where a
  `UIScale` changes the reserved size and makes siblings jump; and ADR 0005 forbids scaling a
  `CanvasGroup` or anything above one. Each panel re-discovering those two rules on its own is
  how the previous pass produced 35 inline tweens in one controller.

## Decision

1. **`Client/Utils/UIMotion` is the one vocabulary.** `MusicMotion` is promoted there unchanged in
   spirit (`tween` with per-property channels, `pop`/`popIn`, `wiggle`/`spin`, `fadeIn` +
   `captureBases`, `slideIn`, `bindPress`) plus `stagger`, `slideInVertical`, `bindHover`
   (pointer devices only), `pulse` and `countTo`. Every kit panel that wants motion beyond
   open/close uses it; new bespoke tween code in a panel needs a reason written next to it.
2. **Layout safety is decided by the module, not the caller.** `canScale` only allows a centred
   element whose parent has no layout and which is not in or under a `CanvasGroup`; everything
   else gets transparency, colour, rotation or padding. `slideIn` moves content with equal and
   opposite `UIPadding`, so a laid-out page never changes size.
3. **Reduced motion is honoured by every path.** `UIMotion` snaps or skips. `AnimationHelper`
   and `PressFeedback` snap to their end state when `ReducedMotionEnabled` is true. A panel
   still opens, closes and functions; it just does not move.
4. **`MotionPresets` stays the single source of durations and easing**, and `MOTION_SCALE`
   keeps scaling all of it.

## Alternatives considered

- **Per-panel bespoke motion.** More variety, but reduced motion and the layout rules would be
  re-implemented (or forgotten) per file, and the owner would have no one knob for the feel.
- **Extend `AnimationHelper` instead of a new module.** It is 917 lines of open/close and
  backdrop logic with a token/registry model built for one animation per target;
  micro-interactions (many short tweens on many small elements) fit the channel model better.

## Consequences

- `MusicMotion` is deleted; the four music views require `UIMotion`. Instance/attribute names
  it creates change (`UIMotionScale`, `UIMotionSlide`, `UIMotionRotation`) — all runtime-only.
- Panels touched in this pass are listed in `UPGRADE_PROGRESS.md`; `LoadingScreen`, the
  overhead nametags and the Workspace donation leaderboard are deliberately left alone (own
  state machines, per-player texture budget).
- Register budget (ADR 0002) is untouched: each panel adds one `require`.
- Code-only → source sync, no RBXM. Rollback is the previous commit; no data or config moves.
