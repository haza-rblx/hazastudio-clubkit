# Event cards, reminders, countdown posts, attendance calendar — 2026-10-07

Owner-approved design (grill round 1–3, 2026-10-07). Glossary in `CONTEXT.md` → *Event board* (Countdown post, Event card, Reminder, Attendance calendar, Quest popup). ADR 0019 records the hard-to-reverse parts.

## Decisions

- Streak quest detail = **quest popup** (wide, two columns: info + check-in left, attendance calendar right). Opened from the Event tab card ("Lihat detail"), from a reminder, and once per session on its own after gameplay-ready when a streak quest is not checked in today.
- The **Daily Quest addon** (`1000-02-DQ-ADDON`, `Features.DailyQuest`, `ClubKitConfig.DailyQuest`, `DailyQuestService`, `DailyQuestUI`) was never released → removed. `Overhead_v1.dailyQuest` stays readable, never written.
- Venue posts get a **kind**: `announcement` | `countdown`. Countdown = start time (WIB in the dashboard), optional end (default start + 2 h), optional **Roblox Event ID** (Creator Hub Experience Event). Before start: D/H/M/S tiles; between start and end: LIVE; after end: hidden. "Notify me" only when an event id is set → `SocialService:PromptRsvpToEventAsync` (client).
- Streak quest progress stores the **check-in days**; legacy entries reconstruct consecutive days back from `lastDay`.
- **Reminders** (bottom-right): show-on-join post on join, plus posts that appear on the board while the player is online, once per player per post (`seenPosts`). Line timer 8 s, pause on hover, max 3 stacked, extras queue "+N". Hidden while the menu is open. Image posts → small thumbnail.
- Card templates live in the GUI design file (RBXM surface); code only fills them.

## Wire contract — VPS `GET /game/:key/v3/event-board` (Agent A owns the VPS side)

Each `posts[i]` gains (old fields unchanged):

| field | type | notes |
|---|---|---|
| `kind` | `"announcement"` \| `"countdown"` | missing → `"announcement"` (old API) |
| `startsAt` | number \| null | unix seconds, countdown only |
| `endsAt` | number \| null | unix seconds, countdown only; API fills start + 7200 when the owner left it empty |
| `robloxEventId` | string | digits only, `""` = none |

The API may drop countdown posts whose `endsAt` is in the past; the kit filters them too.

## Kit domain contract — `EventBoardDomain` (Agent B owns)

- `Post` gains `kind: string`, `startsAt: number?`, `endsAt: number?`, `robloxEventId: string`. `serializeBoard` round-trips them.
- `EventBoardDomain.postPhase(post, nowUnix): "none" | "upcoming" | "live" | "ended"` — `"none"` for announcements.
- `EventBoardDomain.visiblePosts(board, nowUnix): { Post }` — board posts minus ended countdowns.
- `QuestProgress.days: { number }?` — sorted ascending, unique WIB day numbers, at most `DailyQuestDomain.MAX_TARGET_DAYS` entries (oldest dropped). `checkIn` appends today; a reset keeps earlier days (the calendar shows every check-in in the window; the chain shows runs). `sanitizeProgress` validates, `mergeProgress` unions + bounds.
- `EventBoardDomain.checkInDays(quest, entry?): { number }` — `entry.days` when present, else legacy reconstruction `lastDay - progress + 1 .. lastDay` clamped to `>= quest.startDay` (empty when progress or lastDay is 0).
- `EventBoardDomain.calendar(quest, doc, today)` →
  ```
  {
    leadBlanks: number,          -- weekday of quest.startDay, Sunday = 0 ((day + 4) % 7)
    cells: { { day: number, dom: number, month: number, year: number,
               state: "done" | "today" | "missed" | "upcoming" } },  -- startDay..dueDay
    todayIndex: number?,         -- index into cells, nil when today is outside the window
  }
  ```
  `done` = in checkInDays; `today` = today and not done; `missed` = before today and not done; `upcoming` = after today.

## Server state contract — `EventBoardController.buildState` (Agent B owns)

- `posts` = `visiblePosts(board, now)`, each with `kind`, `startsAt`, `endsAt`, `robloxEventId` added.
- `unseenPostIds: { number }` — visible posts not in `seenPosts` (bounded by the board's 50).
- `joinPostId` unchanged.
- Streak quests: `calendar = EventBoardDomain.calendar(...)` replaces `strip` (unreleased, no compat needed). `startDate` added next to `dueDate`.

## Client (main session owns)

- `EventTabUI`: event-card templates; countdown card (tiles, LIVE, Notify me = RSVP); streak card shows this week's calendar row + "Lihat detail"; no check-in button in the tab.
- Quest popup (replaces `DailyQuestUI`), reminder controller, removal of the client half of the addon.
- Zoom/pop animations scale from the centre (layout children get a slot) — see memory rule; no emoji, icon placeholders.

## Release surface

Engine code → source sync. GUI templates (`07-MenuGUI` EventTab cards, quest popup ScreenGui, reminder ScreenGui) → RBXM/manual. VPS → migration `0028` + API + dashboard deploy (owner go-ahead for restart).
