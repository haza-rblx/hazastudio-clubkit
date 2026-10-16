# DJXExperiment — combine spec (2026-10-16)

The owner approved the look below. It was built as runtime edits in a playtest of the
Experiment Area place (placeId 75916114543452), on top of the **older** DJXExperiment that
lives in the place (1208 lines, no section 13). The repo copy
`docs/plans/dj-panel-experiment/DJXExperiment.client.luau` is **newer** (section 13: drag a
row to a deck + real local playback per deck).

Goal: one script = repo copy + this look. Output file:
`docs/plans/dj-panel-experiment/DJXExperiment.combined.client.luau`.

All paths below are under `DJGUI["9-AdvancedDJ"]` unless noted. Apply the look after the
repo code has built its UI (e.g. one `task.defer` / end-of-script section), so it wins.

## A. Darker palette (single pass, exact original hex → new)

GuiObject `BackgroundColor3` under 9-AdvancedDJ:

| from | to |
|---|---|
| 1c1c1c | 141414 |
| 1d1d1d | 0f0f0f |
| 181818 | 0f0f0f |
| 141414 | 0a0a0a |
| 0c0c0c | 0a0a0a |
| 2a2a2a | 141414 |
| 222222 | 141414 |

Map each object once from its *original* value (never chain 1c→14→0a).
`UIGradient` under 9-AdvancedDJ: every keypoint that is near-grey
(max(R,G,B) − min(R,G,B) < 0.05) and 0.1 < max < 0.3 → multiply RGB by 0.55. Coloured
keypoints untouched. Accents (#2ec86e, #ff963c, playlist covers) untouched.

## B. Header

In `DJX_Header`: hide (Visible=false, do not destroy) the `DROP` and `TAKE OVER`
TextButtons and the 1×20 divider Frame between them and the minimize button. Keep `—`
and `×`, title, ON AIR, listening, Crowd Hype.

## C. Bottom strip — `DJ_Deck.EffectWrapperBottom` (5 slot Frames, sort by AbsolutePosition.X)

Final order, left → right:

1. **FX CLUB** — the original wired slider, unchanged.
2. **REVERB**
3. **MASTER** + level meter
4. **ECHO**
5. **XFADE CURVE**

(The template had FX CLUB, PITCH, empty, FX CLUB, FX CLUB. PITCH is dropped: deck speed
already lives on the deck.)

Slots 2–5: hide the template slider Frame (it may be wired by AdvancedDJController), put an
unwired clone in its place (keep the clone's Name `Frame` — the slot's UIListLayout sorts
by LayoutOrder/Name), set the label TextLabel text. Slot 3 is empty in the template: clone
the label Frame + slider Frame + UIListLayout + UIPadding from slot 2. MASTER label colour
#c8c8cc.

Slider behaviour (own code, all four): click/drag on the slider Frame sets v = (mouseX −
track.X) / track.width, clamped 0..1. Track = the Frame with height ≤ 8 and width > 40.
Handle = the 22×27 Frame that is a **sibling of the track** (not the `DJX_Cap` inside it).
Handle `AnchorPoint = (0, 0.5)`, `Position = UDim2.new(v, -handleW * v, 0.5, 0)`.
Add `DJX_Fill` (bg #4a4a52, copy the track's UICorner) inside the track, width = handle
centre − track.X. Initial values: REVERB 0, ECHO 0, MASTER 0.8, XFADE CURVE 0.5.

What each slider drives (use the repo's section-13 deck Sounds / gains, not "the loudest
Sound in the game"):

- **MASTER**: multiplies the final volume of both deck Sounds.
- **XFADE CURVE**: shapes the crossfader → gains curve the repo already computes
  (0 = smooth / equal-power, 1 = sharp / cut). If the repo has no curve parameter, add one.
- **REVERB**: a `ReverbSoundEffect` named `DJX_Reverb` on each deck Sound.
  WetLevel = v > 0 and (−30 + v·30) or −80, DecayTime 2.2.
- **ECHO**: an `EchoSoundEffect` named `DJX_Echo` on each deck Sound. WetLevel = v > 0 and
  (−24 + v·24) or −80, DryLevel 0, Feedback 0.2 + v·0.4, Delay 0.35.

Repo audio rule: create each effect once, then mutate in place; every setter returns early
when the value is unchanged; never destroy/recreate an effect on a playing Sound.

Slot layout: every slot's UIListLayout `VerticalAlignment = Center`, `Padding = 4px`;
UIPadding top/bottom 0; every visible slider Frame (incl. FX CLUB) height 28px.

MASTER meter `DJX_Meter`: child of the MASTER slider Frame, 10 bars, 4px wide, 2px gap
(total 58px), height 16, `AnchorPoint (1, 0.5)`, `Position UDim2.new(1, 58 + 14, 0.5, 0)`;
MASTER slider Frame width `UDim2.new(1, -(58 + 14), 0, 28)`. Bar i height 4 + i·1.2, anchored
bottom, UICorner 1px. Bars lit by level = clamp(max deck PlaybackLoudness·Volume / 400);
fast attack, release ×0.88 per frame (~30 fps); off #1f1f22, on #4a4a52, bars 8–10 #d85a30.

## D. Library tabs — `DJGUI.DJX_Overlay.DJX_Tabs`

- Remove the **Requests** tab (hide its button; Library is the default view).
- Container: height 40, bg #0a0a0a, UICorner 4px, no UIStroke.
- Buttons: FontFace `rbxassetid://12187365364` Medium, TextSize 16, sentence case, UICorner
  3px, active bg #222226 (existing select() toggles BackgroundTransparency), inactive text
  #767676. Queue label RichText: `Queue  <font color="#767676">3</font>`.
- This matches the search TextBox `01-SearchSong` (40 tall, #0a0a0a, 4px, 16 Medium).

## E. Drag to deck (repo section 13)

Keep the repo behaviour, change colours: drop outline UIStroke `DropOutline` colour
**#4c7dff**, thickness 2. Ghost: bg #141414, UICorner 4px; hint text / rim colour #4c7dff
while over a deck, #767676 / #2a2a2e otherwise.

## F. Library data

The runtime version fetched playlists/tracks via the read-only remotes `MusicGetPlaylists`
/ `MusicGetTracks` (request `{requestId}` → `MusicResponse` with matching requestId; data
is a dict keyed by id). If the repo copy already renders real playlists/tracks from
`MusicPlayerStore`, keep the repo's way. Otherwise port: playlist column = "All Tracks" +
one row per playlist (name, "N Tracks", image cover when `coverType == "image"`), clicking
filters the track list; search box filters by title/creator.

## Constraints

- Keep `--!nocheck`; nothing new sent to the server (read-only remotes only).
- Place-only mockup: do not touch `src/`.
- Do not edit the original repo copy; write the combined file.
