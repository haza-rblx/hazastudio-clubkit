# ADR 0019 — Event cards: countdown posts linked to Roblox Events, check-in days, reminders, Daily Quest addon retired

Status: Accepted, 2026-10-07 — designed with the owner in playtest mocks, built the same day; kit + VPS unreleased

## Context

ADR 0015 shipped the event board with four card templates and a six-square streak strip. In a
playtest design session (2026-10-07) the owner redesigned the cards (one header + body shape for
every card), asked for an attendance-style calendar for streak quests, a dedicated countdown card
for upcoming events with a "Notify me", and in-game reminders in the bottom-right corner while
playing. Three parts of that are hard to reverse:

- a countdown needs data the VPS did not have (start/end time, a link to something that can notify);
- an attendance calendar needs to know **which** days a player checked in, but progress stored only
  a counter and the last day (with one skipped day forgiven, the days cannot be recovered from it);
- the Daily Quest addon (`1000-02-DQ-ADDON`) was a second, config-driven streak-quest system with
  its own panel — the panel the redesign started from.

Roblox Experience Events (Creator Hub) can be reached from inside the game:
`SocialService:PromptRsvpToEventAsync(eventId)` shows Roblox's own RSVP prompt, and Roblox notifies
RSVP'd players itself, also outside the game. A kit cannot push a notification outside the game any
other way.

## Decision

1. **Venue posts get a kind**: `announcement` | `countdown` (VPS migration `0028`: `kind`,
   `starts_at`, `ends_at`, `roblox_event_id`). A countdown has a WIB start, an optional end (default
   start + 2 h) and an optional **Roblox Event ID**. Before the start the card counts down; between
   start and end it is LIVE; after the end it is gone (API and kit both filter; the server pushes a
   state at each boundary).
2. **Notify me is Roblox's RSVP**, shown only when the post links an Experience Event and only
   before the start (the prompt errors afterwards). The kit stores nothing for it.
3. **Streak progress stores its check-in days** — an additive `days` list on the venue quest
   progress entry (same DataStore key, `VenueQuestProgress_v1`), bounded to 100 entries, unioned on
   merge. Entries written before it are reconstructed as consecutive days back from `lastDay`
   (owner's choice: never an empty calendar, may be off by a forgiven skip).
4. **One card shape** (header row + body row) for the Event tab, the quest popup and the reminders;
   templates in the GUI design file (RBXM surface), code only fills them.
5. **Streak check-in moves to the quest popup** (`18-EventQuestPopup`); the tab card shows this
   week only and links to it. The popup opens itself once per session when a streak quest waits.
6. **Reminders** (`19-EventReminders`) for the join post, unseen countdowns on join, and posts that
   appear while the player is online — once per player per post (`seenPosts`). Not for the whole
   unseen backlog on a first join (existing players' `seenPosts` only ever held join posts).
7. **The Daily Quest addon is removed** before it was ever released: code, `ClubKitConfig.DailyQuest`,
   `Features.DailyQuest`. Its best parts (auto-open, check-in flight) live on in the quest popup.
   `Overhead_v1.dailyQuest` stays readable and is never written.

## Consequences

- A release ships on three surfaces at once: engine (source sync), GUI (RBXM: new EventTab
  templates + two ScreenGuis), VPS (migration + API before the dashboard — an old API would save a
  countdown as an announcement).
- Every venue's board revision changes once after the API deploy (new fields): one full pull each.
- A place without the new ScreenGuis keeps the tab working; it just has no popup (no check-in!) and
  no reminders — the streak card's button then opens nothing. Install the GUI with the engine.
- Long quest windows draw at most six weeks around today (`calendar` clips, no START/FINISH on a
  clipped edge).
- RSVP depends on the owner creating the event in Creator Hub and pasting its id; without it the
  countdown still runs, with no button before the start.
