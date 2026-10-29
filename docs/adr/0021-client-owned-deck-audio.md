# ADR 0021 — DJ booth: client-owned deck audio with a self-healing load loop

Status: Accepted, 2026-10-25 (owner, grill session). Supersedes ADR 0020 §4 ("Audio on the server").

## Context

ADR 0020 §4 put each deck on a server `Sound` in `SoundService.HazaDJ_Audio` with its effect chain,
heard by everyone through replication. It was simple: one Sound, one chain, no client sync code.
It left out the cost: when a client's download of the replicated asset fails, Roblox never retries,
the client cannot repair a Sound it does not own, and nothing notices. The booth's own `Reload.luau`
was a manual patch for exactly this ("Roblox never retries"). It made one 10 s attempt and wrote
`SoundId`/`TimePosition` onto a server-replicated Sound, which the server could overwrite again. Other
symptoms: the server re-anchors `TimePosition` every 3 s, so clients can jump. Server-side tweens of
EQ, fader and volume replicate in coarse steps.

"DJDAI" is a commercial DJ system used in large clubs, studied 2026-10-25 in its own place. It is
reliable for one reason. The server only publishes state (`startTime` on `GetServerTimeNow`), and
every client owns its Sounds and keeps loading them until they play: preload, then forceRefetch
(`SoundId = ""`, a frame, then reassign), then a bounded `IsLoaded` wait, then backoff. After a full
cycle it delays and starts again, so it never gives up while the track is still wanted.

The booth is not live at any venue yet, so it can change outright with no compatibility mode.

## Decision

1. **Server owns transport, not audio.** The server keeps play / pause / cue / pitch / mixer state and
   the anchor (`pos` at server time `at`). It creates no deck `Sound`. Deck end and auto-crossfade
   timing are computed from the anchor and `Track.len` (`pos + elapsed × speed ≥ len`), not from
   `Sound.Ended` or `TimeLength`.
   **Every player gets the room state.** `session` and `settings` go to everyone, plus a derived
   `stage` signal holding the tracks on the decks and in the queue. Before this change, only players
   who could open the panel got any state. `library` and `access` stay panel-only.
2. **Every client builds its own decks.** Deck A / B, each with the full chain (EQ, echo, reverb,
   flanger, pitch shift), feed a local master `SoundGroup` with the limiter, 2D in `SoundService`.
   Sounds are never reparented. A live Sound and its effects are mutated in place, never recreated,
   and a value that has not changed is skipped. Continuous parameters from the server are lerped over
   about 60 ms. Version 1 has no local prediction for the DJ: knobs wait for the server echo, the
   same as before.
3. **Self-healing load loop.** For each deck, up to 6 attempts per cycle:
   - preload;
   - forceRefetch, alternating the `rbxassetid://` and `https://www.roblox.com/asset/?id=` cache keys;
   - wait up to 25 s (30 s on touch devices) for the asset to load;
   - back off `min(1.5 × attempt, 8)` s.

   After a failed cycle the loop waits 8 s and starts again. A generation check stops it as soon as
   the deck's track changes. `TimeLength` 0 does not cancel: the loop falls back to `Track.len`.
   A failure shows nothing: no toast, no manual reload.
4. **Watchdog instead of buttons.** Every 2 s, a deck that the state says is playing but whose Sound is
   not playing is resumed, or re-enters the load loop. Drift is corrected on the client only when it
   is past 1.5 s. The Reload button is removed. Respawn needs no hook, because the client scripts live
   in StarterPlayerScripts. CharmSync patches arrive in order, so no extra version counters are needed.
5. **The same applies to everything else.**
   - DeckBrake runs entirely on the client's Sound, and the client stops it itself. The server's 0.4 s
     margin is removed.
   - Pad SFX become a broadcast: each client plays its own one-shot.
   - The speaker reparent and 3D path is removed (the booth is map-wide, owner 2026-10-23).
6. **Probe is lenient.** The server probe waits 25 s and makes 3 attempts. A track is marked
   `unavailable` only on an explicit `Failure`. A timeout stays pending and is re-probed after 5 minutes.
7. **Client preload order.** Tracks on the decks first, then the queue, then the library newest
   first. The cap is 300 tracks on desktop and 15 on mobile, with at most 8 loads at once.
8. **The server and handshake have no stuck states.**
   - `Ready` is retried until the server answers.
   - The `sweeping` / `fading` flags and the `Probe.many` wait are guarded: they always clear and
     always end.
9. **Tested without multiplayer.**
   - The retry/backoff policy and the position/end math are pure `shared/` modules with Lune tests.
   - In Studio, solo playtest with forced client load failures.

## Consequences

- Client code grows: chain setup, parameter lerp, load loop, watchdog, preload queue. Server `Decks`
  shrinks to state and timing.
- Every client's audio depends on getting the full state. CharmSync's initial sync on `Ready` plus the
  `Ready` retry is the one path, so it has to stay robust.
- Meters still read `PlaybackLoudness` on the local Sound. The server's `PlaybackLoudness` was always 0,
  so nothing there is lost.
- Listener latency for a knob is unchanged (one server hop). Local prediction for the DJ can be added
  later without changing this split.
- Without a Reload button there is no manual escape hatch, so the load loop and the watchdog are
  release-blocking: they must pass the forced-failure tests.
- A preload deck for the next track (DJDAI's per-channel double buffer) is deferred. Automix already
  loads the other deck ahead of the crossfade; starting that load earlier is the cheap substitute.
