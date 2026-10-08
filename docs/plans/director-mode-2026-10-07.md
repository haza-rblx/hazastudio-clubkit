# Director mode for the Cinematic Dock (paused, 2026-10-07)

The owner wants the Cinematic Dock to become a broadcast director's console with many more
cinematic features, plus event "frame" images uploaded by ID. Only the admin UI was explored, as a
static mockup in a playtest. No code exists yet. The owner paused it because the viewer side and
the system behind it are complex. This file holds the decisions and the mockup spec so work can
resume where it stopped.

## Current dock (what this replaces)

`12-CinematicDockGUI` is a bottom bar with these parts:

- Select target (player or CCTV), Select movement (36 movements from
  `Config.CinematicDock.MOVEMENT_OPTIONS`), and a speed segment (.5x to 2x).
- A Start / Stop Broadcast button.
- Popup lists `01-MovementType` and `02-TargetList`.

One broadcast sends one shot to every player through `CinematicDockBroadcast`. The rate limit is
3 per 12 s per admin. The engine has no "event mode" and no overlay image yet.

## Owner decisions (grill round, 2026-10-07)

| Question | Decision |
|---|---|
| What is director mode? | **Both** a **Sequence** (planned list of shots played in order, like a playlist) **and Live presets** (camera buttons that cut on one click, like OBS/ATEM) |
| Extra broadcast features | **All four:** on-screen text (lower third / centre title / ticker), transitions (cut / fade / dip to black / crossfade), camera look (letterbox, depth blur, grain, colour grade), countdown (3 / 5 / 10 s) |
| When the event frame image shows | **Only while a broadcast is on air**, like a TV broadcast frame. It does not stay on for the whole event. |
| How many frames | **A library** of named frames (e.g. Halloween, Birthday) stored on the server. The director picks the active one. |
| Console layout | **Bottom console**, a timeline-style strip above the hotbar |
| Relation to the old dock | **Replace it entirely** |

## Mockup spec (approved look, admin side)

Built in `12-CinematicDockGUI` as `DirectorConsoleMock`. It is 920 px wide, anchored bottom-centre
92 px above the screen bottom, and 372 px tall. It uses the **Preferences design tokens** because
the owner asked for one design system:

| Part | Token / source |
|---|---|
| Panel | like `SettingsTab`: bg `#070707`, radius 24, padding 16, gap between sections 18, title-to-content 14, stroke `#1b1b1b`, dance panel `SoftShadow` |
| Section heading | clone of `SettingsTab.Section.SectionIdentity`: title Bold 18 white, subtitle SemiBold 14 `#828282`, gap 2 |
| Cards (shots, presets, fields) | Preferences row: themed row fill, padding 12, label SemiBold 15 white, sub SemiBold 14 `#828282` |
| Card grouping | `GroupedRowCornerUtil` rule: gap 2, inner radius 4, outer radius 18 on the outer corners of a strip or grid |
| Choice controls | `MultiOption` look: track white @0.98 + stroke, padding 3, options white @0.95 radius full with gap 4, selected solid white Bold 14 black |
| Toggle | clone of `BasicToggleEnabled` |
| Action buttons (ON AIR, Stop broadcast, Show text, Start countdown) | clone of the dock's `CentralStartandStopButton` |
| Control height | 34 |

Layout from top to bottom:

1. **Top bar.**
   - Left: ON AIR button plus status "Shot 2 of 5 · CCTV Stage · 0:04 / 0:06".
   - Centre: Prev / Pause / Next options.
   - Right: Stop broadcast.
2. **Sequence.**
   - Heading "Sequence", sub "Opening Night · 5 shots · 0:41".
   - A grouped strip of shot cards, each 158 × 56: "1  DJ Rio" / "Epic Reveal · 8s · Fade".
   - The transition is written in the card's sub line, not as a chip, so the grouping stays intact.
   - The shot on air is drawn as the selected (white) card. A "+  Shot" card closes the strip.
3. **Two columns** of 436 each, gap 16:
   - **Live presets** ("Tap a camera to cut to it"):
     - A 4 × 2 grouped grid: CAM 1–7 and "+ Save / Current view".
     - The camera on air gets a red dot and a 1.5 px `#ff3b4e` ring.
     - Grid cells must use integer offsets: `CellSize (0.25,-2, 0.5,-1)`. With −1.5 the grid wraps to 3 columns.
   - **Broadcast** ("Shown to every viewer"): option tabs Text / Transition / Look / Countdown / Frame.

     | Tab | Contents |
     |---|---|
     | Text | Title and Subtitle fields; Lower third / Centre / Ticker; Show text |
     | Transition | Cut / Fade / Dip / Crossfade; 0.3s / 0.6s / 1s / 2s |
     | Look | Letterbox / Depth blur / Grain; grade None / Noir / Warm / Vivid / Cool |
     | Countdown | 3s / 5s / 10s; label field; Before sequence / Now; Start countdown |
     | Frame | named frame tiles (thumbnail + name, active tile white); "Paste image ID" field; "Show on broadcast" toggle |

Colour meaning:

- **White:** selected / on air.
- **Red:** live or broadcast action.
- Everything else follows the accent theme through the cloned owner components.

## Not decided yet (resume here)

1. **Viewer side.** What every player sees: letterbox, lower third / title / ticker placement, frame
   overlay, countdown, transitions over the shot. The next step was to mock this.
2. **Data and permissions.**
   - Where sequences, presets and the frame library are stored: a DataStore key (versioned, a
     deliberate migration) or the VPS dashboard like the event board.
   - Who may direct: existing Cinematic Dock permission only?
3. **Live preset meaning.** A preset is a target + movement + speed, or a fixed camera CFrame
   ("Save current view")? Both appear in the mockup.
4. **Rate limit vs. sequences.** The current limit is 3 broadcasts / 12 s. A sequence with short
   shots or quick live cuts would hit it. Decide whether the limit applies per sequence instead.
5. **Image moderation.** The frame library takes raw asset IDs. Decide on validation: image type,
   moderation status, and what happens to a removed asset.
6. **Phone.** The console is a desktop layout. Directing from a phone: unsupported, or a reduced version?
7. **Register budget.** The client `CinematicDockController` is already 1,957 lines. Director mode
   should be new modules under `Client/UI` or `Client/Init`, not more top-level locals (ADR 0002).
