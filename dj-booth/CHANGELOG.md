# djX changelog

Releases go to the licence server with `lune run tools/release` (version from `wally.toml`).

## [Unreleased]

### Accent colour (Settings › Show › Look)
- New game setting `accent` (6 hex digits, "" = the default red), owner-chosen, one per game:
  8 preset swatches plus a custom swatch (hue ring) that opens the HSV picker under the row. Previews live while Settings is open; Discard, closing the
  panel or leaving the tab puts the saved one back. Blink schema + Net regenerated.
- `Theme.accent` is a Vide source (`Theme.accentText` = 30 % toward white). Live, active tab,
  toggles, cue pins, playing ring, DUAL DECK badge follow it; destructive buttons, errors,
  licence states and VU peaks stay `C.red`. `Theme.RED_COVER` removed.
- Default playlist and track covers (no colour set) follow it live: call sites pass
  `Covers.playlistColor` / `trackColor` inside a prop function. Access "Now" text and the low-band
  lane pick it up on the next rebuild.

### Rename: HazaDJ → CosmicDJ
- Module roots (`ReplicatedStorage` / `ServerScriptService` / `StarterPlayerScripts` `.CosmicDJ`),
  Rojo projects, `tools/package.luau`, the PlayerGui, instance names, log prefix `[CosmicDJ]`,
  tags and attributes (`CosmicDJ_DjDeck`, `_Stand`, `_Speaker`, `_BPM`, `_BeatAt`, `_Fixture`,
  `_LicenseStub*`), test hook `CosmicDJ_Test`, Blink scope `COSMICDJ` (Net regenerated).
- Kept so saved data and activations survive: DataStores `HazaDJ_v1`, `HazaDJ_Prefs_v1`,
  `HazaDJ_License_v1` and their topics; the legacy `HazaDJ_Booth` tag is still accepted.
- Wordmark: "by kosmik" → "by cosmic".

### Track loads and skips (`client/Preload.luau`, `client/Audio.luau`)
- Fixed: a track loaded onto a playing deck played from the old track's position until the
  watchdog caught it, 1-2.5 s later and at a different moment on each client (a playing Sound keeps
  its TimePosition across a SoundId swap, and the anchor had already been recorded before the load
  finished). The load loop now forgets the anchor when a load lands, so the playhead is set at once.
- Preload now warms the cache for real: each id is loaded once into a silent Sound in SoundService
  until `IsLoaded`. `ContentProvider.PreloadAsync` on a loose Sound did not help: a deck's first
  load of a "preloaded" track still took 600-760 ms; it now takes 16-19 ms.
- The load loop checks `IsLoaded` every frame instead of every 50 ms.
- Measured in a 2-client Studio playtest (DJ on client 1): a skip starts on the DJ's client
  ~0.2-0.3 s after the click (one server round trip), at the right position, and the other client
  plays within 12-62 ms of it once its copy has loaded. Players who can't open the panel don't get
  the library, so they only preload the decks and the queue; a skip to a track outside those still
  loads cold for them (0.25-1.7 s seen).
- New `Hint` event (Blink, unreliable, client → server): when the live DJ hovers a track row in the
  deck library for 0.3 s, or presses it, the server keeps it in `State.hints` (newest 3, live DJ
  only, rate-limited) and sends it to everyone in the stage (`Stage.hints`). Every client preloads
  hinted tracks at once (no 2 s debounce), up to 30 per session (`HINT_CAP`). Measured: with a hint
  0.6 s before the click a listener's cold skip started with the DJ (~0.3 s after the click, same as
  the DJ); without one it lagged 0.55-0.8 s. Too short a gap (hint still loading) doesn't help.
- Resources, measured: each preloaded or played track keeps ~0.7 MB of sound memory on that client
  for the session (Stats `Sounds` tag; it is not released). A listener grew 6.0 → 7.4 MB over four
  skips. No CosmicDJ errors on server or either client.

### Header mark (`Features/Header.luau`)
- The "xfade" wordmark is gone; the mark is the red outlined tag alone, now reading DUAL DECK DJ and
  opening with two platters (9 px, in the tag's accent text colour, each with a 3 px dark spindle
  hole). One 3 px margin runs round and between them, so the tag is 15 px tall. "by cosmic" sits
  3 px under it (was touching). Picked live: a separate platter mark before an "XFADE" wordmark
  (outlined, solid, A/B), the platters alone in the tag, the tag before XFADE, XFADE in Inter, and
  an all-white tag were tried and turned down.
- One builder, `Header.mark(zIndex)`, now draws it in the header and at the top of the lock
  screen's right column (which also lost "xfade"). The lock form keeps its old position
  (`LOGO_H` unchanged), so the shorter mark leaves a little more air above it.

### Other
- `UI/ColorPicker.luau`: the HSV picker (square, hue bar, chip, hex, Default) pulled out of
  CoverPop; the playlist cover popover and the accent row both use it.
- Settings groups have 4 px corners (`Layout.group`).
- Side nav (Access, Settings, deck library) is a tree: rows hang off a 1 px guide line (`C.card2`)
  under their caption, each on a 2 px-radius branch into a 4 px pill; the group's last visible row
  ends the line; the selected branch is in the accent. Captions after the first are 44 px (was 32).
  Picked live from four takes (white pill, headline groups and stacked tiles were turned down).
- Settings test hook: `settings diff` lists the draft keys that differ from the saved values.
- Online dot and "In this server" text are green (`C.ok`) in the list, the avatar and the detail.
- Plus buttons (Add track, New, Add DJ) draw the icon (`Controls.button{ icon = "plus" }`)
  instead of a "+" glyph.
- Settings: "Skip silence" row hidden — decks never read `autoCue`.

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
