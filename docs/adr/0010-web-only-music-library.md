# ADR 0010 — The music library moves to the web; the game becomes a reader

**Status:** Accepted — implementation staged (2.13 opt-in, 3.0 default)
**Date:** 2026-09-13

## Context

Three things write the shared music library, and they all write the same two JSON blobs in `MusicLibrary_v1`:

1. `ReplicatedStorage/Hazastudio_ClubKitConfig/MusicCatalog.luau` — the buyer's seed script, merged additively at boot by `MusicCatalogSeeder`.
2. The in-game **Manage** tab (tab 4 of `06-MusicPlayerGUI`), via `MusicManagePlaylist` / `MusicManageTrack`.
3. **BRM** — a separate service, from outside the game entirely: it writes the buyer's DataStore with the buyer's own Open Cloud API key. No BRM code exists in this repo.

Convergence between them is last-writer-wins on `syncRevision` inside `UpdateAsync`, plus a 30-second re-read poll (`Config.Music.SYNC_POLL_INTERVAL`). That handles two Roblox servers editing at once. It does not handle the three failure modes that actually bite:

- **BRM's sync rewrites the whole entry.** An edit made in the Manage tab between two syncs is gone, silently, with no conflict shown to anyone.
- **Track duration is guessed.** A new track carries `totalDuration = 0`; the server has no way to ask Roblox how long an audio asset is, so it waits for the first client to measure and report back over `MusicDurationReport`, and until then runs a blind `AUTO_ADVANCE_UNKNOWN_DURATION_SECONDS = 180` timer. A three-minute song is cut; a forty-second song leaves 140 seconds of silence. The web already knows the duration at processing time.
- **Roblox revokes audio long after approval** and tells nobody; the music simply stops. BRM can ask (`refreshAvailability`); the game cannot.

Separately, the Open Cloud API key is the wall: BRM needs one to upload, so `games.music_enabled` has been 0 for every buyer except `thebasic` since the flag was added. Venue owners who are not developers stop at "create an API key in Creator Hub".

Alternatives for the transport:

- **(A) Keep the push.** BRM keeps writing the buyer's DataStore over Open Cloud; the game reads its own DataStore as today. Zero kit change — but every buyer still needs a key, so the wall stays exactly where it is.
- **(B) The game pulls.** The kit fetches the library from `api.hazastudio.id` using the game secret it already holds for the license gate, and writes what it got into `MusicLibrary_v1` as a cache.
- **(C) Both.**

One more was considered and rejected: Hazastudio uploads all audio under its own account and grants each buyer's universe access. That removes the key even for uploads, but concentrates every venue's music on one account — a single moderation or DMCA action would stop the music in every venue at once, and moves the legal exposure onto the vendor.

OAuth was investigated as a way to drop the key. The scopes check out (`asset:read` + `asset:write` cover the Assets API, which handles audio and images alike; the `universe*` scopes that DataStore would need are buggy in OAuth and unavailable — a problem (A) would have hit and (B) does not). It was still rejected for v1 on reliability: third-party OAuth is Beta and carries a live scope bug, while API keys are GA and static. The UX gain is also thinner than it first looks — only buyers who *upload* ever meet the key, and those are the paying, more technical ones.

## Decision

**One writer, two readers.** The web (brm-api) is the only place the library is edited. The game reads.

**Transport is (B) with a cache.** The kit fetches at boot and polls, then writes the result to `MusicLibrary_v1`. If the VPS is unreachable it boots from that cache. This is the point of choosing (B) over (A): the DataStore stops being the single source and becomes the fallback, so the two sources are redundant rather than serial. It also means no Open Cloud key is needed to *read* a library — only to upload new audio.

**Live control stays in the game.** DJ mode, effects, playback speed, the soundboard and admin skip are runtime, not configuration; moving them to a browser would mean a DJ alt-tabbing mid-event. Today they share one gate with library editing (`MusicService.isManageAllowed`), so the privilege splits in two:

- `musicManage` — editing the library. Leaves the game entirely; becomes a web permission.
- `musicControl` — live control. Stays, held by the DJ role.

**The commercial line follows the technical one.** A track that points at an existing Roblox audio asset needs no key and no server work, so managing the library — playlists, tracks by asset ID, DJs, covers — is free for every buyer. Uploading audio or importing from YouTube needs the buyer's Open Cloud key and costs VPS transcode time, so that stays the paid add-on.

**Player-facing behaviour does not move.** Song requests (including request-by-asset-ID) and the queue stay in the game and stay in memory, exactly as `MusicReadOnlyLibrary` already behaves; favourites stay in `MusicFavorites_v1`, because they are player data, not venue configuration.

**DJ is its own entity.** It is not the `Creator` of the live-status feature (ADR-less, see CONTEXT.md) — a track's DJ may be an outside artist who is not a player at all.

**Rollout is staged.** `ClubKitConfig.Features.MusicWebLibrary` (default `false`) selects the new source in 2.13; existing behaviour is untouched until a buyer opts in. The default flips in 3.0, and only then are the Manage tab, `MusicCatalogSeeder` and `MusicCatalog.luau` deleted.

## Consequences

- **`Config.Music.PLAYBACK_SPEED = 0.625` is a BRM-era assumption, and it is now a trap.** That number exists to undo the pitch shift BRM applies when evading Roblox's audio matching. A per-track `playbackSpeed` of `nil` falls back to it — which was right when every track came through BRM, and is wrong the moment a buyer pastes an ordinary asset ID: the song plays slowed. Tracks created by asset ID must store `1.0` **explicitly**; never `nil`. Do not "fix" this by changing the global default, which would re-pitch every existing BRM track in every venue.
- The kit gains an outbound HTTP dependency for music. It rides the pipe `LicenseService` already opens, so it is a new route rather than new infrastructure — but the cache is not optional. A build that fetches without writing the cache turns the VPS into a single point of failure for music in every venue at once, which is strictly worse than today.
- `musicManage` lives in `ClubKitConfig.RoleCategories`, a buyer-owned file (ADR 0001). Splitting it means a new key through schema + template + fill-forward, and the fill-forward rule must inherit `musicControl` from the old `musicManage` value — otherwise every venue's DJs lose their controls on update, in silence.
- **The register-budget win only arrives in 3.0.** `MusicPlayerUIBinder.luau` sits at 158 top-level locals against a ~200 ceiling (ADR 0002) and the Manage tab is a large part of it, but 2.13 *adds* code (the provider, the second gate) because the local mode must keep working. Do not sell 2.13 as the slimming release.
- Deleting Manage is not deleting a file. It is woven through `MusicPlayerUIBinderPart2` (~140 references), `MusicPlayerUIBinder` (~56), `MusicPlayerController` (~78) and `MusicController` (~35).
- Buyers with an existing DataStore library need a one-time import. The chosen path is an export from the game on first boot under the new flag, accepted by the VPS only while that game's web library is still empty — so no buyer needs an Open Cloud key merely to migrate.
- `MusicDurationReport` stays. Web-sourced tracks arrive with a known duration, but a free-tier track pasted as a bare asset ID does not, so the client-measures-and-reports path remains the fallback for exactly that case.
- Music must not be collateral damage of the licence kill switch. `maintenance_until` expiry already blanks `/v2/*`; the music route returning 403 has to be treated by the kit as "unreachable" and fall through to cache, not as "empty library".

## Addendum — 2026-09-13: publishing is automatic, with no draft stage

Until the pull transport exists, the customer area still reaches the game by the old push: brm-api writes the game's `MusicLibrary_v1` with the customer's Open Cloud key. That push used to be a button ("Sync ke Roblox", later "Kirim ke game"). The button was not a decision — nobody edits a playlist and then chooses to keep the old one playing — so what it reliably produced was the failure of forgetting to press it, discovered as silence in the venue.

**Decision (owner):** publishing is automatic and there is no draft stage. Every edit reaches the game on its own; there is no per-playlist "not yet" switch.

**Mechanism.** Library writes mark the `(user, universe)` pair dirty (`src/roblox/library-dirty.ts`); a flusher in brm-api (`src/roblox/auto-sync.ts`) pushes due pairs every ~4 s, one flush at a time. When and whether to push is decided by a pure, tested state module (`src/roblox/autosync-state.ts`):
- **A failed push stays queued.** An earlier draft took entries off the queue before pushing and dropped them on failure, which lost the publish silently until the customer's next edit.
- **Every mark bumps a generation**, and a push clears the entry only if no newer edit arrived while it was in flight — otherwise an edit made mid-push would be swallowed by that push succeeding.
- **Failures are classified.** `ROBLOX_CLOUD_NOT_CONFIGURED` is the free tier: nothing queued, nothing logged. Roblox answering 401/403 means the key is refused: retried every 5 minutes, so replacing the key resumes publishing without an edit. Everything else (429, 5xx, timeouts, network) backs off from 4 s doubling to a 5-minute cap. Editing during a backoff does not bring the retry forward.
- **The customer area reads the push's real status** from `GET /roblox/club-kit/library/autosync` (pending, last pushed, retry time, error kind and HTTP status — Roblox's own error text stays in the server log) instead of inferring it from playlist `lastSyncedAt`, which does not move for an edit that only touches a track. The manual push route settles the queue too. Marks come from the explicit write paths only — playlist save/update/delete, library item patch/delete, upload completion, and the manual asset-id routes. The sync's own write-back paths (`upsertLibraryItemFromSync`, `upsertPlaylistFromSync`) never mark, which is what stops the flusher chasing its own tail.

**Alternatives considered:** a per-playlist toggle as a draft stage (so a set can be built during a live event without going on air), and keeping the manual button with a clearer status. Both rejected by the owner in favour of the simplest model.

**Consequences:**
- There is no safety net for editing during an event: a change is on air within seconds. That is the accepted cost of the simpler model.
- `playlists.sync_enabled` is a **dead column**. It is stored, defaults to 1 and is returned to clients, but `club-kit-sync.ts` never reads it. It is not a draft mechanism and must not be presented as one. If a draft stage is ever wanted, that column is where it would start — but it does nothing today.
- The push still needs the customer's key, so the free tier still cannot publish: the flusher quietly skips libraries with no Open Cloud profile. Automatic publishing fixes forgetting, not the free tier. Only the pull transport above does that.
- The dirty set is in memory. A restart loses at most the few seconds between an edit and the next flush; the next edit marks it again. Persisting it would be a second source of truth about what the game has.
- Everything in this addendum is interim. When the kit pulls, the flusher and the dirty set are deleted; the customer-area status copy ("perubahan langsung dikirim ke game") stays true and does not change.
