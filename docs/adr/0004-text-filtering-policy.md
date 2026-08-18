# ADR 0004 — Text Filtering Policy (Roblox ToS Compliance)

**Status:** Accepted
**Date:** 2026-08-18

## Context

A deep audit (3 parallel explore agents + manual verification) mapped every text surface in the kit against Roblox's requirement that **all user-generated text displayed to other players must be filtered server-side via `TextService`** (correct author context). Most surfaces were already filtered, but the audit found 6 gaps and 8 duplicated inline filter implementations:

- **G1** `/status` free text rendered on the overhead billboard above heads with zero filtering (`ProfileCommandService` stored raw).
- **G2** Bio/status re-filter used the *viewer's* userId as author (`AvatarContextService._filterText`) — wrong age context.
- **G3** External provider nicknames (Saweria/Bagibagi — typed on an external payment platform, NOT Roblox-moderated) reached workspace leaderboard boards unfiltered for unlinked donors.
- **G4** Music manage track/playlist names + creators (admin/DJ client input) stored and shown to all players unfiltered.
- **G5** Robux donation name fell back to the RAW string on filter failure.
- **G6** `communityName` from the buyer's worker API was truncate-only sanitized onto the community board.

## Decision

1. **One canonical module.** All filtering goes through `Shared/Utils/TextFilterUtil.luau` (`filterForBroadcast`, `filterForUser`, `normalize`, `hashFallback`). The 8 inline implementations were migrated; no new inline `pcall(TextService...)` may be added.
2. **Filter at write, not just at read.** Free text that is stored (`statusText`, `bio`, music names/creators, `communityName`) is filtered **before** DataStore write. Per-viewer re-filter (ACM popup) stays for stored text shown to a specific viewer — with the **author's** userId (`filterForUser`), fixing G2.
3. **External text is player text.** Strings originating outside Roblox moderation (provider nicknames, worker `communityName`) are filtered before display/storage. Author context: linked donor userId when known, else `game.CreatorId` (the place owner publishes it). Filter failure → `#`-hash fallback, **never** the raw string (G3, G5, G6).
4. **D1 — DisplayNames are NOT re-filtered.** Roblox `DisplayName`/`Username` are platform-moderated at source. Re-filtering every payload would burn TextService quota and add latency for no compliance gain. This is the accepted industry-standard reading.
5. **Native chat stays native.** Chat decorations (role tags, colors) only mutate `PrefixText`/metadata; the message body never leaves Roblox chat filtering.
6. **Sign tools stay single-attempt** (`retries = 1`) — a retry loop would multiply the TextService quota a spamming client can burn.

## Consequences

- The full audit tables (filtered surfaces, entry points, display surfaces) live in the 2.6.7 release notes summary; `TextFilterUtil` is the single grep target for future audits.
- `setStatus`/`setBio`/music-manage now yield (TextService is a web call). All call sites (remote handlers, chat commands) already run in yieldable contexts.
- Unlinked external donors whose name fails filtering show a `####` mask on boards — cosmetic tradeoff accepted over leaking raw external text.
- New features that display free text must: filter via `TextFilterUtil` at write (and per-viewer for stored text), and add the surface to this ADR's audit list in the release notes.
