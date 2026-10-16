# DJ panel — from mockup to real (implementation plan, 2026-10-16)

Script: `StarterGui.DJGUI.DJXExperiment` in the Experiment Area place (placeId 75916114543452).
Source of truth on disk: `docs/plans/dj-panel-experiment/DJXExperiment.combined.client.luau`
(commit d53f3f6 + later patches). Look spec: `combine-spec-2026-10-16.md`. Topbar pill:
`StarterPlayer.StarterPlayerScripts.DJXTopbarTrigger`. Backup of the pre-combine script:
`ServerStorage.DJXExperiment_backup_20261016`.

## 0. Where we are

| Area | Now |
|---|---|
| Library (playlists, tracks, counts, playlist filter) | **Real** (MusicPlayerStore + read-only remote fallback) |
| Drag row → deck, blue outline | Real, **local only** |
| Deck playback, play/pause, hot cues, progress, times, jog readouts | Real, **local only** (DJ hears it, nobody else) |
| EQ HIGH/MID/LOW, FILTER, REVERB, ECHO, MASTER, crossfader + curves, MASTER meter | Real audio, **local only** |
| Header: DJ BOOTH, ON AIR, "24 listening", Crowd Hype | **Mock** |
| Minimize "—" | **Mock** (no handler); "×" closes via DJXTopbarTrigger |
| Effect pads (Air Horn, Chord 1, Drum Hat, Spaceship, Camera Shake/Rotate, Darken Camera, Ungravity) | **Mock** (local cooldown text only) |
| Queue tab rows + "Queue 3" count + "Load B" | **Mock** |
| Search box | **Mock** (no handler in section 12) |
| "Add from ID" dock | Template only, not wired |
| Center lanes, BPM tags 124/122, bar numbers, playhead | **Mock** (seeded random, fixed tempo) |
| Track-strip waveform shape | Mock shape (seeded), real playhead |
| VU A / VU B | **Bug**: A reads the loudest SoundService sound, B never fed |
| SYNC | **Mock** (no BPM data exists) |
| Jog scratch | Visual only |
| Play button before first load | Not wired |
| FX CLUB slider | Unknown (template wiring) |

The kit already has the server side most of this needs:
`MusicSetDjMode` (DJ mode, `djOwnerUserId`, permission check `no_permission`),
`MusicDjEffect` + `Config.Music` DJ effects (equalizer low/mid/high, echo, reverb, chorus,
distortion — applied to the global music Sound for **everyone**), `MusicTransport`
(pause / resume / seek / previous / clear / remove / request_many), `MusicRequestTrack`,
`MusicAdminSkip`, `MusicQueueUpdated`, `MusicStateSync`, `MusicVoteState`,
`MusicResolveRequestAsset`. Music is one global session: everyone hears the same track.

## 1. Owner decisions — **all approved as recommended (owner, 2026-10-16)**. Next: Phase 1.

- **D1 — What does "real" mean?** Recommended: **Live deck + Cue deck**. The deck marked LIVE
  drives the global session (everyone hears it, through the kit's own playback). The other
  deck is the DJ's private preview (local Sound, only the DJ hears it). Crossfading / DROP =
  switch the global session to the cue deck's track. Alternative: keep everything local
  (panel = a toy), or stream both decks to everyone (not possible with one global session).
- **D2 — Where does it live?** Recommended: **stay place-only** (DJXExperiment) for phases
  1–3, using only existing kit remotes; no `src/` change, no buyer impact. Phase 4 items that
  need new server code become a separate kit plan (engine release surface, CHANGELOG,
  UPGRADE_PROGRESS, register budget, maybe an ADR).
- **D3 — Who can use it?** Recommended: whoever `MusicService:setDjMode` accepts (same
  rank rule as today). Others: the DJ pill is hidden.
- **D4 — Effects on the live deck.** Recommended: REVERB / ECHO / EQ go through
  `MusicDjEffect` (everyone hears). FILTER, MASTER, XFADE CURVE stay DJ-local (no kit effect
  for them). Chorus / distortion: not on the panel for now.
- **D5 — Effect pads.** Recommended: WORLD pads map to existing kit commands through
  `CommandLibraryExecute` (`/ungravity`, camera / darken if a command exists, else hide);
  SFX pads (Air Horn, Chord, Drum Hat, Spaceship) need a server broadcast → phase 4 (kit),
  hidden until then.
- **D6 — Mock visuals with no data.** Recommended: BPM tags → hidden (tracks have no BPM);
  SYNC → hidden; center lanes → live loudness history of each deck (real, scrolls while
  playing); track-strip shape → keep (it is a texture, the playhead is real).
- **D7 — Header numbers.** Recommended: "N listening" = player count in the server;
  Crowd Hype = keep decorative but driven by the live deck's loudness (honest "energy"),
  or hide. ON AIR = shown only while I am the DJ owner and a live deck is playing.

## 2. Phases (each task = one Haiku run; tasks inside a phase are independent unless noted)

### Phase 1 — finish the local panel (no server writes) — **done 2026-10-16** (checksum 1733105294)

1.7 shipped local-only: a hidden Sound probes the id, then it plays on deck A.
`MusicResolveRequestAsset` was dropped because it queues the track for the whole room.

- **1.1 Search box** — section 12: `01-SearchSong` Text change → filter `visibleTracks()` by
  title/creator (case-insensitive, plain find). Accept: typing "drake" leaves only Drake rows.
- **1.2 Real Queue tab** — read the session queue (store `queue` key or `MusicQueueUpdated`;
  research which the kit store exposes), render rows like library rows, count in the tab
  label (`Queue  <font color="#767676">N</font>`), "Load B" loads that track on deck B via
  the existing `loadDeck`. Remove the 3 mock rows. Accept: count matches the kit queue.
- **1.3 VU fix** — VU A/B read `DJXDeckA` / `DJXDeckB` (`PlaybackLoudness × Volume`), same
  scale as the MASTER meter. Accept: VU B moves when only deck B plays.
- **1.4 Play button before load** — wire both play buttons at start; with nothing loaded,
  pulse the deck outline blue once ("drop a track"). Accept: no error, no silent no-op.
- **1.5 Minimize** — "—" collapses the panel to its header row (tween height), click again
  restores. Accept: library/decks hidden, header still draggable/visible.
- **1.6 Hide data-less mocks (D6)** — hide BPM tags and SYNC buttons; center lanes = rolling
  loudness history per deck (one bar per frame at 30 fps, newest at the playhead).
- **1.7 Add from ID** — find the dock in the template; on submit call
  `MusicResolveRequestAsset` (read the controller for its payload/response), then load the
  resolved track on the deck under the cursor / deck A. Accept: a valid audio id plays on A.

### Phase 2 — DJ ownership (server: existing remotes only) — **2.1 + 2.3 done, 2.2 written**

2026-10-16. DJX checksum 2090834719. Trigger disk copy `DJXTopbarTrigger.client.luau`, checksum 1530852785.
2.2 gates the pill on the store key `isControlAllowed` (the same key the Music panel uses for its
DJ tab). Owner playtest passed: the pill shows and the panel built 13 rows. This works through
`canControlMusic` (isAdminUser = false in this place). The guest-hides-pill check needs Studio's
two-client test, same as the 2.1 check.

- **2.1 Take over / ON AIR** — research `MusicSetDjMode` payload and the `MusicStateSync` /
  state fields (`isDjMode`, `djOwnerUserId`). Re-show TAKE OVER as the "Go live" button:
  fires `MusicSetDjMode {enabled = true}`; on success header shows ON AIR, button becomes
  "End set" (`enabled = false`). Errors (`no_permission`, rate limit) → small toast in the
  header. Accept: two-client test — client 2 sees the session in DJ mode.
- **2.2 Gate the pill (D3)** — DJXTopbarTrigger shows the pill only to players allowed to
  set DJ mode (same check the kit uses client-side; research where the Music panel decides
  to show its DJ tab). Accept: a guest client has no pill.
- **2.3 Header numbers (D7)** — "N listening" from `#Players:GetPlayers()`; Crowd Hype from
  the live deck's smoothed loudness.

### Phase 3 — Live deck drives the room (depends on 2.1)

- **3.1 LIVE marker** — one deck is LIVE (badge on its track tile); the other is CUE.
  Crossfader side or a click on the badge picks LIVE. Only the owner sees the controls.
- **3.2 Load on LIVE deck** — research how a DJ-mode owner plays a track now (MusicSession
  DJ-mode path: request + skip, or `MusicTransport` request_many + previous/skip). Loading
  onto the LIVE deck → session plays that track for everyone; the local deck Sound for the
  LIVE deck is muted for the DJ too (the DJ hears the room's kit playback, no double audio).
- **3.3 Transport on LIVE** — play/pause → `MusicTransport` pause/resume; hot-cue jump →
  seek. Accept: two-client test, client 2 hears pause/seek.
- **3.4 Transition (DROP)** — DROP button re-shown: plays the CUE deck's track on the room
  at the cue deck's current position (seek), CUE becomes LIVE. Optional 3-2-1 overlay that
  already exists. Crossfader past 90% toward CUE triggers the same.
- **3.5 Effects on LIVE (D4)** — REVERB / ECHO / EQ knobs on the LIVE deck send
  `MusicDjEffect` (read the controller for payload: effect id, enabled, item values;
  respect `DJ_*_RATE` limits — send on release + max 5/s while dragging). CUE deck effects stay
  local. Map: REVERB 0..1 → reverb enabled + wet; ECHO → echo enabled + wet/feedback;
  HIGH/MID/LOW dB → equalizer items. Accept: client 2 hears reverb.

**3.1 + 3.2 done 2026-10-16** (checksum 137894440). The room plays a track via MusicTransport
clear → MusicRequestTrack → MusicAdminSkip, because the kit has no "play now". Clear removes every
request in the room (set tracks stay).

**D8 (owner, 2026-10-16):** clear only on the first LIVE load after Go live. On later loads, use
MusicTransport `remove` only on the entries that sit ahead of the DJ's new entry and are not set
entries, then skip.

**3.3, 3.4, 3.5 and D5 done 2026-10-16** (checksum 888977510), each tested on a single client.
- Room seek is relative and limited to ±30 s per call.
- Room effects are not reset when DJ mode turns off, so End set sends neutral values first.
- Ungravity is the only WORLD pad left. The kit has no camera commands, so that pad works only for
  admin-panel roles. The pad strip still keeps its 80 px height.
- Known gap: if the room queue has set entries, the skip in D8 can land on a set track.
- Still to test with two clients: client 2 hears room switch, pause/seek, DROP, and reverb/EQ, and
  a guest sees no pill or badges.

### Phase 4 — needs kit (`src/`) changes → separate kit plan, not for this place script

- SFX pads broadcast (Air Horn etc.) to all clients; FILTER/MASTER for the room; BPM field
  in the web library (enables SYNC + BPM tags); real waveform data.

## 3. How every Haiku task must work

1. Edit `docs/plans/dj-panel-experiment/DJXExperiment.combined.client.luau` first (disk is the
   source of truth), matching its style; keep `--!nocheck`; new code in `do ... end` blocks
   (Luau 200-local limit); audio setters guarded (`if x ~= new then`), effects created once and
   mutated in place; nothing sent to the server unless the task says which remote.
2. Push to Studio with **anchor patches**, not a full re-upload: Studio must be in Edit mode
   (`start_stop_play false`); in one `execute_luau` (datamodel `Edit`), read
   `StarterGui.DJGUI.DJXExperiment.Source`, replace each exact unique anchor with
   `string.find(src, old, 1, true)` (assert found + unique), write with
   `ScriptEditorService:UpdateSourceAsync` (never `.Source =`). Use `[====[ ]====]` strings.
3. Verify the sync: checksum (`h = (h*31 + byte) % 2147483647`, h0 = 0) of the Studio source
   must equal the checksum of the disk file with CRLF→LF. If it does not match, stop.
4. Test in a playtest (`start_stop_play true`, datamodel `Client`): wait for
   `RealTrackRow` rows (the library fills ~10 s after join), use the `DJXLoadDeck`
   BindableEvent to load decks (the cursor cannot be moved), screenshot with
   `screen_capture`, read `LogService:GetLogHistory()` for errors. Two-player tasks (2.1, 3.x):
   say so in the report — they need Studio's multi-client test, which the owner runs.
5. Stop the playtest when done. Do not save/publish the place (owner saves with Ctrl+S).
   Do not commit. Report: what changed (line ranges), checksum, test evidence, open issues.

## 4. Order

Phase 1 tasks in parallel batches of 2–3 (they touch different sections; still push one at a
time). Then 2.1 → 2.2 / 2.3. Then 3.1 → 3.2 → 3.3 / 3.4 / 3.5. Owner two-client test after
2.1, 3.3, 3.5.
