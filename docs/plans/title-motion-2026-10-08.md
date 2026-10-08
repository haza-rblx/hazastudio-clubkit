# Custom title motion — experiment notes (paused 2026-10-08)

**Status: parked by owner.** "simpan catatannya dulu, aku masih fokus optimize performa". Nothing is built in the kit. Everything below was a client-only mockup in an Experiment Area playtest (2026-10-07/08).

## What exists today

The overhead custom title (`01-SpecialTitle` › `SpecialTitleText`) animates **colour only**:
- 33 presets in `OverheadEffects/TitleColorPreset/Presets` (gradient, stroke, pulse, rainbow…);
- the renderer's gradient modes: scan / bounce / sheen / drift / pulse / prism;
- the tuning keys `Config` `TITLE_PRESET_SPEED` / `TITLE_PRESET_SIZE`.

Nothing moves the text itself.

## The 30 mockups

All 30 were shown side by side; screenshot `.tmp/live-chip-variants/title-motion-30-grid.png`. The owner has not picked any yet.

### Whole label (1–15): 0 extra instances

These move the existing `TextLabel` (Position / Rotation / Size / a `UIScale`).

| # | Name | What moves |
|---|---|---|
| 1 | Float | Y bob, sin(t·2)·0.15 |
| 2 | Sway | Rotation ±6°, 1.8 rad/s |
| 3 | Breathe | UIScale 1 ± 0.07 |
| 4 | Heartbeat | Double beat every 1.2 s: +0.14, then +0.10 |
| 5 | Shake | Constant small random jitter |
| 6 | Jelly | Decaying squash-stretch every 2.2 s |
| 7 | Slide in | Enters from the left with ease-out, holds, slides out to the right with a fade (3 s loop) |
| 8 | Zoom pop | Elastic pop-in from 0 every 2.5 s |
| 9 | Squash | Size X/Y alternate, ±8% / ∓18% |
| 10 | Spin | One 360° ease-out spin every 4 s |
| 11 | Blink | Transparency 0 → 0.7 pulse |
| 12 | Glitch | Cyan/pink offset copies + jitter bursts every 1.8 s (+2 labels) |
| 13 | Neon flicker | Random dips + glowing pink `UIStroke` |
| 14 | Marquee | Text scrolls through a clipped row |
| 15 | Quake | A 0.45 s shake burst every 3 s |

### Per letter (16–30): about 3–4 instances per character

Each letter gets a slot Frame, a TextLabel and a UIScale, plus a UIStroke if the title has one. A 14-character title costs about 50 extra instances per head.

| # | Name | What moves |
|---|---|---|
| 16 | Wave | Travelling sine on Y |
| 17 | Pop ripple | A scale + tilt pulse runs left → right |
| 18 | Card flip | Width goes through \|cos\|, staggered; rests 2 s |
| 19 | Hop | Letters jump in sequence |
| 20 | Typewriter | Letters appear one by one, hold, loop |
| 21 | Drop in | Letters fall from above with a bounce, then fade, loop |
| 22 | Angry jitter | Each letter shakes and tilts randomly |
| 23 | Letter spin | Each letter spins 360° in turn |
| 24 | Rainbow hop | Wave + hue cycle per letter |
| 25 | Scatter | Flies apart, reassembles, holds |
| 26 | Zigzag | Alternate letters snap up and down |
| 27 | Swell | Scale wave with a long wavelength |
| 28 | Stretch | Height wave per letter |
| 29 | Spotlight | A white highlight + slight scale sweeps across |
| 30 | Fade wave | Transparency wave across the letters |

## How the per-letter split was done (reusable)

1. **Measure glyph widths.** Use `TextService:GetTextBoundsAsync`, with `GetTextBoundsParams.Font = title.FontFace` and Size 100. Cache the widths per character. Spaces get at least 26.
2. **Size the holder.** Holder width = `title.TextBounds.X / title.AbsoluteSize.X`. Read it **after one layout frame**: on a fresh clone `TextBounds` is not ready yet, and the fraction clamps to 1.
3. **Lay out the letters.** Each slot's width is that glyph's share of the total. Each letter is `TextScaled`, so all letters come out the same size without any extra sizing step. (Trying to force one `TextSize` broke this: the letters became invisible.)
4. **Colour the letters.** Each letter takes the title gradient's colour at its centre x. In this mockup the gradient was static; a real version should keep the colour presets animating.
5. **Hide the original.** Set the original label's TextTransparency to 1 and its stroke to transparent.

## If this is picked up later: open decisions

- **Which variants**, and whether to offer them as a player-selectable "motion effect" next to the colour presets.
- **Performance.** Per-letter variants cost about 50 instances per head, right after the nametag was trimmed to 55 (V6, 2026-10-07).
  - Recommendation: split into letters only for nearby heads (the existing Near/Medium/Far distance tiers); far heads show the plain label.
  - Or offer only the whole-label set (1–15).
- **One animation loop.** Run everything from one shared tick (`TitleColorPreset/SharedTick`, about 30 Hz), not a RenderStepped per head.
- **Buyer config / schema.** A new key is needed only if it becomes a buyer toggle (ADR 0001 rules).
