# ADR 0014 — Track covers are drawn by the kit, never uploaded

**Status:** Accepted, 2026-09-22. Built, unreleased (rides 3.0). Cross-repo (kit + `clubkit-infra`).
**Date:** 2026-09-22

## Context

Link ingest v2 uploaded each link's thumbnail to Roblox as the track's cover. On its first day a
cover drew a moderation strike on the owner's account, "Privacy: Giving PII", for an ordinary
DJ artwork. The owner appealed twice and was denied twice. Every image upload puts the account
that runs every venue at risk, and the owner cannot work if that account is banned. The owner
also ruled out paid AI image generation ("aku mau gratis").

Thumbnail upload was switched off the same day (`LINK_COVER_UPLOAD_ENABLED`, default off).
The replacement was designed in the cover lab artifact, which the owner iterated on and approved.

## Decision

1. **Nothing is uploaded.** A track without an image cover chosen by the customer
   (`coverType = "image"`) gets a cover the client draws at runtime:
   - the artwork is a mesh gradient (`Shared/Domain/CoverMesh`), a 4×4 OKLab grid with
     Catmull-Rom interpolation, seeded by `name — creator`;
   - text sits on top, as TextLabels in Inter.
   Customer image covers keep working unchanged.
2. **Eight layouts in the first release:** editorial, sampul, samping, monogram, piringan,
   tiket, swiss and cd (`Client/UI/Music/CoverTile`).
3. **Every cover setting lives on the web, and a Studio place holds none of them.** The owner
   said on 2026-09-22 that everything is edited on the web and the Studio side is "tinggal
   pasang" (just install). An earlier draft put these in `ClubKitConfig` plus a player setting;
   that was reverted. The settings are:
   - **Layout: per playlist.** `playlists.cover_layout`, where `NULL` means editorial and
     `"none"` means no template. Only the web writes it; a sync from the game never touches the
     column. The dashboard shows it as one Cover control with three tabs: Gradien, Gambar and
     Template (owner, 2026-09-22: two separate sections were confusing).
     - **Template:** each song gets a drawn `cover`. The playlist card also gets one, with its
       name (10 characters) as the headline and no subline.
     - **Gradien or Gambar (`"none"`):** neither the songs nor the card get a `cover`, so the
       game shows the playlist's gradient or image for all of them.
     - A song's own image beats every tab.
   - **Headline mode and corner mark: per venue.** They are stored in `venue_cover_settings`:
     - `headlineMode` is `playlist` (the playlist name, at most 10 characters, the default) or
       `title` (the song title, at most 26 characters);
     - `mark` is `""` for the experience's name, `"-"` for none, or the literal text.
   - **Lines: per track.** `library/cover-text.ts` runs 15 deterministic rules over the raw link
     or file title, the DJ, the playlist and the length. Customers can edit the result, and
     guessed text is marked "Perlu dicek".
   - **Players choose nothing.** The in-game Settings item was removed.
   brm-api resolves all of it (`library/cover-style.ts`) into one `track.cover`:
   `{ layout, headline, subline?, venueAlt, kicker?, mark }`. The kit
   (`Shared/Domain/CoverTextPick`) applies only what needs the game:
   - `mark ""` becomes the experience's name;
   - the venue-name swap (a subline that repeats the corner mark);
   - the ticket's 10-character clip.
   A layout the kit does not know draws as editorial, so the web can add layouts first.
   The dashboard previews covers with the same lab code (`dashboard/src/lib/cover-tile.ts`), so
   what the customer picks is what the game draws.
4. **The UIGradient fallback is the main path, not a degraded one.** EditableImage in a
   published experience needs an owner who is 13+ and ID-verified, with "Enable Mesh / Image
   APIs" turned on. Most venues will not have that.
   - Every cover first paints three UIGradient layers from the same mesh: rows, columns at 55%,
     and the corner diagonal.
   - Where an EditableImage can be created, a 128×128 image replaces the layers. It is built a
     few rows per frame, one per frame at most, shared per `name — creator|mood`, and kept in an
     LRU cache of 64 entries (about 4 MB).
5. **Full tiles are a CanvasGroup; list rows show artwork only.** UICorner never clips children,
   so a full tile is a CanvasGroup whose rounded corner clips everything inside it. List and
   queue rows (compact mode) show a plain Frame with the artwork only.

## Consequences

- There is no moderation surface and no asset or Open Cloud dependency for covers. A cover
  renders the same on every client, because the seed and the rules are deterministic, and
  `.tmp/cover-mesh-spec.luau` checks parity against the lab JS across 926 values.
- The trade-offs are instances and memory, not bandwidth:
  - a full tile is about 30–90 instances (the ticket is the heaviest because of its dot rows);
  - there is one CanvasGroup texture per visible full tile, at most three on screen (detail,
    Now Playing, vote card);
  - compact rows are about 1–7 instances each.
- Text is always a real TextLabel, never baked into an image. Roblox has no letter-spacing and no
  text-shadow, and the lab was designed within those limits.
- The ticket's punched notches are circles painted in the nearest opaque ancestor's colour. On
  a translucent panel they show as dots rather than holes.
- A kit older than 3.0 ignores `cover` and keeps showing the playlist cover.
- There are no `ClubKitConfig` keys and no `Settings_v1` field, so nothing needs a fill-forward or
  DataStore migration. The price is that a place cannot override the look offline: a venue
  changes covers only through the dashboard.

## Addendum 2026-09-24 — artwork v2: board colours, soft Apple-style fields, crop

The owner judged the v1 mesh out of spectrum with the leaderboards and the UI: its base hue was
drawn from the whole wheel (greens, teals, cyans the kit UI never uses), and its "neon" mood is
the look already rejected on the boards. After several preview rounds the owner chose:

- **Colour = one board family per track.** Six families, the boards' own hues and glow triads
  (orange 16, red 356, pink 328, purple 288, violet 262, blue 214). Dark by design: a near-black
  base, the board's dark tones, glows at mid value, one lit accent. No gold or yellow — darkened,
  they read olive and mustard (seen in Studio), so the owner dropped the gold family and orange's
  glows stop at 24 with dark tones leaning red. No green, teal or neon.
- **Form = three Apple-style fields**, one per track: a 3×3 mesh (B-spline, no overshoot), light
  from above (Now Playing), folded sheets (Ventura). Layered waves (Sonoma) were tried and dropped. The owner asked for a
  very strong blur ("120") and no grain. Each style is an analytic field with soft edges, so the
  blur is the edge width (`W = 0.56`) and nothing runs a blur pass; the kit and the dashboard draw
  the same pixels from the same code (JS reference `mesh-core-v2.js`, parity spec
  `.tmp/cover-mesh-spec.luau` 267/267).
- **Crop, never stretch.** The artwork is square; wide or tall slots crop it
  (`ScaleType.Crop` in `CoverArt`, `object-fit: cover` on the dashboard canvas).
- **EditableImage is 48×48, not 128×128.** v2 has no detail finer than a third of the tile, and
  the richer fields cost 3× more per pixel (measured in Studio: 1.6 s per cover at 128², 0.5 s for
  v1). At 48² a cover draws 7× faster and holds 9 KB instead of 64 KB; the engine's upscale is
  invisible on artwork this soft.

Consequences: every track's artwork changes once when a venue takes this kit version, then stays
fixed per title + DJ. The UIGradient path, the tints and the glow colour now read a 4×4 grid
*sampled* from the artwork rather than the mesh nodes themselves. `Mood` stays in the API for
cache keys and dark paper, but every cover is "dusk". The dashboard preview went live on
2026-09-24, ahead of the kit release (owner's call: only THE BASIC ran v2 then), so other venues
preview v2 while their games draw v1 until they update.
