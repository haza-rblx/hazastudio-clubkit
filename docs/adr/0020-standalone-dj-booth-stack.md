# ADR 0020 — Standalone DJ booth: its own package, a Vide/Charm/Blink stack, server-authoritative audio

Status: Accepted, 2026-10-23 — decided by the agent during an overnight build the owner handed over
("abaikan stack lama ... pake fw2 happening ... akurasinya 100% sama"). Open to review.

## Context

The DJ booth UI was designed live in Place1 as two place-only LocalScripts
(`docs/plans/dj-panel-experiment/DJXTabs.client.luau`, `DJXExperiment.combined.client.luau`,
~360k chars together). They restyle the kit's `9-AdvancedDJ` template at runtime, keep all data as
client-local mocks, and sit over 4,700 GUI instances in StarterGui. The owner asked for the real
thing: working, tidy, industry-standard, component-based, using current Roblox frameworks, and
**visually identical** to the prototype. The old kit stack (MusicPlayerStore, kit remotes, the
template) is explicitly out of scope.

## Decision

1. **Own package** at `dj-booth/` with its own Rojo project, Wally manifest and Rokit toolchain.
   It does not require anything from the kit and the kit does not require it. Instances live under
   `ReplicatedStorage.HazaDJ`, `ServerScriptService.HazaDJ`, `StarterPlayerScripts.HazaDJ`.
2. **Stack**
   - UI: **Vide 0.4** (fine-grained, typecheckable). Every surface is built in code; no template.
   - State: **Charm 0.11** signals on the server, replicated with **CharmSync 0.4** (delta patches,
     per-client subscriptions); bridged into Vide with **vide-charm**.
   - Client → server: **Blink 0.18** IDL (`dj-booth/net/booth.blink`), typed and range-checked on
     receive, one tagged-enum `Command` event plus a few functions.
   - Player preferences ("This panel"): **ProfileStore 1.0** (per-player, session-locked).
   - Booth data (library, playlists, pads, sounds, access, settings) is **global** state, which
     ProfileStore is not designed for: one DataStore document written with `UpdateAsync`
     (debounced), with `MessagingService` telling other servers to reload.
   - Tooling: StyLua, Selene, luau-lsp, Lune tests for pure modules.
3. **Server-authoritative.** Clients send intents; the server checks the sender's role
   (Owner / Resident / Guest / gate guest), validates, mutates signals, and CharmSync fans out.
   Library, access and settings sync only to players who may open the panel.
4. *(Superseded by ADR 0021, 2026-10-25: deck audio is client-owned.)* **Audio on the server.** Each deck is a server `Sound` with its own EQ / filter / FX chain in a
   `SoundGroup`; everyone hears it through replication. Meters read `PlaybackLoudness` on each client.
   Positions are anchored (`pos`, `at` server time) so every client can draw time without traffic.
5. **Parity is measured, not eyeballed.** The prototype's rendered output was captured per screen
   (28 golden display lists in `dj-booth/tests/golden/`); the rebuild is diffed against those, and
   against screenshots of the prototype in the same state, using a Studio-only demo fixture that
   seeds the prototype's mock data.

## Consequences

- The booth can ship to any place without the kit; the kit's music panel is untouched.
- Four Wally packages and the Blink CLI become dependencies; they are pinned in `wally.toml` and
  `rokit.toml`.
- Booth data is one document: every edit rewrites it (debounced). Fine for a few hundred tracks;
  past ~3 MB the library would have to split into its own key.
- A Studio DataStore without API access falls back to memory with a warning.
- The prototype scripts stay in `docs/plans/dj-panel-experiment/` as the visual reference.
