# DJ booth as a standalone product — what the kit server already backs (2026-10-17)

Research for the admin tabs: Library/Upload, Sets, Access, Log, Settings. Paths are under `src/`.

| Tab | Already on the server | Needs new server work |
|---|---|---|
| Library / Upload | Web library is the source of truth (`MusicLibraryProvider` `/v3/music/library`, DataStore cache `MusicLibrary_v1`); asset probe + validator; duration reports | No in-game create/edit/delete. `MusicRepository` save/delete exist but are unreachable in web mode → VPS write endpoints or a new design |
| Playlists & Sets | Playlist/track schema; sets (`MusicActiveSet`): create/start/stop/reshuffle/page via `MusicTransport set_*`, `SET_QUEUE_MAX` 3 | Sets live in session memory only (no persistence), no scheduling, no playlist edit from the booth |
| Access | `musicControl` / `musicManage` role mapping (`PermissionDomain`, ClubKitConfig role categories), `/setrole` `/unsetrole` (persisted in `Overhead_v1.giftedRole`), admin override | No DJ-facing grant UI/remote; no booth-scoped permission without a group rank |
| Log | Console `log:info` only; in-memory `playedHistory` (for "previous") | Event sink (queue, skip, request, DJ mode, effects, roles) + storage + read remote |
| Settings | Buyer keys `Music.PlayOnceRequest`, `Music.MaxVolume`; per-player volume (`Settings_v1`) | Runtime settings store + remote + validation (vote threshold 0.75 / 15 s, request caps, play-once limits, MaxVolume are hard-coded in `Config.luau`) |
| Requests / votes (moderation) | Request rules (`dj_only`, duplicates, 3/user), play-once policy, vote skip, admin skip, queue remove/clear | Per-player block/mute, request history, moderator audit trail |

Also open from Phase 4 research: SFX broadcast (kit soundboard is local-only, soundIds empty), room
gain (no server-owned volume), FILTER (no low/high-pass on `Sound`), BPM (no field anywhere),
`setDjEffect` has no id whitelist / value clamp.
