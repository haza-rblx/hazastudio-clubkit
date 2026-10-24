# HazaDJ — standalone DJ booth

The DJ booth designed live in Place1 (2026-10-22/23), rebuilt as a real, self-contained system:
two decks with server-side audio, a library with playlists and pads, access control and booth
settings, all persisted. It does not depend on the Club Kit. Decision record:
[`docs/adr/0020-standalone-dj-booth-stack.md`](../docs/adr/0020-standalone-dj-booth-stack.md).

## Stack

| Layer | Library | Why |
|---|---|---|
| UI | **Vide** 0.4 | fine-grained reactivity, typecheckable, cheap per-frame updates |
| State | **Charm** 0.11 + **CharmSync** 0.4 (+ vide-charm) | server signals, delta-patched to the players who may see them |
| Client → server | **Blink** 0.18 (`net/booth.blink`) | typed, range-checked buffers; one `Do` function + `Live` / `Nudge` events |
| Topbar button | **TopbarPlus** 3.5 | the "DJ" icon opens / closes the panel; shown only to players with access |
| Player prefs | **ProfileStore** 1.0 | per-player, session-locked ("This panel" settings, view mode) |
| Booth data | DataStore `HazaDJ_v1` / key `booth` | global document, debounced `UpdateAsync`, `MessagingService` reload |
| Tooling | Rojo 7.5 · Wally · Rokit · StyLua · Selene · luau-lsp · Lune | `rokit install` pins them all |

## Layout

```
net/booth.blink          network schema (generates src/*/Net.luau and src/shared/NetTypes.luau)
src/shared/              ReplicatedStorage.HazaDJ.Shared — pure modules
  Types  Defaults  Fixture  Format  Mix  Queue  Rules  Dict
src/server/              ServerScriptService.HazaDJ
  init.server            starts the services in order
  Services/State         Charm signals: library, access, settings, session, per-player me
  Services/Store         the booth document (load, debounced save, cross-server reload)
  Services/Roles         Owner / Resident / Guest / gate guests, prefs via ProfileStore
  Services/Sync          CharmSync subscriptions (panel data only to players with access)
  Services/Booth         who is live, take-over rule, idle / longest-set limits, stats
  Services/Decks         audio engine: Sounds, EQ/filter/echo/reverb/flanger/key lock, mixer, queue
  Services/Library       tracks, playlists, sounds, pads edits (validated)
  Services/Pads          SFX one-shots, world effects, booth-wide cooldowns
  Services/Probe         asset checks (name, creator, length; background re-check)
  Services/Show          announcements, now playing, name billboard, beat attributes, booth prompt
  Services/Commands      the one door in: role checks, rate limit, dispatch
src/client/              StarterPlayerScripts.HazaDJ
  init.client  App  Store  Actions  Theme  Toast  WorldFx  Debug(Studio only)
  UI/                    Base, Controls, Layout, Covers, Hardware — the design system
  Features/              Header, Decks/*, Library/*, Access, Settings
tests/run.luau           unit tests for the shared modules (Lune)
tests/golden/            the prototype's rendered output, 28 screens (parity reference)
tools/build.sh           blink + rojo build → build/{shared,server,client,parity}.rbxm
tools/parity/            the Studio parity checker (compares the live panel with a golden)
```

## Build, install, test

```sh
rokit install && wally install      # once
./tools/build.sh                    # → build/*.rbxm
lune run tests/run                  # 53 unit tests
selene src && stylua --check src    # lint / format
```

Install in a place: put `build/shared.rbxm` in **ReplicatedStorage**, `build/server.rbxm` in
**ServerScriptService**, `build/client.rbxm` in **StarterPlayer › StarterPlayerScripts** (each
arrives as a `HazaDJ` folder/script). Turn on *Game Settings › Security › Enable Studio Access to
API Services* to save in Studio. Development can also use `rojo serve default.project.json`.

### Deck off (the brake) and the queue

- **Deck off.** ■, ✕, or CUE on a playing deck slows the record down like a turntable losing power. The server keeps the transport. Each client runs the effect on its own copy of the Sound (`src/client/DeckBrake.luau`).
  - Presets, and the asset ids for the click, hum, dust, needle and thump layers (`0` skips a layer), are in `src/shared/DeckBrakeConfig.luau`.
  - The owner picks a preset under **Settings › Decks › Deck off**. *Instant* turns the brake off.
- **Queue.** One shared list. **Q** on a track adds it, and **Queue all** on a playlist adds every track, in order or shuffled per the playlist.
- **Auto mix** (Queue tab, on by default). When the live deck nears its end, the next queued track loads on the idle deck and the crossfader sweeps over it, using the *Auto crossfade* time. With 0 s it cuts at the end. With Auto mix off, the queue is only a list to load from.

### Venue hooks (tag parts with CollectionService)

| Tag | Used for |
|---|---|
| `HazaDJ_Booth` | the "Open the decks" prompt, the live DJ's name billboard, "near the booth" pads |
| `HazaDJ_Stand` | the floor behind the decks ("DJs only behind the decks" keeps others off it) |
| `HazaDJ_Speaker` | where the decks play from in *Club zone* / *Booth area* mode |

Club lights can follow the beat from `workspace:GetAttribute("HazaDJ_BPM")` and
`HazaDJ_BeatAt` (server time of a beat).

### Who can do what

| | Owner (creator / group rank 255) | Resident | Guest (listed, group rank, game pass) | Everyone else |
|---|---|---|---|---|
| Open the panel, play decks and pads | ✓ | ✓ | ✓ | – |
| Edit library, playlists, pads | ✓ | ✓ | – | – |
| Edit access and booth settings | ✓ | – | – | – |
| Take over a live set | always | if the rule allows | if "Any DJ" | – |

The server enforces every row; the client only mirrors it.

## Parity with the prototype

The prototype (`docs/plans/dj-panel-experiment/`) was dumped screen by screen as display lists
(`tests/golden/`). With `workspace:SetAttribute("HazaDJ_Fixture", true)` in Studio, the server seeds
the prototype's mock data, and `tools/parity` compares what the new panel draws with each golden
(occlusion-aware, 1 px tolerance). Last run (2026-10-23): Library, Access and Settings screens
**100 %** (a couple of single-label exceptions), Decks **99.9 %** once live readouts are excluded.
Known, intended differences: the jog / header / meter readouts are live instead of frozen mock
numbers, and "TEMPO ±16%" follows the booth's pitch-range setting (the mock said ±8%).
