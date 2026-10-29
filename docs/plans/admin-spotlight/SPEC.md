# Admin Spotlight: spec

Approved in the Experiment Area playtest on 2026-10-18. It replaces the Admin Hub UI (`04-AdminHub`).
The Admin Hub template GUI stays in buyer places but is no longer bound. The panel is built in code,
so it needs no template.

## Decisions

- **Rollout.** Spotlight replaces the Admin Hub. The `Features.AdminHub` /
  `FeatureFlags.AdminHubEnabled` flag still gates it, and there is no new buyer flag.
- **Actions.** `AdminHubController` keeps all its business logic: gates, role catalog, gift tiers,
  donate flows, and command strings run through `CommandLibraryService`. Only the UI module is
  swapped. `AdminSpotlightUI` exposes the same public API as `AdminHubUI`, and
  `usesActionTemplate()` always returns false, so the controller takes its code-built path.
- **Edit stats.** These use the new RemoteFunctions `AdminGetStats` and `AdminSetStats`
  (`Config.Admin.REMOTE_GET_STATS` / `REMOTE_SET_STATS`).
- **Title.** Phase 2 adds a new Spotlight modal that posts to the existing title remotes. In phase 1
  the Title tile keeps opening the v3 editor.
- **Blur.** There is no camera blur. `Config.PanelBlur` stays off.

## Visual tokens

These come from the 07-MenuGUI Preferences panel and the 15-TopMenuGUI Section1 buttons.

| Token | Value |
|---|---|
| Font | `rbxassetid://12187365364` (SemiBold, Bold, Medium, Heavy) |
| Item fill (main list, search, pills, label chips) | `#070707`, solid |
| Item hover / keyboard highlight | `#1a1a1a` |
| Modal background | `#0b0b0b`, radius 28, no stroke |
| Modal row fill | `#161616` |
| Modal control fill (stepper, segmented track, toggle off) | `#2a2a2a` |
| Muted text | `#8e8e8e` (modal), `#b1b1b1` (main list subtitles, label chips) |
| Selected state | white fill, black text |
| Row height | 54 in the main list (top-menu parity), 48 in modals (56 with a subtitle) |
| Icon disc | 38 at (8,8). Colour and `AccentDiscGradient` are cloned from the top-menu BroadcastButton disc. Icon is white, 24 |
| Text, main list | title 15 Bold white at x=54; subtitle 14 Medium `#b1b1b1` |
| Groups | rows 2px apart; outer radius is a full pill (main) or 18 (modal); inner radius 6 (main) or 4 (modal). Built from two clipped halves with a 1px overlap, so there is no seam |
| Chevron | music play icon `rbxassetid://75726391560105`, 12×12, `#8e8e8e`, not rotated |
| Scrollbar | `OverlayScrollbar.attach(listScroll, listScroll)`. The list width equals the row width, so the pill sits 6px off the rows |

All sizes are whole pixels. The panel has no root UIScale, because fractional sizes blur the text.

## Main panel ("Spotlight")

- **Wrapper.** The outer wrapper is fully transparent with no outline. Width 500. Every item floats.
- **Search.** A 54px pill with the search icon (`rbxassetid://72914550286274`), placeholder
  "Search players, actions or /commands", and a `/` key hint. The close button is a 36 circle to
  its right, using the hub close icon `rbxassetid://70796895792875`.
- **No target picker** on the main page.
- **Label chips** carry the section labels: 24 tall, `#070707` pill, 12 Bold `#b1b1b1`, 10px side
  padding. The sections are:
  - "Recent": the last 4 actions used, as a 2×2 grid of 54px pills with full radius, an icon disc
    and the title.
  - "Player actions": actions with `needsPlayer = true`.
  - "Server", with the right-side chip "Affects everyone": the rest.
- **Rows** show the icon disc, title, subtitle, and the command alias on the right in RobotoMono 12
  `#8e8e8e` (`/bring`). Actions that open a modal also get the chevron.
- **Search behaviour.**
  - Filters actions by title, subtitle and alias.
  - A query starting with `/` matches by alias prefix. `/bring sari` also pre-selects the player
    whose name or display name starts with "sari", which skips the picker.
  - Up/Down move the highlight, Enter runs the highlighted row, and `/` focuses the search.
  - With no match, show an empty state: "No results" plus "Try a player name or a command like
    /bring".
- **Toasts.** Instant actions show a white pill toast at the bottom of the panel (black text, 40
  tall, Back easing in, auto-hide after 2.6s).

## Modal (Apple Settings style)

- **Placement.** Centred, 400 wide, height follows the content, with 16 padding. A full-screen dim
  (black, transparency 0.45) sits behind it, and the Spotlight wrapper scales to 0.96.
- **Open and close.** Opening scales 0.92 → 1 with Quint Out over 0.4s. Closing scales to 0.9 with
  Cubic In over 0.2s.
- **Nav bar.** Height 56, or 64 with a subtitle. "Cancel" on the left (15 SemiBold, muted). The
  title is centred (16 Bold) with an optional 12 Medium subtitle. The primary action is on the
  right (15 Bold, white): Save, Send, Apply or Update.
- **Groups.** An optional caps header (12 Bold, muted, x=16), then rows, then an optional footnote
  (12 Medium, muted).
- **First group** is the target row for player actions: avatar 40, name 15 Bold, `@user` 12 Medium,
  and "Change" with a chevron. "Change" reopens the picker.
- **Controls.**
  - iOS stepper: a 94×32 pill split "−|+" by a divider, with the value to its left (15 SemiBold,
    muted).
  - Value field on the right of a row (a TextBox).
  - Toggle: 48×28 track, white when on with a black knob.
  - Segmented control: `#2a2a2a` track, sliding white thumb.
  - Check list: rows with a white 22 dot and a black 8 centre on the selected row.
- **Dismiss** with Esc, a tap on the dim, or Cancel.

## Player picker

A modal with the nav "Cancel · Choose Player · for <action>". It contains a search row and a group
headed "N IN SERVER", with one row per player: avatar 36, name (plus "(You)" for yourself), `@user`
and a chevron. Picking a player either runs an instant action at once, or swaps the modal to that
action's sheet.

## Stats contract

### `AdminGetStats`

RemoteFunction, called as `InvokeServer(targetUserId: number)`. It returns `nil` when the caller is
not allowed or the target is not in the server. Otherwise it returns:

```
{ level: number, xp: number, xpToNext: number?, streakDays: number,
  daily: { label: string?, progress: number, goal: number, completed: boolean }? }
```

### `AdminSetStats`

RemoteFunction, called as `InvokeServer(targetUserId: number, changes)`. It returns
`(ok: boolean, message: string)`. `changes` is a table where every field is optional:

```
{ level: number?, xp: number?, streakDays: number?, dailyProgress: number?, dailyCompleted: boolean? }
```

Server rules:
- The gate is `PermissionDomain.canUseAdminPanel`, rate-limited by `Config.Admin.RATE_MAX` and
  `RATE_WINDOW`.
- Values are clamped and integer-checked.
- Writes go through the existing services: LevelService, StreakService, and the daily quest owner.
  Overhead data is saved through the normal path.
- `/setlevel` and `/setstreak` get the same `canUseAdminPanel` gate.

### Edit Stats sheet

The sheet has the target row, then three groups:
- **Level:** a Level stepper and an XP field showing "340 / 1200", with the footnote "XP resets when
  the level changes."
- **Streak:** a "Days in a row" stepper.
- **Daily quest:** a Progress stepper showing "N of goal" and a Completed toggle, with the quest
  label as the footnote.

Save sends only the fields that changed.
