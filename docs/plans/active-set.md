# Active set — implementation contract (2026-10-16)

Owner request: "Add set" fails on big playlists (800 tracks), and a set should show as one card in the
queue instead of hundreds of rows. Designed live in the PARKLAB playtest (Set card + Full set sheet).

## Why the old path fails

`LibraryView.requestSet` sends every track id through transport `request_many`. Any payload over
`Config.Security.MAX_PAYLOAD_BYTES` (1024) is dropped by `validatePayload` in `MusicController` **without a
reply**, so the client times out. 800 ids ≈ 10–31 KB; only ~23–70 ids fit.

## Decisions (owner-approved design; defaults marked *default* were not argued and can change)

- An **Active set** is a server-side *source*, not queue content. The client sends a **source reference**
  (never track ids); the server resolves it to an ordered list (cap `Config.Music.SET_MAX_TRACKS = 1500`),
  optionally shuffled, plus a cursor.
- ~~One active set per server; starting a set replaces the current one.~~ **Superseded 2026-10-16 by
  "Queued sets" below.**
- ~~Interleave (`SET_INTERLEAVE = 1`).~~ **Retired 2026-10-16:** a set plays to the end once it is active.
  With no set, the queue behaves exactly as before (auto buffer only when neither a set nor requests exist).

## Queued sets (owner-approved 2026-10-16, PARKLAB playtest)

Owner: "set A, then a request, then set B" must be possible; a second "Add set" must not overwrite the
running set's card.

- **A set is a queue item.** `set_start` appends a **set card entry** at the end of the queue, after the
  requests already waiting (so it lands below them). The queue can mix freely: set, song, set, set.
- **Activation:** when a set card reaches the front of the queue it becomes the **active set** (the big
  Set card). If nothing is playing, `set_start` activates it at once.
- **Plays to the end:** while a set is active its next track is always at the front of the queue
  (insert index 1), so everything behind it waits until the set finishes. Requests added meanwhile go to
  the end of the queue as usual. `SET_INTERLEAVE` is removed from engine `Config.luau` (it was never in
  buyer config, so nothing to retire there).
- **Limit `Config.Music.SET_QUEUE_MAX = 3`**, counting the active set plus waiting set cards. Over the
  limit `set_start` replies `set_queue_full`.
- **Waiting set card actions: remove only** (existing transport `remove` with its `entryId`; control
  holders, or the starter as owner). Shuffle / View full set / Remove set appear once it is active.
- **Waiting set look:** a waiting set card is drawn as only the banner of the Set card ("UP NEXT SET",
  title, starter, track count, remove), not as a track row or a Library playlist row. The banner colour
  is the set playlist's cover colour; with no playlist (Liked Tracks / New Drops) or no colour it is the
  player's accent. The active set keeps the full Set card.
- **Clear Queue** removes requests **and** waiting set cards; the active set keeps playing.
- **No repeat on activation:** when a set activates, leading items equal to the track that just played
  are skipped (the set started while its first song was already on air played it twice).
- `set_stop` / `set_reshuffle` / `set_page` act on the active set only (unchanged).
- Who: **start / stop / reshuffle = `musicControl` holders** (same gate as today's `request_many`).
  *default:* **viewing the remaining set (pages) = everyone.**
- *default:* the set **keeps playing when its starter leaves** (it is the venue's set, not the player's).
- Private playlists: only `musicControl` holders can start a set from a private playlist (they are the only
  ones who can open it).
- State is **in memory per server**. No DataStore key, no buyer-owned file.
- The server **always replies** to a set action, including rejections, and `validatePayload` must reply
  `payload_too_large` instead of dropping silently (all transport actions benefit).

## Server ↔ client contract

### Transport actions (existing transport remote / `_sendTransport` path)

| action | payload | gate | reply |
|---|---|---|---|
| `set_start` | `{ source = { kind = "playlist" \| "favorites" \| "new_drops", id = string? }, shuffle = boolean }` | musicControl | `{ ok, reason?, total? }` |
| `set_stop` | `{}` | musicControl | `{ ok, reason? }` |
| `set_reshuffle` | `{}` | musicControl | `{ ok, reason? }` |
| `set_page` | `{ offset = number (0-based, into the REMAINING order), limit = number ≤ SET_PAGE_SIZE, query = string? }` | **everyone**, own rate limit 10 / 10 s | `{ ok, reason?, offset, total, tracks = { {id, name, creator, totalDuration}... } }` |

`favorites` resolves the requesting player's favourites; `new_drops` the existing New Drops list.
`query` filters the remaining tracks by name/creator (case-insensitive substring) before paging.

### Queue update payload (`buildQueueUpdatePayload`) gains

```
activeSet = nil | {
  id = string,              -- changes on every start/reshuffle
  title = string,           -- playlist name / "Liked Tracks" / "New Drops"
  sourceKind = string,
  starterUserId = number, starterName = string,
  played = number,          -- set tracks already consumed (incl. the one on air, if from the set)
  total = number,
  shuffle = boolean,
  upNext = { {id, name, creator, totalDuration} x ≤3 },
}
```

Set tracks that the server materialises into the queue for playback carry `fromSet = true` on the queue
entry; the client does **not** draw those as normal queue rows (the Set card represents them).

Waiting set cards appear in `queue` at their position as
`{ setCard = true, queueEntryId, setId, name = title, creator = "Set · N tracks", total, sourceKind,
requesterUserId = starterUserId, requesterDisplayName = starterName, playlistId = sourceId? }` and are
drawn as a normal queue row (cover from the playlist, "Queued by : starter", remove button).

### Config keys (engine `Config.luau`, Music section — not buyer config)

`SET_MAX_TRACKS = 1500`, `SET_QUEUE_MAX = 3`, `SET_PAGE_SIZE = 50`, `SET_PAGE_RATE = { count = 10, window = 10 }`.

## Client

- **Library**: "Add this sets to queue" → `set_start` with the opened playlist's source and `shuffle=false`;
  "Shuffle play from this sets" keeps its current behaviour unless it also queued all ids — then it becomes
  `set_start` with `shuffle=true`.
- **Set card** (queue, top of the list, above the virtual rows): banner in the playlist accent colour with
  kicker "NOW RUNNING A SET", 2-line title (size 20, ends in "…"), shuffle + trash buttons (trash
  `rbxassetid://78255461602603`, control only), "Started by <avatar> name", counter `played / total`,
  progress bar; then "UP NEXT FROM SET" with 3 rows (number, title, duration only) and a "View full set"
  button. Card bg 22, no stroke, no gradient, corners 12.
- **Full set sheet**: own ScreenGui overlay; the music MainWrapper scales to 0.94 behind it (UIScale) with
  a dim at 0.35; the sheet opens with one tween `TweenInfo(0.32, Sine, InOut)`, slides 60 px, sits 52 px
  lower, hidden until positioned (no first-frame flash). Layout: 6 px gutter, corners 20 / 16 / 12 / round.
  Left column 280 px in the accent colour: Back, title (26), Started by, `x / total`, songs left, progress,
  Reshuffle + Remove set (control only). Right card (bg 18): "UP NEXT FROM SET", search box, virtual list.
  Rows 49 tall at a 52 pitch, bg 27 (alt 38), number column as wide as the widest number, centred,
  title gap 12, duration on the right. Pages of 50 via `set_page`, skeleton rows while a page loads.
  Scrollbar = kit `Client/UI/OverlayScrollbar.attach(scroll, sheet)` with the native bar hidden.
- Everything is **built from code** (no GUI template needed), so it ships by source sync.
