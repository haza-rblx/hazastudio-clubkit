# Cinematic Dock — Scene Editor experiment (2026-10-17)

Status: **UI mock only**, runs in a playtest client. Nothing in `src/` or the live place changed.

## Run it
1. Play in Studio and open the Cinematic Dock.
2. Run [`scene_editor_lab.luau`](scene_editor_lab.luau) in the client (MCP `eval_client_runtime`).
3. Clean up with `_G.CineLabCleanup()`, or stop the playtest.

## What's in the mock
- **Dock:** widened to 860 with two new buttons, Look and Scene.
- **Look panel** (quick, no timeline):
  - Filter swatches: None, Warm, Cool, B&W, Neon (+ bloom), VHS (+ blur).
  - Letterbox: Off, 2.39:1, 16:9, 9:16.
  - Overlay image ID with position (Full, Corner, Lower third) and opacity.
  - The overlay ID is checked with `GetProductInfo`. Decal IDs fall back to `rbxthumb` (max 420px, so softer).
- **Scene Editor:**
  - Presets column: built-ins plus saved presets.
  - Timeline with 3 tracks: Camera, Target, Look. `+` adds a shot; clicking the ruler scrubs.
  - Inspector per shot type: movement list with search and Cut/Blend, follow target, the Look controls, Duration stepper, Duplicate/Delete.
  - Play drives the real `CinematicCameraModes.Character` modes locally. During play the editor collapses to a transport bar and all other UI is hidden.
- Motion uses the approved centre-panel scale (Expo Out 1.2s / Cubic In 0.75s).

## Open questions before a real implementation
These need a grill-with-docs pass first.
- Preset storage: a DataStore per player (new versioned key = migration doc), per club, or both?
- Broadcast integration: does a scene play locally only, or replicate to viewers through the server's `CinematicDockController`? If it replicates, the server needs permission checks and overlay-ID validation and rate limiting.
- Should CCTV/part modes be allowed in the Camera track?
- Is beat-sync with the music system wanted?
- Register budget: the client controller is already ~1970 lines. The editor should be its own module (`Client/Init` bag).
- Mobile layout: the editor is desktop-width only right now.

## Known mock limits
- Presets live in `_G.CineLabPresets` and are lost when the playtest stops.
- Simulated MCP clicks don't reach the GUI, so the interactions still need a manual test.
