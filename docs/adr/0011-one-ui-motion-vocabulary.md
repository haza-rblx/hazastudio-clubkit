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

## Current state (2026-09-17)

What the decision amounts to after every addendum below. Read this first; the addenda are the
record of how it got here and stay as written, with a note at the top of any that a later one
corrected.

- **One module, four tiers.** `Client/Utils/UIMotion` is the vocabulary. `bindPress`/`bindHover`
  pick the strongest target the button can move without shifting a sibling: **button scale**
  (`scaleTargetOf`: a centred element outside any layout and any `CanvasGroup`) → **icon**
  (`iconTargetOf`: the button's visible `ImageLabel`, or an image-bearing chip with no text of its
  own, direct child or one level into any visible non-button container; 1.08 hover / 0.92 press)
  → **text** (`textTargetOf`: a fixed-size button whose only visible child is one label centred by
  the button's own both-axes layout, no image of its own, label × 1.08 inside the padded inner
  rect; same amounts, the label frozen at its rest size for the gesture and never reparented) →
  **fallback** (press insets the button's own `UIPadding` 2–6 px, or a 15% brightness dip where an
  inset would move nothing; hover is brightness only). `UIMotionBound` records the tier:
  `true` > `"icon"` > `"text"` > `"fallback"` > `"no-target"`; `UIMotion.markBound` is its one
  writer (`PressFeedback` calls it).
- **The icon slot copies `Size`; it never measures.** An icon whose parent could reflow is moved
  once into a `UIMotionIconSlot` that takes the icon's own `Size`, `Position`, `AnchorPoint`,
  `LayoutOrder`, `ZIndex`, `SizeConstraint` and `UIAspectRatioConstraint`; the icon inside is
  `fromScale(1, 1)`. Refused only for an `AutomaticSize` icon, a parent layout sorting by `Name`,
  or a clipper that is tight around the icon (under 1.5× its box) and would cut the lift.
  The icon tier also refuses an icon with a `CanvasGroup` ancestor (ADR 0005, 2026-09-17 review) —
  a deliberate coverage reduction: the cinematic-dock favourite badge, dance-row favourite icons
  and command-library row icons fall to the fallback. `restFootprint` serves only the text tier's
  gesture-time freeze.
- **Slides are refused per axis.** `slideIn` moves the left/right padding pair, `slideInVertical`
  the top/bottom pair; a page is refused only when its `AutomaticSize` overlaps the travel axis.
  The fallback squash keeps the all-axis (`XY`) refusal. Offsets are always equal and opposite,
  so the content width is invariant and nothing re-wraps. A refusal writes
  `UIMotionSlideRefused = "X"`/`"Y"` on the page and never logs.
- **Every release path ends at rest.** Reduced motion means no tween, not no final state:
  `settleScale` runs on the instant branches of press and hover, and `tintRelease` always writes
  the captured value back, detached or not. An owned `UIScale` rests at 1 by construction
  (identity plus the `UIMotionOwned = true` attribute; a clone inherits it). A borrowed `UIScale`
  has its rest captured only while no UIMotion tween is moving it, and only the current tween
  releases a capture.
- **Per-instance state is strong and reclaimed on `Destroying`.** Weak tables keyed by Instances
  are not a lifetime mechanism: a weak entry is dropped while the Instance is still alive and
  parented. UIMotion's `MotionState` lives in a `Shared/Utils/InstanceState` store (`get` never
  creates; `of` creates and connects exactly one `Destroying:Once`; `drop` reclaims explicitly;
  never `AncestryChanged`, because pooled rows are detached and re-shown), and that store is the
  kit-wide mechanism after the 2026-09-17 sweep. The `_fadeBases` maps handed to
  `captureBases`/`fadeIn`/`stagger` are strong plain tables owned by their panel. Binds follow the
  same rule: they release their connections only on the *button's* `Destroying`. A detach just
  settles the target to rest and keeps the bind, because `ObjectPool` rows in
  `DancePanelUIBinder`/`CommandLibraryUI` are released with `Parent = nil` and re-acquired, and
  both binders bind a row once, after parenting it. A delayed `fadeIn` writes an element detached
  during the delay back to its design.
- **The feel tokens** (`MotionPresets` + `Config.UIMotion`, every one through `scaledTime`;
  `MOTION_SCALE` stays `1`): panel open 0.32 Quint Out + 0.20 Sine Out settle (0.52 s), close
  0.22 Quad In; dialog 0.24 + 0.15, close 0.17; `CENTER_OPEN_TIME` 0.40 Quint Out,
  `CENTER_CLOSE_TIME` 0.24; sidebar 0.38 Quint / 0.26 Sine with `SIDEBAR_SPRING_FREQ` 3.8 (the
  `MotionPresets` fallback is 5.0 and the config value wins); toast 0.30 / 0.22; tab slide 0.38
  Quint; row fade 0.36 Sine, `STAGGER_STEP` 0.055, `STAGGER_MAX_ROWS` 12; `pop` 0.16 Sine Out
  (was 0.12 Quad; peak 1.25); hover 0.22 Sine in / 0.18 Sine out, no overshoot; press release
  0.28 Back Out, `pressUp` 0.26
  Back Out, fallback tint release 0.24; `PRESS_DOWN_TIME` 0.08 on all four press-down paths,
  deliberately.
- **Decisions 3 and 4 are unchanged:** reduced motion is honoured on every path, and
  `MotionPresets` stays the single source of durations and easing.

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

## Addendum — 2026-09-15: decision 2's fallback, implemented

A runtime coverage marker measured the cost of leaving decision 2's "everything else" unwritten:
of 483 GuiButtons in the kit, 120 were bound through `bindPress`/`bindHover` while
`scaleTargetOf` returned nil, so press and hover did nothing at all — to the player those buttons
were dead. All three causes are legitimate refusals by `canScale` (the button carries the layout
its children sit in; the button has no children to scale; the button is under a `CanvasGroup`),
so the fix is not to loosen `canScale` but to give those buttons the promised non-scale answer.
Press now insets the button's **own** `UIPadding` by `clamp(shorter side × 0.06, 2, 6)` px on all
four sides and springs back Back-Out, reusing `slideIn`'s one-UIPadding-per-instance mechanism
(designed values recorded once as attributes, offsets taken from those, never a second
`UIPadding`); padding is internal, so the button's `AbsoluteSize` — and therefore every sibling
in its layout, and the size of any rasterized group above it — is unchanged, which is exactly why
this is legal where scale is not. Where padding would show nothing the button dips what it paints
instead: a childless button, or an `AutomaticSize` one (whose measured size *does* include its
padding, so insetting it would cause the sibling jump `canScale` exists to prevent), tweens
`BackgroundColor3` 15% toward black, else `ImageColor3`, else `TextTransparency` +0.25, captured
and restored exactly. Hover uses brightness only — 8% toward white — because holding a button's
content inset for as long as the cursor rests there reads as broken rather than alive. Reduced
motion skips the fallback entirely, and any release restores padding and colour instantly, so a
press can never leave a button dimmed. Two more runtime-only names join the list above
(`UIMotionBound = "fallback"`, and the `Squash`/`Tint` tween channels); `"no-target"` now means
only "this button paints nothing at all" — an invisible hit area. Separately, both binds now
release themselves when the button leaves the tree (`Destroying` / `AncestryChanged`), because
`bindPress` holds a `UserInputService.InputEnded` connection that list rebuilds would otherwise
accumulate once these binds became real work. Padding's one-per-instance rule turns out to apply
to `UIScale` too, so scale now borrows whichever `UIScale` the element already carries
(`MobileScaleService` on panel roots and the dance trigger, the cinematic dock magnifier,
`AnimationHelper`) rather than parenting a second, silently dead one, and press/hover/pop are
factors of that owner's **rest** value — captured the first time UIMotion pushes the scale off
rest and released only when a tween lands back on it, so an owner that re-applies its scale
between interactions is read fresh next time, while one that re-applies mid-press is overwritten
by the release instead of being captured as a stale rest.

> *Partly superseded by the 2026-09-16 entry "the icon slot copies the icon's `Size`" below: the
> slot described here as pinned to a measured rest `AbsoluteSize` now copies the icon's `Size`
> property instead. The tier itself, the chip rule and the clipping rule stand.*

**2026-09-16 — an icon tier above that fallback.** Hover's 8%-toward-white on a button that paints a
fill reads as a faint wash, and the owner rejected it: a button with an icon should lift the icon.
So `bindPress`/`bindHover` now try a third target between the two — `iconTargetOf`, the button's
visible `ImageLabel` (or an *inactive* `ImageButton`; an active nested `GuiButton` has its own bind
and swallows the input that would drive this one), direct child first, then one level into any
visible non-button container — and scale it 1.08 on hover, 0.92 on press through the
same `scaleOf`/`restScaleOf`/`scaleTo`/`settleScale` machinery the button tier uses, so an icon
already carrying someone else's `UIScale` is still borrowed relative to that owner's rest. What
"the button's icon" means had to be learned from the place rather than assumed, in three live
rounds — 86 scale / 14 icon / 159 fallback, then 204 / 51 / 240, and the owner still reporting seven
of nine top bar rows dead. The shape the first two rounds missed is the **icon chip**: a styled
badge, `UICorner` + `UIGradient` + a `UIAspectRatioConstraint`, whose own `Image` is empty because
the art lives in an `ImageLabel` nested inside it. Every top bar row is built that way; `ShopButton`
and `DonationsButton` only appeared to work because their chips happen to carry a leftover
`GuiImagePlaceholder` asset, which is a difference in leftovers, not in design. The music playlist
covers and the cinematic dock rows are the same shape, 63 buttons in all against 73 that genuinely
paint nothing. So an image-less chip now counts as an icon when it holds image-bearing art **and no
visible text of its own**, and it is the *chip* that scales, not the art inside it — corner, gradient
and art grow as one badge, and a placeholder-carrying chip behaves exactly like an empty one. The
no-text clause is the whole guard against the one false positive that matters, a button whose direct
image child is really its full-bleed background with the row's content inside: growing that grows
the row's words, which is not an icon lift. Words are what separate a badge from a surface — a badge
never labels itself, a row's chrome always does — and because it tests shape rather than size, a
99×99 playlist cover that fills its card's face still qualifies: its title and artist sit outside it,
so it holds art, no text, and zooms. A chip rejected for holding text is not lost either; the
wrapper scan reaches the art inside it and lifts that instead. That scan was widened at the same
time from a plain `Frame` to any visible non-button container (`CanvasGroup`, `ScrollingFrame`, an
image-bearing chrome panel) — worth nothing today, since no kit button wraps its icon in anything
else, and cheap insurance against the next design that does. `canScale`
is unchanged:
this tier deliberately does not consult it, because the two things `canScale` refuses are not
hazards here. **Being under a `CanvasGroup` is not one** — ADR 0005 forbids changing a rasterized
group's `AbsoluteSize`, and scaling a descendant inside the group changes nothing about the group's
own size, so the texture is never re-created; it is re-*painted*, which is what any tween in there
already does. The layout hazard is real, and is decided per button rather than refused wholesale:
the icon is scaled where it stands only when nothing above it can reflow — its parent has no
`UIGridStyleLayout`, and neither its parent nor the button has `AutomaticSize ~= None` — since
overflowing the button's own fixed bounds moves nothing (the layout above reads the button, whose
size does not change). Every other icon is moved once into a `UIMotionIconSlot`: a
`BackgroundTransparency = 1` `Frame` pinned to the icon's *measured* rest size — `AbsoluteSize` in
offsets, with its own `UIScale` and every `UIScale` above it divided back out, since the slot's
offsets get measured through those ancestors a second time and a mobile-scaled panel would
otherwise shrink its own icons — carrying the icon's `Position`, `AnchorPoint`, `LayoutOrder`,
`ZIndex`, `SizeConstraint` and its `UIAspectRatioConstraint`, taking its place in the layout and
holding that footprint while the icon — now centred and filling it — scales and spills over its
edges; the icon's `UICorner`, `UIGradient` and nested decorations stay on it and ride along. The
first cut read the slot's size off the icon's `Size` property and refused any icon under a
`UIAspectRatioConstraint`, which threw out the owner's own case: the top bar rows, the menu tabs and
the Admin v3 player cards are all constrained, and with the wash removed from `TopMenuController`
they were left with no hover at all. `Size` is simply a lie whenever a constraint is shaping the
icon; `AbsoluteSize` is the only reading that already contains the constraint's result, and once the
constraint moves up with the slot it goes on shaping the same footprint from the same parent, so
both of its `AspectType` modes land exactly where they did. This was
measured, not assumed: a bare `UIScale = 1.08` on the 38×38 icon of `TopBarMenu.Section#.ShopButton`
(own horizontal `UIListLayout`, `AutomaticSize = Y`) grew the row 38→41 px and pushed the sibling
frame +3 px, and the slot removes exactly that. One detail the slot has to get right: a layout
breaks equal `LayoutOrder`s by child order and the slot is parented last, so where the icon shares
its `LayoutOrder` with a sibling the row's current order is written out as unique `LayoutOrder`s
first — nothing moves, and the slot then copies a number that means exactly the icon's place. The
tier steps aside — back to padding/brightness —
only where the footprint cannot be pinned at all: an `AutomaticSize` icon (still sizing itself from
its own content, and it would go on doing that inside the slot), one whose parent layout sorts by
`Name`, and one whose `AbsoluteSize` is still zero because the GUI has not laid out. Clipping is the
other refusal, and it had to be narrowed for the same reason the constraint did. A clipper only
matters when it hugs the icon: a `ScrollingFrame` or a panel body is many times the icon's size, and
whenever the row is actually on screen its icon is well inside the rect — a 4%-per-side lift on a
16 px list icon is 0.64 px. Measuring those at bind time measures the list's *scroll position*, and
a bind is permanent: rows cloned while they happened to sit outside the window lost the tier for
good while the rows beside them kept it, which is a worse panel than no tier at all (32 of 40 live
refusals were exactly this, `12-CinematicDockGUI` rows among them). So a clipper now refuses only
when it is tight around the icon — under 1.5× its box on either axis — *and* the grown icon would
break out of it. Reduced motion, teardown and channels behave exactly as the button tier
does, because it is the same code: press and hover were factored into one `bindScalePress`/
`bindScaleHover` that both tiers call with their own target, factor and marker. The marker is the
fourth value of `UIMotionBound`, ordered `true` > `"icon"` > `"fallback"` > `"no-target"`, and
`UIMotionIconSlot` joins the runtime-only names above.

**2026-09-16 — a text tier under the icon tier, and a squash that admits it shows nothing.** The
owner reported the custom-title overlay's `SaveButton` and `RemoveButton` (Admin v3) as dead on
press and on hover. Both report `UIMotionBound = "fallback"`, so the audit attribute called them
healthy and they were bound — the fallback simply has nothing to show on their shape, and the shape
is a common one: an `ImageButton` with an empty `Image`, a solid fill, `AutomaticSize = None`, a
`UIPadding`, a `UICorner`, a `UIStroke`, a `UIListLayout` that centres on **both** axes, and exactly
one visible child, an auto-sized `TextLabel`. Press took the padding branch, because
`squashPaddingOf` only ever asked whether a padding *exists*; but adding the same inset to all four
sides under a layout that centres on both axes re-centres the content inside the smaller inner rect,
so a child that does not fill that rect lands on exactly the same pixel. The press was not subtle,
it was arithmetically zero — on every kit button of that shape, not only these two. Hover was the
8%-toward-white wash, which is the "slight putih aneh" the icon tier was built to remove and which
on a saturated dark fill is barely there at all. So two changes. First, `squashPaddingOf` now refuses
the padding branch when it cannot move anything: a layout on the button centring both axes and no
visible `GuiObject` child sized in *scale* on either axis — a child sized `{1, 0}` is measured from
the inner rect and really does shrink, so that shape keeps its squash. Refused before
`slidePaddingOf` runs, so a button that can never squash is not given a `UIMotionSlide` padding to
hold; with the padding refused, `bindPressFallback` falls through to the tint branch it already had
and darkens what the button paints, which is visible. Second, a **text tier** between the icon tier
and that fallback: `UIMotion.textTargetOf` returns the button's one label and `bindPress`/`bindHover`
scale it through the same `bindScalePress`/`bindScaleHover` the other two tiers use, with the icon
tier's own amounts (1.08 hover, 0.92 press) and the marker `"text"` — `UIMotionBound` is now ordered
`true` > `"icon"` > `"text"` > `"fallback"` > `"no-target"`, strongest result still winning. The tier
claims a label only where scaling it is provably layout-neutral and residue-free: the button is
`AutomaticSize = None` (its footprint cannot grow and push its siblings), no `CanvasGroup` ancestor
(ADR 0005 — a group resizes with its content), the button carries its own layout centring on both
axes (precisely what `scaleTargetOf` refuses at its `hasLayout(button)` guard, and what makes the
lift grow symmetrically instead of drifting off an alignment edge), exactly one visible `GuiObject`
child which is that `TextLabel` (one level into a plain wrapper `Frame` with no layout of its own,
the reach `scaleTargetOf`'s `pick` already has — two visible children means the layout is arranging a
row, and lifting half a row is a wobble), the button paints no image of its own (that button belongs
to the icon tier), and the label still fits: `AbsoluteSize × 1.08` inside the button's *padded* inner
rect, or the label keeps the fallback rather than spilling its words over the corner and the stroke.
A label sized to fill that inner rect therefore never qualifies, which is the right answer twice
over — it is also the shape whose squash still works.

The residue is the part that had to be measured. A `UIScale` applied to an element that is itself
`AutomaticSize` corrupts the measurement that element feeds itself: on this exact label, rest width
112 read back 120.96 at 1.08 and 138.89 at 1.20, and **destroying** the `UIScale` left it at 116.67
rather than 112, with the height going 15.0 → 15.83 at 1.20 instead of 18 and never coming back. A
`UIScale` on an *ancestor* is clean by contrast — scaling the button took the same label 116.67 → 125
and back to exactly 112 — but the button is what cannot be scaled here, which is why this tier exists
at all. So a target label that measures itself is frozen for the duration of the gesture only: its
rest `AbsoluteSize` is captured through `restFootprint` (every ancestor `UIScale` divided back out;
the icon slot used to pin a footprint the same way — see the 2026-09-16 entry below, where it stopped
measuring and this became `restFootprint`'s one caller), written as an offset `Size`, and
`AutomaticSize` set to
`None`; the original `Size` and `AutomaticSize` are handed back when the scale settles on rest — the
same `Completed`-gated moment that frees the captured rest — and on the instant/teardown paths
(`settleScale`, a detached target), where no tween will ever land to do it. The freeze is held per
instance rather than per bind, so a press landing mid-hover finds the label already frozen and one
release thaws it once. Nothing is ever left frozen: these panels rewrite their labels' text per tab,
and a stuck offset size would clip the longer wording. The label is **not** reparented into a slot
the way an icon is — kit code looks these labels up with non-recursive
`FindFirstChildWhichIsA("TextLabel")` calls (`AdminPanelV3UI.luau:215` reads the Save/Remove wording
that way to restore it per tab), and moving one would break them silently.

**2026-09-16 — the icon slot copies the icon's `Size`; it does not measure one.** The owner reported
the music library's playlist covers and the Admin v3 player picture as tiny dots, and the running
client agreed: in `06-MusicPlayerGUI…ScrollablePlaylist.djset:niki` the `PlaylistCover` sat in a slot
sized `{0, 8}, {0, 8}` (7.6 px absolute) inside a 281 × 106 row, and in
`04-AdminPanelv3…Player_8842050215` the `PlayerProfilePicture` in a `{0, 16}, {0, 16}` slot (14.1 px)
inside a 236 × 62 row — 14 slots kit-wide under 35% of their button's height, against the 98.8 px the
same `PlaylistCover` measures on `FavoritesPlaylistTabButton`, which never got a slot. The measured
pin above is the whole cause, and it is wrong in two independent ways. **A measurement has to pick a
moment, and the icon does not get to choose it.** These rows are built by a pool and bound before or
during their first layout pass — `AdminPanelV3UI` binds a player card while it is still a detached
clone, `ListPool` parents its rows `Visible = false` before `createRow` — so `restFootprint` caught a
pre-layout `AbsoluteSize` and `UDim2.fromOffset` froze it forever; nothing re-measures, because a
slot is created once per icon and `iconIn` finds it on every later bind. **And a fixed offset is the
wrong kind of value for these icons regardless of timing.** `PlaylistCover` is `Size = {0.5, 0},
{1, 0}` under a `UIAspectRatioConstraint`, `PlayerProfilePicture` is `{1, 0}, {1, 0}` — both defined
*relative to their row* — so substituting an offset severs that relationship even when the reading is
taken at a perfect moment, and a resized panel, a phone scale or a re-laid-out row stops tracking.
The premise the previous round reasoned from (a constraint makes `Size` a lie about what the row
actually measures) is true but beside the point, because the slot is not answering "how big is this
icon": it stands in the icon's *own place*, under the same parent and the same layout, and the icon
inside it becomes `fromScale(1, 1)`. A slot carrying the icon's original `Size` — with the
`UIAspectRatioConstraint` still moved up onto it, so the constraint goes on shaping that `Size` from
the same parent — therefore reproduces the footprint exactly and keeps tracking it, for scale-sized
and offset-sized icons alike, with no dependence on when the bind happened. So `slotIcon` measures
nothing at all now: the `AbsoluteSize` refusal went with the measurement, and the `AutomaticSize`
refusal stays for the reason it always had (an icon still sizing itself from its own content has no
`Size` worth copying, and would go on sizing itself inside the slot). `restFootprint` survives for
the text tier's `freezeText`, its one remaining caller, which runs at *gesture* time on a label the
player has just hovered or pressed — the one moment a measurement is known to be real. Slots are
built at runtime on `PlayerGui`, never in the `StarterGui` template, so a fresh boot builds them
fresh and no repair path is needed for the bad ones.

`iconFits` still reads `AbsoluteSize` at bind time and is deliberately left as it is. It can in
principle decide on a pre-layout reading, but the bias runs toward accepting rather than refusing: a
pre-layout measurement is *small*, and `tight` (a clipper under 1.5× the icon's box on an axis) gets
harder to satisfy as the icon reads smaller, so the loop's refusal effectively cannot fire; the only
unconditional refusal left is a zero `AbsoluteSize`, and neither reported slot hit it — both measured
non-zero and both were slotted. A wrong accept costs a 4%-per-side overflow clipped by a tight
parent, which is cosmetic. Changing that gate is its own round with its own live evidence: the last
pass that tightened it wrongly refused 8 buttons, every top bar row among them.

**2026-09-16 — every release path ends at rest, including the ones where no tween lands.** The owner
reported one music-library playlist cover rendering smaller than the rest, and the running client put
a number on it: `djset:captain papri` measured `slotAbs` 98.80 against `coverAbs` 90.896 — 98.80 ×
0.92, exactly `ICON_PRESS` — with its borrowed `UIScale` reading 0.920, while every other row read
98.80 for both. Setting that scale back to 1 restored the row, so round 5's slot geometry was right
and only the scale was wrong: the cover was not mis-sized, it was stuck mid-press. `bindScalePress`'s
`release()` opens with `if UIMotion.reduced() or not target.Parent then` — a branch that already knew
the important fact, that a detached row comes back re-shown, and acted on it for the frozen label by
thawing it, then **returned without putting the scale back**. Nothing else was ever going to: no
tween is started on that path to settle on rest, and `selfRelease`'s teardown settle fires only when
the *button* leaves the tree, while a pooled row is re-shown as the same instance carrying the same
`UIScale`. The fix is to call the teardown's own `settleScale(target)` there rather than write a
second version of it — instant, thaws the label, and never creates a `UIScale` that was not already
there (nothing captured means the scale is at rest and may belong to someone else, so it is left
alone). Reduced motion takes the same call for the same reason it always should have: reduced motion
means no tween, not no final state.

**The rule this leaves behind:** a release ends at rest on *every* path, and a path that cannot tween
settles instead of returning. `bindScaleHover`'s `MouseLeave` had the identical omission one value
up — a pooled row detached mid-hover kept 1.08 — and settles now too. `tintRelease`'s instant branch
had the fallback tiers' version of it: it dropped the capture and then skipped the write when
`element.Parent` was nil, so a detached row came back holding the press darken or the hover lighten
*and* with nothing left to restore it, and the next gesture on that row would capture the tinted
value as the design. It now always writes the captured value; a property write on a detached instance
is legal and free. That one change covers `bindHoverFallback`'s teardown and `bindPressFallback`'s
`release(true)` alike. The fallback's padding path was audited and deliberately not touched: a
`UIPadding`'s `Parent` is the button and stays set while the button is merely detached, so its guard
is a "was this padding removed" test rather than a detachment test; the release writes absolute goals
derived from the `UIMotionBase*` attributes rather than deltas, and teardown passes `instant`, so
every branch of it already lands on the designed padding.

> *One clause below is superseded by the 2026-09-17 (later the same day) addendum: "the weak-keyed
> `scaleRest` cannot lose an entry while the `UIScale` is parented" was wrong — a weak entry is
> dropped while the Instance still lives. The rest of the paragraph stands.*

**The squash cannot compound into a new rest**, which is worth stating because a 0.92 that
re-captured itself would be permanent rather than cosmetic. `scaleTo` captures the rest through
`restScaleOf` *before* the press pushes the scale off it, and the broken branch left that capture in
place — so a second press on a stuck target reads its rest as 1, not 0.92, which is why the
measurement was 0.920 and not 0.846. The only two places that clear a capture (`scaleTo`'s settling
completion and `settleScale`) both put the scale on rest first, and the weak-keyed `scaleRest` cannot
lose an entry while the `UIScale` is parented and so reachable. Capture semantics are unchanged by
this round.

**What this does not explain.** The music library never detaches a playlist row:
`LibraryView:renderPlaylists` hides spare rows through `Visuals.setVisible` and `ListPool:_redraw`
recycles with `row.instance.Visible = false`, and neither reparents nor destroys one — so
`target.Parent` is not nil for a playlist cover, and the branch repaired above should not be
reachable from that panel at all. The hole is real and the rule is right either way, but the reported
row is not evidence that this was the path it took; the alternative is a release that never fired,
which leaves the same 0.92 behind. One live check on a row that has actually been pressed and
re-rendered is what closes this.

**2026-09-16 — the slide's `AutomaticSize` refusal was over-broad; a slide is refused per axis, the
squash stays all-axis.** The owner reported that the music player's tab-switch animation had stopped.
`PanelShell:_applyTab` still calls `UIMotion.slideIn` on every real switch, but `slidePaddingOf`
returned nil and `slideIn` returned without a sound: the guard refused **any** page with
`AutomaticSize ~= None`, and all three music tab frames (`NowPlayingTab`, `LibraryTab`, `DJTab`) are
`AutomaticSize.Y`. The guard was refusing the wrong thing. A slide moves padding along **one** axis —
`slideIn` the left/right pair, `slideInVertical` the top/bottom pair — and a page only resizes if it
measures itself along *that* axis. An `AutomaticSize.Y` page slid horizontally cannot grow: the axis
that grows is not the axis being moved. `slidePaddingOf` now takes the travel axis (`X`, `Y`, or `XY`)
and refuses only when the page's `AutomaticSize` overlaps it. **`squashPaddingOf` passes `XY` and must
keep passing it:** the fallback squash insets left, right, top and bottom in one tween, so both axes
are genuinely in play and any `AutomaticSize` still brings back the sibling jump `canScale` exists to
prevent. Nothing else about the mechanism moved — the created padding is still `UIMotionSlide`, the
designed values are still `UIMotionBase*` attributes, and there is still one `UIPadding` per instance.

**The re-wrap hazard is the reason the blanket guard felt safe, and it cannot occur here.** Narrowing
a content box re-wraps `TextWrapped` text, and on an `AutomaticSize.Y` page that changes height
mid-slide — a real mechanism, and the honest objection to loosening the guard. It does not apply,
for a structural reason rather than a lucky one: `slideIn` shifts the two sides by **equal and
opposite** offsets, so `PaddingLeft + PaddingRight` is invariant and the content box's *width* never
changes — only its origin moves. Nothing can re-wrap. Measured live on `06-MusicPlayerGUI` with
`PaddingLeft +28 / PaddingRight −28` applied by hand and reverted: `LibraryTab` and `NowPlayingTab`
each held 950 × 554.80 at rest, shifted and back, dY 0.00 (`DJTab` reads 0 × 0 while hidden and is
simply uninformative). The caveat that survives is narrower and is written at the guard: an
**asymmetric** shift — one side moved further than the other — really would change the content width
and put the wobble back, so if a slide ever needs unequal offsets, the per-axis refusal stops being
sufficient. A `TextWrapped`-child refusal was considered and deliberately **not** added; there is
nothing for it to protect against while the offsets stay mirrored.

**A refusal now leaves evidence, and still no log.** This bug hid in plain sight because
`slideIn`'s nil-return was silent, and a silent no-op looks exactly like a panel nobody animated yet.
A refused slide now writes the axis it wanted (`"X"` / `"Y"`) to a runtime-only
`UIMotionSlideRefused` attribute on the page, and a slide that runs clears it — the same kind of
evidence `UIMotionBound` already leaves for the coverage audit, greppable by the same scan. It is
deliberately **not** a warning: a refusal repeats on every tab switch for the life of the session,
and a kit shipped to buyers that prints into their output window on every tab click is worse than
the silence it replaces. The attribute costs one property write on a path that already decided to do
nothing.

## Addendum — 2026-09-16: the vocabulary's feel, retuned to be enjoyed rather than obeyed

Owner: *"overall animasi ui nya dibikin smooth delightfull ajaa, gausah se snappy itu gapapa, jadi
animasinya dibuat untuk dinikmati."* Every tier above answers *what* moves; none of them ever chose
*how it should feel*. The numbers this vocabulary inherited came from `MusicMotion`, which was tuned
for one dense panel where a fast panel is a responsive panel — 0.18 s of panel travel, 0.13 s of
dialog travel, 0.14 s of hover, a 0.02–0.03 s row step. Applied to twenty-five panels they read as
efficient, which is not the same thing as pleasant. This round changes only durations and easing
curves. **No motion type was added, no API changed, no exported preset shape changed, and nothing
about `canScale`, the icon slot, the text tier or the padding squash was touched** — a rule this
round held deliberately, because a feel pass that also moves things is a feel pass nobody can revert
cleanly.

**Openings luxuriate; closes never do.** A panel now arrives over 0.32 s of Quint Out travel into a
0.20 s Sine Out settle (0.52 s in all), a dialog over 0.24 + 0.15 (0.39 s — the same shape, a touch
quicker, because a dialog is a smaller thing arriving on top of something already open), and a
centre panel over `CENTER_OPEN_TIME = 0.40`. Quart gave way to Quint for the travelling half of each
of those: at these longer durations Quart's tail is slack enough to read as drift, where Quint puts
most of the distance behind it early and spends the rest settling — motion that is generous without
being slow. Sine keeps the settle, which is the half the eye is actually watching. Every close was
softened by a curve rather than by time (`Cubic In` → `Quad In`, `Quart Out` → `Sine In` on the
sidebar and toast), and every open/close pair holds **open > close** by a wide margin: 0.52/0.22
panel, 0.39/0.17 dialog, 0.40/0.24 centre, 0.38/0.26 sidebar, 0.30/0.22 toast. A close that
luxuriates is not delight, it is a door that will not shut.

**The press-down is the one thing that stays fast, and that is the whole point.** `pressDown` holds
at **0.08 s** and `bindScalePress`'s squash, the fallback padding inset and the fallback tint hold
with it (all four now read the named `PRESS_DOWN_TIME`, with the reason written above it, so a later
pass does not sweep them up). The gap between a finger landing and the button acknowledging it is
not perceived as elegance; it is perceived as the game being slow, and no amount of grace afterwards
buys it back. The owner was told this and agreed. Everything *after* the contact is where the
delight went: the release grew 0.22 → **0.28 s** and `MotionPresets.pressUp` became **0.26 s Back
Out** instead of 0.12 s Quad Out. Overshoot is safe on exactly these targets and was checked rather
than assumed, because a `Back` on a scale inside a clipped parent is the one way this round could
have broken something visible. Back Out's overshoot is a fraction of the *travelled* distance, and a
press releases from a shallow squash: `PressFeedback`'s 0.97 → 1 peaks near 1.002, the button tier's
0.86 → 1 near 1.010, the icon and text tiers' 0.92 → 1 near 1.006. On a 16 px list icon that is
under a tenth of a pixel, and the icon tier already answers the general case properly — an icon that
could overflow its row is inside a `UIMotionIconSlot`, whose footprint does not move, and `iconFits`
has already refused any clipper tight enough to cut it. The fallback's Back Out lands on `UIPadding`,
which is internal to the button by construction, so it cannot spill at all. **Hover deliberately
gets no overshoot** — 0.22 s in / 0.18 s out, both Sine Out. A hover is a state the cursor rests in,
and a bounce under a stationary pointer reads as a glitch rather than as life; Sine also makes the
lift something the cursor arrives into rather than something that jumps up to meet it. Hover-in is
longer than hover-out (a lift is savoured, a drop is not) and never outlasts a panel open.

**The cascade reads as a cascade, and still finishes.** The row step went 0.03 → **0.055 s** with the
row fade 0.28 → 0.36 s (Quad → Sine). The existing `maxRows` cap is what keeps that honest and is
unchanged at 12: `0.055 × 11 + 0.36 = 0.965 s` is the worst case a caller passing no step can
produce, so a 20-row list settles inside a second with rows past the cap arriving together. Both
values are named constants now (`STAGGER_STEP`, `STAGGER_MAX_ROWS`) with that arithmetic written
beside them. Tab slides follow the sidebar at 0.38 s Quint Out. **Call sites that pass their own
step keep it** — eight panels tuned a step to their own list density (the 18-wide emoji grid at
0.012, the donation tiles at 0.035) and overriding those from here would be this round deciding
something it was not asked to decide.

**`MOTION_SCALE` is untouched and must stay untouched.** It remains `1`, and the new feel is baked
into the tokens rather than into the knob, precisely so that a buyer who set `0.8` still gets a
proportionally brisker kit and one who set `1.4` a slower one. Every new duration still goes through
`MotionPresets.scaledTime` (via `makeInfo` or `UIMotion`'s `info`), and the sidebar spring still
divides its frequency by the scale. That spring is the one place where the live value was *not* what
the vocabulary's default said: `MotionPresets.sidebarSpringFrequency` fell back to 6.2, but
`Config.UIMotion.SIDEBAR_SPRING_FREQ` has shadowed it with 4.8 since the TopMenu spring landed, so
the default was decorative. Both moved (6.2 → 5.0 fallback, 4.8 → **3.8** live) and the shadowing is
now written next to both, because changing only one of a pair like that produces a change nobody can
see and an explanation everybody believes.

**Reduced motion was re-read, not assumed.** A longer duration makes a missed `ReducedMotionEnabled`
branch more obviously wrong, so every path whose duration changed was walked again: `UIMotion.tween`
snaps; `fadeIn`, `stagger`, `slideIn`, `slideInVertical`, `pop`, `popIn`, `wiggle`, `spin`, `pulse`
and `countTo` return before touching a tween; both binds refuse on `InputBegan`/`MouseEnter` and
release to rest without one; `tintRelease` restores the captured colour instantly; `AnimationHelper`
snaps to its end state in all six present/dismiss paths; `PressFeedback.tweenTo` sets `Scale = 1`.
No branch was added and none was found missing.

Two hard-coded values outside `MotionPresets`/`UIMotion` had to move with the tokens, both because
leaving them would have contradicted the new set rather than merely differing from it.
`AnimationHelper:presentDialog` writes the dialog's easing inline (`DialogOpenPreset` carries no
style fields, and its shape is consumed elsewhere, so it was not widened for this): its snap went
Quart → Quint, so a dialog and a panel do not arrive along different curves. And `AdminHubUI`'s
sheet comment quoted the old dialog total (≈ 0.25 s) next to the 0.14 s fade delay it sequences
against; the number is now 0.39 s and the delay is left alone, since it still lands well inside the
travel.

## Addendum — 2026-09-17: a scale UIMotion made rests at 1, by construction

> *Superseded as the explanation by the 2026-09-17 (later the same day) addendum below: the trigger
> was the garbage collector dropping weak-keyed entries. The four decisions here remain in force.*

**Symptom.** Music library playlist covers (icon tier, `UIMotionScale` inside `UIMotionIconSlot`)
sometimes stayed enlarged after hover, and later hovers grew from there. An in-client recorder with
per-button event trails measured it: a `MouseLeave` whose tween ended on **1.080**, a later hover
reaching **1.166** (= 1.080 × 1.08) and leaving back to 1.080; on another row a steady hover with
*no* recorded event between enter and leave ended stuck at 1.080. Enter and leave counts per stuck
button were exactly equal, so no leave was dropped. The wave-5 note's "synthetic-input artifact"
(hovered icons reading 1.080 after `user_mouse_input` leave) was very probably this bug, not the
simulated cursor.

**Mechanism (proven).** `scaleRest[scale]` went nil during a steady hover; the leave's `scaleTo`
then called `restScaleOf`, which re-captured the *current* `Scale` (1.08, or a mid-tween value) as
rest, tweened "home" to it, and every later gesture multiplied from it.

**Trigger (not identified).** The only writers are `scaleTo`'s settling `Completed` handler and
`settleScale`. One interleaving that does clear it is shown in the harness: under deferred signals,
a leave tween completes and a re-enter starts its hover tween before the leave's `Completed` handler
runs, and that stale handler (state `Completed`) clears the capture the hover now holds. It needs
the re-enter in the same frame as the leave's completion, which does not fit the recorded trace with
no event between enter and leave — so it is a real hole, closed below, but not claimed as *the* cause.

**Decision — remove the failure class instead of chasing the trigger.**

1. **Owned scales rest at 1.** `scaleOf` records the `UIScale`s it creates in a weak-keyed set, by
   identity — never by `Name == "UIMotionScale"`, which a buyer's place may use. `restScaleOf`
   returns 1 for those without reading `Scale`. Whatever clears a capture, a leave on an owned scale
   goes to 1 and the next hover to 1.08. `pop`/`popIn` write `Scale = restScaleOf(scale)` first, so
   they now start from 1 on an owned scale, which was always the intent.
2. **Borrowed scales capture only at rest.** A capture is taken only when no UIMotion tween is on
   the scale's `"Scale"` channel. With a tween running and no capture, the gesture inherits the rest
   that tween was aimed from (`scaleTweenRest`, recorded per tween by `scaleTo`). If the running
   tween has none — a caller's own `UIMotion.tween(scale, …, { Scale = … })`, such as the cinematic
   dock or notification entrance — the live value is used for that one gesture and **not stored**:
   the gesture's tween records it, so its release lands where it started, and the next gesture that
   starts at rest captures the owner's real value. Nothing sticky is ever written from a mid-flight read.
3. **Only the current tween releases a capture.** The settling `Completed` handler clears the capture
   (and thaws a frozen label) only if the channel holds no other tween. `play` connects its own
   `Completed` first, so when the finished tween is still current the channel is already nil by the
   time this handler runs; a different non-nil tween means it was superseded. `== tween` is accepted
   too in case that ordering ever changes.
4. **`settleScale` resets an owned scale to 1 even with no capture** (before, a missing capture made
   it return early and leave 1.08 in place on teardown). A borrowed scale is settled to its capture or
   to the in-flight gesture's rest; with neither, it is at the owner's value and is left alone.

**Why the fix does not depend on the trigger.** For owned scales — every playlist cover — the rest is
a constant, so the capture is no longer consulted at all; no ordering of writers can move it. For
borrowed scales, the two ways a wrong rest could enter (a stale handler clearing it, a mid-flight
read storing it) are both closed independently of which one happened live.

**Known limit.** A `UIMotionScale` that existed before this client session (cloned from a template
that already carried one) is not in the owned set and takes the borrowed path — correct, just without
the constant-rest guarantee. `UIMotion` 80 → 83 top-level locals. Verified with a lune harness
(`.tmp/uimotion-scale-rest-spec.luau`): six cases, five red on the pre-fix code and all green after;
removing the handler's supersede condition turns the deferred-signal case red again.

## Addendum — 2026-09-17 (later the same day): the trigger was the garbage collector

**Superseded, not reverted.** The addendum above hardened the rest capture correctly and is still in
force, but it was not the root cause, and it failed live the same day: a `UIMotionScale` that
UIMotion had certainly created — on `NewDropsTabButton`, an element that is never cloned — was no
longer recognised as owned, and `UIMotion.pop` started from 1.08.

**Mechanism, measured.** Every piece of per-instance state UIMotion kept lived in weak-keyed tables
(`setmetatable({}, { __mode = "k" })`): `running` (instance → channel → Tween), `scaleRest`,
`ownedScales`, `tintRest`, `frozenAuto`, and `scaleTweenRest` keyed by Tween. The orchestrator ran
this in the live client:

```lua
local weak = setmetatable({}, { __mode = "k" })
do local s = Instance.new("UIScale"); s.Parent = holder; weak[s] = true end
-- churn allocations for ~40 frames, wait 1 s
-- entriesBefore=1  entriesAfterChurn=0  instanceStillInTree=true
```

**A weak-keyed entry keyed by an Instance is dropped as soon as no Lua value references that
Instance — the Instance itself stays alive, parented, in the tree.** Kit binds keep no Lua reference
to the `UIScale`s they create (the bind closures hold the button and the target, `scaleOf` finds the
scale by `FindFirstChildWhichIsA` each time), so every entry keyed by one sat on a GC timer. Each
table's loss maps to a symptom that was seen:

| Table lost | What happened |
|---|---|
| `running` | The in-flight hover-in tween was orphaned, so `play()` could not cancel it. A quick enter → leave then had the 0.22 s hover-in outlive the 0.18 s hover-out and land last — at 1.08. This is the "random" stuck cover. |
| `scaleRest` | Lost mid-hover, the leave re-captured 1.08 as rest (the trace's 1.08 → 1.1664). |
| `ownedScales` | An owned scale took the borrowed path — the previous addendum's blind spot, and the `NewDropsTabButton` observation. |
| `tintRest` | Lost mid-hold, the brightness fallback stayed lifted/dimmed. |
| `frozenAuto` | A text-tier label stayed `AutomaticSize = None` for good. |
| `scaleTweenRest` (Tween-keyed) | Same class: the inherit-the-running-rest path lost its answer. |

Nothing was baked into `StarterGui` (zero `UIMotionScale` / `UIMotionIconSlot` there), so this is
purely a runtime lifetime problem.

**Decision — strong bookkeeping, reclaimed on `Destroying`.**

1. **One strong record per instance.** `state: { [Instance]: MotionState }` with
   `MotionState = { running, owned?, scaleRest?, tintRest, frozen?, destroying }` replaces the five
   weak tables. `stateOf(instance)` makes the record on first use and connects
   `instance.Destroying:Once` — one connection per instance, held in the record so it is never
   doubled — which clears the whole record. **Only `Destroying` reclaims.** `AncestryChanged` to a
   nil parent is not destruction: pooled music rows are detached and re-shown, and their state must
   survive that. Release and teardown paths (`settleScale`, `thawText`, `tintRelease`, `cancel`,
   `cancelChannel`, the settling `Completed` handler) read `state[...]` and never call `stateOf`,
   because they can run from inside a `Destroying` handler and must not make a record nothing will
   ever reclaim.
2. **`scaleTweenRest` is strong and Tween-keyed**, and `play()`'s own `Completed:Once` — which
   fires for `Completed` and `Cancelled` alike — drops the entry, so a superseded tween's entry goes
   the moment it is cancelled.
3. **Ownership is belt and braces:** identity (`record.owned`) *and* a `UIMotionOwned = true`
   attribute stamped at creation. Safe against a buyer's place because the attribute name is
   UIMotion's own — nothing else writes it — unlike `Name == "UIMotionScale"`, which a buyer is free
   to reuse. A clone of an owned scale (a row template cloned mid-gesture) inherits the attribute and
   rests at 1, which is the right outcome for a clone.
4. **`selfRelease` and the record do not fight.** `selfRelease` still listens to the button's
   `Destroying` and settles the target; the record's own `Destroying` on the scale clears the
   record. Whichever fires first, the other finds either a live record (normal path) or none — every
   reader tolerates a missing record, and an owned scale is still owned by attribute — so both orders
   end at rest.

**Memory.** A hidden-but-alive pooled row keeps a few small entries (an empty channel map, an
ownership flag, one connection) for as long as it lives. Intended; it is bytes per row.

**Verified with the lune harness** (`.tmp/uimotion-scale-rest-spec.luau`, 14 cases, three builds).
The harness cannot trigger Roblox's collector, so `gc(M, instance)` stands in for it by dropping
that instance's entry from every exported table whose metatable is `__mode = "k"` — and nothing
else, which is exactly the engine's behaviour. Against the Round 9 build 7 cases are red (all six
GC-churn cases, including the `running` case: *"hover-in Completed, leave goal=1.0500, final
Scale=1.0800"*, plus the `scaleTweenRest` lifecycle); against this build 14/14 green, and `gc` is
a no-op there because no table is weak-keyed by an Instance any more. `UIMotion` 83 → 82 top-level
locals.

**General lesson for the kit: weak tables keyed by Instances are not a lifetime mechanism in
Roblox.** The Instance's own lifetime (parented, in the tree) and the Lua proxy's lifetime are
different things, and a weak key follows the proxy. Any state that must survive while the Instance
is alive has to be strong and reclaimed on `Destroying`. Weak keys remain fine for a pure cache,
where a lost entry costs only a recompute.

**Sweep (2026-09-17, same branch): one mechanism, kit-wide.** Every `__mode = "k"` in `src/` was
classified. Class (a) — state that must be there while the Instance lives — now goes through
`Shared/Utils/InstanceState` (`get` never creates; `of` creates on first use and connects exactly one
`Destroying:Once` per Instance, kept beside the record so it is never doubled; `drop` is the explicit,
idempotent reclaim; only `Destroying` reclaims, never `AncestryChanged`, so detached pooled rows keep
their records). It lives in `Shared/` because `WorkspaceLeaderboardRenderer` runs on both halves and a
`Client/Utils` home would have forced a Shared→Client dependency. UIMotion's own `stateOf`/`state[...]`
became `state.of`/`state.get` on the same store (81 top-level locals, 14/14 in the harness, which now
loads the real module from disk); `AnimationHelper`, `DonationLeaderboardController` (21 tables → one
`Marks` record), `WorkspaceLeaderboardRenderer`, `OverheadUI`, `UISoundHelper`, `CoupleController`,
`ImageSwap` and `Main.client` followed, each with the smallest diff and identical behaviour. The eight
`_fadeBases` maps handed to `captureBases`/`fadeIn`/`stagger` were decided as **strong plain tables
owned by the panel**: the failure with weak keys is not the benign "element skipped by `fadeIn`" — it is
the re-capture that every `captureOnce`/`_captureFades` does when it finds no entry, which under a
server echo mid-cascade records a label sitting at transparency 1 as its design. The cost is entries for
destroyed clones held until the panel goes, which is bytes per row and the precedent GiftUI and
AdminPanelUI already set. Class (b) — pure caches where a lost entry costs a recompute — stay weak with
a one-line comment at each site saying what the recompute is (`Visuals.coverKeys`,
`LibraryView.shownBackground`, `CoupleController.cardTargetTransparency`, `AnimatorUtils` ×3).
`PressFeedback` no longer stamps `UIMotionBound` itself; `UIMotion.markBound` is public and is the
attribute's one writer. Found and fixed on the way: `scaleTo`'s settling `Completed` handler had a
parameter named `state` that shadowed the record table, so in the engine `state[scale]` indexed the
`PlaybackState` EnumItem and the completed-path capture release and label thaw never ran (the lune
Enum stub indexed to nil, which is why the harness stayed green). Verified: `.tmp/instance-state-spec.luau`
8/8, `.tmp/uimotion-scale-rest-spec.luau` 14/14, lune compile 461/461 under `src/`.
