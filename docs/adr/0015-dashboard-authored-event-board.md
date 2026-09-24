# ADR 0015 — Dashboard-authored event board (venue posts and venue quests)

Status: Accepted, 2026-09-24 — built and playtested on THE BASIC TEST; API + dashboard live, kit unreleased

## Context

The owner designed an `EventTab` for the menu (07-MenuGUI) with four card templates — a text
announcement, an image announcement, a quest with a progress bar, and a streak quest with day
squares — plus a popup (`PopUpMenuTemplate`). The requirement: announcements and quests are
**configured in the customer dashboard**, not in Studio, like the music library (ADR 0010) and the
track covers (ADR 0014).

The kit already has a quest-like feature, the Daily Quest addon, configured in `ClubKitConfig` with
its own panel; and "announcement" already names `/announce` and paid broadcast. Nothing on the VPS
stores announcements, events or quests.

## Decision

1. **Authored on the web, pulled by the game.** The clubkit API stores venue posts and venue
   quests per game; the dashboard gets a page **Event** (tabs Posts / Quests, card previews). The
   game pulls one "event board" document from a v3 route with a revision/ETag, polls about every
   60 s with back-off, and keeps the last good copy in a DataStore cache, so a VPS outage never
   empties the board (the MusicLibraryProvider pattern).
2. **Posts:** category, title, body, published date, optional Roblox image asset id pasted by the
   customer (no upload, no moderation surface), at most one "show on join" post shown once per
   player. Card button → post popup; popup button → close.
3. **Quests:** goal ∈ {level ≥ N, streak check-ins N days, Robux donated since start, play time
   since start}; reward ∈ {membership tier (permanent, skipped if held), custom title (only if none),
   XP}; WIB start/due dates; hidden after the due date; description auto-filled by the dashboard and
   editable; claim by button, verified on the server; completion announced server-wide.
4. **Per-player progress lives under a new DataStore key** (`VenueQuestProgress_v1`, one document
   per player: per-quest progress, check-in days, claimed-at, and the ids of join posts already
   seen). Not on `Overhead_v1`: play-time and donation counters change often, and the overhead
   document is already the hottest write in the kit.
5. **The Daily Quest addon is superseded**, not removed: it keeps working where installed; new
   venues use the streak venue quest.
6. **Ships to all buyers**, starting on THE BASIC TEST. Code by source sync; the `EventTab`, its tab
   buttons and the popup by RBXM. A place without `EventTab` keeps the "coming soon" rows.

## Consequences

- One new versioned DataStore key (additive; no migration). Losing it resets quest progress and
  claims, not memberships or titles already granted.
- Quest rewards are granted by the game from web data, so a compromised owner account can hand out
  memberships in that venue. The same owner can already do this with `/givemembership`; the claim
  is still checked against the player's real progress on the server.
- "Robux donated since start" needs a hook in the Robux donation receipt path; "play time" needs a
  server-side online-time accumulator with buffered writes.
- The menu's two hard-coded tabs become a list with an optional third tab.
- Two notions of streak coexist: `streakDays` (automatic on join, drives the Streak board) and a
  quest's check-in count (manual, per quest).
