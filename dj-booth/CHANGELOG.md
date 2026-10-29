# djX changelog

Releases go to the licence server with `lune run tools/release` (version from `wally.toml`).

## [0.2.2] — 2026-10-29

### Lock screen (`Features/Lock.luau`)
- Fixed: the artwork covered the whole 1250 × 802 canvas, so it ran under the activation form.
  It now fills the left half only (`fromScale(0.5, 1)`), which is the column `RIGHT_X = 937` was
  always written for. Verified in playtest: artwork 625 × 802, form at 785–1089, centre 937.

### Settings (`Features/Settings.luau`)
- New right-hand column: the lock screen's artwork (rbxassetid://110878579761479, Crop) in a
  300 px tile, so the tab reads as part of the same panel. The section column narrows 937 → 635;
  nav 311 + main 635 + side 300 + two 2 px gutters = 1250, unchanged.
- The tile starts 1 px below the header's bottom edge and runs to the panel's bottom (y = -1,
  height `PAGE_H + 1`), so it never bleeds under the header, whose background is only 80 % opaque.

## [0.2.1] — 2026-10-28

### Lock screen (`Features/Lock.luau`)
- Redesigned: full-bleed artwork behind the panel, xfade mark at the top of the right column, the
  activation form centred between the mark and the copyright.
- Copy: title "Your DJ deck is / waiting backstage.", body "Enter your activation code".
- Backstage pass, lanyard, beam, stamps and the "ALL ACCESS" band removed. The guest pass modal stays.
- Unlock: the whole panel rises 0.7 s with its contents, then hides.

## [0.2.0] — 2026-10-26

Released: template 433 KB, sha256 `7717630e5c65…`. Commit `fe9dec1`. Every look below was picked
live in the DJX Lite playtest by the owner.

### Unlock and lock screen (`Features/Lock.luau`, `App.luau`)
- The unlock reveal is now **curtain**: the pass lifts away, a white seam runs down the middle, then
  the two halves part (Exponential InOut 0.9 s). Picked from four takes; iris, tile wave and "zoom
  through the pass" were turned down.
- The lock screen uses the deck's surface colour (`C.tile`, `#0b0b0b`) instead of pure black, so
  the doors open onto the same colour. Its corners match the panel (4 px).
- After an unlock, the deck rows rise into place one after another (28 px, Exponential Out 0.8 s,
  0.07 s apart) under a veil in the panel colour. Lock calls `onReveal`, App runs `riseIn`. Skipped
  with Reduce Motion.
- Fixed: while celebrating, the pass band read "ALL ACCESS" next to "NOT ACTIVATED"; it now says
  "ACTIVATED".
- Studio only: changing `ReplicatedStorage.HazaDJ`'s `UnlockPreview` attribute replays the unlock
  without a code.

### Header and panel (`Features/Header.luau`, `App.luau`)
- Wordmark: **xfade** (Builder Extended ExtraBold 19) with a red outlined **DUAL DECK** tag
  (`C.redText`, 1 px, 2 px corners, 16 px tall, text 12), over **by kosmik** (12, 50 %). Nudged
  1 px up. Names tried and dropped on the way: crossfade, rekordblox (too close to rekordbox),
  kosmik dj pro.
- The header is 80 % opaque so the room shows through it. The panel itself is see-through; the rows
  under the header sit on a solid `Body` frame so the 2 px gutters stay solid.
- Panel corners are 4 px. Rounded corners don't clip children, so App's `roundCorners` rounds
  whichever tile sits in a panel corner. It re-runs on mode, page and open, and puts back what it
  rounded last time.
- Soft drop shadow (`UIShadow`: black, 0.45, blur 40, 12 px down, `ShowBehindParent = false` so it
  doesn't darken behind the see-through header).

### Hover (`UI/Hover.luau`, new, plus 12 UI files)
- Roblox fires `MouseEnter`, and sets `GuiState`, on everything under the pointer, so pads and rows
  under an open menu, modal or the lock lit up. One watcher now asks
  `PlayerGui:GetGuiObjectsAtPosition`, takes the topmost object that catches input, and lights only
  tracked objects on its path. Use `Hover.track(source)` as a Vide child, or
  `Hover.watch(instance, source)`.
- The top-bar inset differs between the pointer and `GetGuiObjectsAtPosition` depending on where the
  game runs, so the offset is learned the first time Roblox reports a `MouseEnter` on a tracked
  object. Until then nothing lights.
- Nothing lights while a fader, knob, slider or jog is dragged (`Hover.hold()` in
  `Hardware.drag`, `Controls` sliders and the jog).
- Left as they were: two `MouseEnter` tweens in `Library/init.luau`.

### Settings (`Features/Settings.luau`, `net/djdeck.blink`, `shared/Defaults.luau`, `server/Services/Commands.luau`)
- New **Play on load** (Decks › Loading, default on): a track the DJ drops or loads starts right
  away, as it always did; off leaves it paused on its cue. Auto mix's own loads never autoplay.
  Saved settings fill forward, so no migration is needed. Blink was regenerated.
- Hidden: Open at the DJ deck, DJs only behind the decks, Name above the DJ deck and Lights follow
  the beat. The first three need parts tagged `HazaDJ_DjDeck` / `HazaDJ_Stand`, which no game had;
  nothing reads the lights' beat attributes. The code and saved values remain, ready for an
  in-game DJ deck setup.

### Track header markers (`Features/Decks/Deck.luau`)
- Each set hot cue is a **pin**: its number in a slightly flat 16×12 pill head (white, or red for
  the one last hit, with a dark 1.5 px rim) on a 1 px stem down to the progress line. Later pins
  stack over earlier ones. At the panel ends the head stays whole and the stem keeps the true spot.
- The CUE point is a red triangle pointing down onto the line, drawn over the pins.
- The title, meta, times and eject sit 3–4 px higher to make room for the heads.
- Tried and dropped: flags with labels beside a pole, two rows above and below the line, an
  inline thick bar, an overview band, and plain ticks without numbers.

### Not done
- DJX Lite runs this code in edit mode but the place isn't saved.
- The djX deck is PC only; phone and touch gaps are out of scope.
- Hot cues set while testing ("Ya Tab Tab" 1–4) live in DJX Lite's library.

## [0.1.0]

First licensed release: in-game activation and lock screen, stamped downloads, release script.
