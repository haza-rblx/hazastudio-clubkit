# UI experiments: dance panel v3, avatar context menu, profile modal, queue island (2026-10-07)

Built live in a solo playtest of the Experiment Area place (75916114543452) and approved by the
owner step by step. **Nothing here is in the repo or the place yet.** This file is the exact spec
for making it permanent. All sizes are design pixels (before the GUI's UIScale) unless marked
"screen".

Tried and dropped the same day: ACM rebuilt as Frame with a fixed hero (A) or stacked cards (B),
and an edge fade instead of clipping. The owner rejected the flat scroll cut a Frame gives, so the
content wrapper stays a CanvasGroup.

## 1. Dance panel v3 (`IconGroup.DancePanelGUIWrapperv3.03-MainContentWrapper`)

Panel height is unchanged (420). The list gives up the room for the label row and the taller bar.

| Element | Before | After |
|---|---|---|
| Wrapper `UICorner` | 24 all round | **17 all round** (11 bar curve + 6 padding, concentric) |
| `SearchDanceorPose` corner | pill `(1,0)` | **11 px** (matches the speed bar) |
| `MainContent` (ScrollingFrame) | `Size (1,0,1,-84)`, centred (324 tall) | `AnchorPoint (0,0)`, `Position (0,0,0,42)`, `Size (1,0,1,-120)` = **288 tall** |
| `AdjustSpeedWrapper` height | 38 | **44** (its corner is set by `SegmentedSliderBar`, about 11.5 px) |

Measured stack (y from wrapper top): search 6–46, list 48–336, label 340–362, bar 370–414.

### Search bar (`SearchDanceorPose`, TextBox kept so `DancePanelGuiRefs` still finds it)

- `TextXAlignment = Left`, `ClearTextOnFocus = false`.
- Placeholder `"Search dance or pose"`. The old one has a double space, and the binder caches it in
  `_defaultSearchPlaceholder`.
- `UIPadding`: Left 38 (12 inset + 18 icon + 8 gap), Right 32 (10 inset + 14 clear + 8 gap).
- `Icon` ImageLabel:
  - 18×18, `rbxassetid://72914550286274` (the Admin Hub search glyph).
  - `AnchorPoint (0,0.5)`, `Position (0,-26,0.5,0)` (negative offset because the padding shifts children too).
  - Colour `#737373` when empty and unfocused, `#ffffff` when focused or holding text.
  - `_bindSearch` already spins the first ImageLabel child when the query is wiped.
- `ClearButton` ImageButton:
  - 14×14, `rbxassetid://135390345456797` (kit close glyph), colour `#9a9a9a`.
  - `AnchorPoint (1,0.5)`, `Position (1,22,0.5,0)`, `ZIndex` = box + 2.
  - Visible only while `Text ~= ""`. `Activated` sets `Text = ""`.

### Speed label row (new `SpeedLabel`)

- Clone of `07-MenuGUI…SettingsTab.Section.SectionContentWrapper.Slider.SliderLabel` (the owner's Preferences row).
- Placement: `AnchorPoint (0.5,1)`, `Size (0,208,0,22)`, `Position (0.5,0,1,-(44+8))`. `UIListLayout.VerticalAlignment = Center` (SpaceBetween is already set).
- `SectionTitle`: text `"Speed"`, TextSize 14.
- `SliderCurrentValue` sits inside a new `ValueChip` Frame:
  - bg `#030303`, `UICorner (1,0)`, `UIStroke #292929` 1 px Border.
  - `UIPadding` L/R 9, `AutomaticSize X`, height 22, LayoutOrder 1.
  - Text size 13.
- The chip shows the same text as `CustomSpeedField`. Set it in `_updateSpeedLabels` next to the
  field update that already exists there.
- Keep the existing segmented bar code (`SegmentedSliderBar.attach`, 0x/2x labels hidden).

## 2. Avatar context menu (`StarterGui.AvatarContextMenu`)

### Structure and scale

- **UIScale (desktop) 0.86 → 0.8.** It is baked into the GUI's `UIScale`.
- **All gaps 5.** 5 × 0.8 = exactly 4 screen px.
  - Any gap whose scaled value is fractional renders 3 or 4 px at random.
  - Measured at 0.86 / gap 4: 3,3,4,4,4,4,3.
  - Phone uses `Config.MobileScale.ACM_GUI = 0.68`, where 5 gives 3.4 px. Phone scale is still **open** (0.6 + gap 5 = 3 px, or 0.8).
- **`MainWrapper`: CanvasGroup → Frame, `AutomaticSize XY → Y`.**
  - The outer CanvasGroup clipped the UIShadow, and nothing uses its GroupTransparency.
  - `AvatarContextUI` already checks `IsA("CanvasGroup")`.
  - With XY, adding children that use scale sizes ballooned the width to 825.
- `02-MainContentWrapper` **stays a CanvasGroup**. It clips the rounded content.
- `MainContent.UIListLayout.Padding` 6 → 5.

### Look

- **Outline off** (`UIStroke.Enabled = false`): `02-MainContentWrapper`, `DraggableIcon`,
  `SocialProofSection.Connection`, `.Followers`, `RelationshipStatus`.
- **Surfaces stay black, only buttons and tiles take the accent.**
  - `AccentNoTint` also applies to every descendant, so the opt-out lives on an empty child.
  - Surfaces: `02-MainContentWrapper`, `01-DraggableFrame.DraggableIcon`, `MainContent.Separator`, `LoadingScreen`.
  - On each surface: `BackgroundTransparency = 1`, then add a child Frame `NoTintBackdrop`:
    - attribute `AccentNoTint = true`, no children;
    - `Size (1,0,1,0)`, `ZIndex 0`;
    - bg = the design colour `#111111`;
    - a clone of the parent's `UICorner`.
  - `MainContent` (ScrollingFrame): `BackgroundTransparency = 1`.
  - `GradientOverlay`: attribute `AccentNoTint = true`, and set its UIGradient back to the design
    colour (attribute `AccentDesignColor`, ~`#101010`). Otherwise the cover fades into the tint
    instead of into black.
- **Shadow.** Clone the dance panel's `SoftShadow` (UIShadow) onto `02-MainContentWrapper` and `DraggableIcon`:
  - Color `0,0,0`, Transparency 0.82;
  - Offset `(0,0,0,8)`, BlurRadius `(0,28)`, Spread 0, ZIndex −1.

### Order (`MainContent` LayoutOrder; several used to tie at 2 and at 10)

| Row | LayoutOrder |
|---|---|
| PlayerInformation | 1 |
| SocialProofSection | 2 |
| **StatsStrip** (new) | 3 |
| BioSection | 4 |
| RelationshipStatus | 5 |
| Separator | 8 |
| ButtonsGroup | 10 |
| **ActionGroup** (new) | 11 |

### Rows

- **SocialProofSection** (Connections / Total likes):
  - height 70 → **68**;
  - `UIListLayout`: Padding 5, `HorizontalFlex = Fill`, `HorizontalAlignment = Center`;
  - tiles `Size (0,0,1,0)`; tile list padding 3.
  - Tile fill = button fill (design `#1b1b1b`, Transparency 0). Connection used to be
    `#000000 @ 0.95`, which the accent tint does not recognise, so it stayed the old theme colour.
  - Value Inter ExtraBold **24** white; caption Inter SemiBold **14** `#9a9a9a`.
- **StatsStrip** (new, owner picked "variasi 3"):
  - Frame, bg = button fill, `UICorner 20`, `Size (1,0,0,68)`, `UIPadding` L/R 6;
  - horizontal `UIListLayout` with `HorizontalFlex = Fill`, `VerticalAlignment = Center`;
  - 4 columns, each a vertical centred list with padding 3: value ExtraBold 24 white, caption SemiBold 14 `#9a9a9a`.
  - Columns, all read from the **target's** `leaderstats` (names from `Config.PlayerList.*_STAT_NAME`):

    | Value | Caption |
    |---|---|
    | Robux | `Robux` |
    | Cash | `Rupiah` |
    | Level | `Level` |
    | Streak | `Streak` |

  - Value format: no currency prefix (at 24 px, "Rp200K" does not fit a 63 px column). Short form
    K/M/B, one decimal under 100, trailing ".0" dropped. Examples: 18016 → `18K`, 200000 → `200K`.
- **ButtonsGroup** (Sync / Carry / Like): height 85 unchanged; `UIListLayout` Padding 5 and
  `HorizontalFlex = Fill`; buttons `Size (0,0,1,0)`.
  - Do not size them `(1/3, -n)`. Offsets are integers, so −2.67 becomes −2 and the row overflows by 2 px.
- **ActionGroup** (new transparent Frame, `AutomaticSize Y`, `UIListLayout` Padding 5):
  - Rows in order: SendGiftButton 1 → **ProposeCoupleButton** 2 → SendFriendRequest 3 → Investigate Avatar 4.
  - Grouped corners over the **visible** rows: first 18 top / 4 bottom, middle 4, last 4 top / 18
    bottom, a lone row 18 all round. These are the `GroupedRowCornerUtil` radii, but with gap 5 instead of its 2.
- **ProposeCoupleButton**: clone of `SendFriendRequest` with text `"Propose Couple"`. Wire it to
  `CoupleController`'s `RemoteSendRequest` `{ requestId, targetUserId }`.
  - **Open:** what to do when either player is already coupled. I suggested hiding the button, since the Status pill already says "Taken by …".

Measured at UIScale 0.8: every vertical and horizontal gap is 4 screen px, and the panel is 224 screen px wide.

## 3. Profile edit modal (`07-MenuGUI.UniversalModal`)

The look copies the check-in popup (`18-EventQuestPopup.Wrapper.Card`): a header bar and a body,
2 px apart. Width **280** (the owner said 340 was too wide).

**Modal frame.** Transparent stack: no background, no stroke, no padding, UIListLayout gap 2.

**Header** (clone of the popup `Header`):

- 40 tall, radius 18, popup header colour, UIShadow; left padding **12**.
- **No icon.**
- The existing `Title` label becomes the header label: SemiBold 16 white, left aligned.
  - Text is **"Edit " + the field in lower case**: "Edit display name", "Edit title", "Edit bio", "Edit status".
  - The code sends "Display Name" etc. as `request.title`, so `MenuShellUI` formats it.
- The existing **`CancelButton` becomes the close button** in the header's close slot, so its
  binding still works. It is 28×28, radius full, with the popup `CloseWrapper` colour. Inside:
  the popup `CloseButton` image (16 px, `#c8c8c8`). The button's own text and label are hidden;
  its gradient, stroke and padding are removed.

**Body** (popup `Main` look):

- Popup main colour, radius 6, UIShadow, padding 12, gap 12.
- `FieldHeader` (gap 2):
  - `FieldTitle`: the field name as the Profile tab shows it ("Display Name", "Title", "Bio", "Status"), Inter **Bold 20** white.
  - `Hint`: the same description as that row in the Profile tab, SemiBold 14 `#bebebe`, wrapped.
- `Field` (gap 6):
  - `InputValue`: height **56**, radius **8**, the themed row colour.
    - Text Inter SemiBold **18**, **centred**, `TextWrapped`, `ClipsDescendants`, `ClearTextOnFocus = false`, padding 12/6.
    - **No stroke.**
    - Placeholder **"Your " + field** ("Your bio"), colour `#828282`.
  - `Counter`: SemiBold 13 `#7c7c7c`, right aligned, "n / max".
    - Turns `#ff5a6a` past the limit.
    - Hidden for Title, whose limit lives in CustomTitle.
    - Limits mirror the server checks, which count bytes, not characters:

      | Field | Limit |
      |---|---|
      | Display name | 24 (`Config.ProfileMenu.DISPLAY_NAME_MAX_LENGTH`) |
      | Bio | 80 (`Config.AvatarContext.BIO_MAX_LENGTH`) |
      | Status | 50 (`Config.AvatarContext.STATUS_MAX_LENGTH`) |
- `UpdateButton`: full width, 38 tall.
  - The popup's primary button look: white + `UIGradient-Gold`, label SemiBold 15 white. **No stroke.**
  - The button's own `Text` must be transparent. The code writes "Update" to both the button and its label, and they overlap.

**Code changes needed:**

- `MenuGuiRefs` finds `CancelButton` / `UpdateButton` as direct children of the modal. They now
  live in `Header` / `Body`, so the lookup must search descendants.
- Per-field hint, placeholder, counter and limit go into `MenuShellUI:_openProfileFieldModal`.

**Open:** block typing past the limit, or only mark it red and let the server reject?

## 4. Queue notification island ("B4", to every player)

When anyone queues a song, **every player** gets a notification. The owner picked the **batch**
form (B4) for every count, after looking at 6 general toast styles, 6 "added to queue" cards and
4 broadcast cards.

The **motion** follows the owner's "dynamic island" idea. It runs at the real toast spot, top centre:

| Step | Shape | Time | Hold |
|---|---|---|---|
| 1 | 44 px dot pops in | 0.35 s, Back | — |
| 2 | widens to the pill (A) | 0.4 s, Back; compact layer fades in | 0.9 s |
| 3 | grows to the card (D), height = measured content | 0.5 s, Back; layers cross-fade | 3.6 s |
| 4 | shrinks back to the pill | 0.45 s, Quint | 2.2 s |
| 5 | collapses to the dot, scales out | 0.35 + 0.2 s | — |

- The radius stays **22** throughout. That is a full pill at 44 tall, so no corner tween is needed.
- The shell is a Frame with `ClipsDescendants`, plus UIShadow.
- Each content layer is a small CanvasGroup used only for `GroupTransparency`. Its content sits
  in a plain Frame, because a CanvasGroup with `AutomaticSize` measures 0.
- Content has a fixed width, so it does not reflow while the shell grows.

**Pill (A)**, 300 × 44, padding 4/16:

- Stacked avatar heads, 32 each in a 2 px ring of the panel colour, 14 apart, at most 3.
- Line 1 (SemiBold 12 `#828282`):
  - 1 request: "Rio queued · #4".
  - Several: "N new songs in queue".
- Line 2 (Bold 14 white, truncated):
  - 1 request: the track title.
  - Several: "Rio, Kai +N".

**Card (D)**, width 300, padding 14, gap 8:

- **Top row:** heads 30 each, 18 apart, at most 3. Then rich text:

  | Requests | Text |
  |---|---|
  | 1 | "**Rio** queued a song" |
  | 2 | "**Rio** and **Kai** queued" |
  | 3 | "**Rio, Kai** and **Mia** queued" |
  | 4+ | "**Rio, Kai** and N others queued" |

  Names are Bold white, the rest `#828282`.
- **Up to 3 track rows:** cover 28 (radius 6, the music player's own drawn `HzCoverTile`), then
  "**Title** · artist" (13, truncated), then the queue position "#n" (Bold 12 `#828282`).
- If there are more than 3: "+N more in queue" in SemiBold 12, accent colour.

Measured card heights: about 100 for 1 request, 180 for 3, 195 for 5.

**Data:** every queue entry already carries `requesterUserId` + `requesterDisplayName`
(`MusicDomain`), and the queue position is known. ETA is not needed for B4.

**Open:**

- Batch window length: requests within N seconds merge into one island.
- Minimum gap between islands.
- A "Hide queue notifications" option in Preferences.
- Whether the requester also gets their own copy.

**Notification GUI facts found:**

- `99-NotificationCenterV2` runs at **UIScale 0.8**. The demo used an extra 1.25 scale to show the
  island at 1:1. Decide whether to drop the 0.8 or size the island up.
- The accent theme recolours the per-type colours (success / warning / error / info) to its own
  hue, so under a purple theme every toast is purple. Any type colour that must survive needs
  `AccentNoTint` set **before** the instance is parented.

## 4b. Vote-skip island ("V1")

This replaces the centred `VoteModal`. It uses the same island shell as §4.

- **Card** (300 wide, padding 14, gap 10). **No kicker label.** The owner removed "VOTE TO SKIP".
  - Top row: initiator head 24, then "**Rio** wants to skip this song" (SemiBold 14, the rest `#828282`), then the countdown "0:12" (Bold 13) on the right.
  - Track row: white @0.95, radius 10, cover 40, title Bold 14 (truncated), artist SemiBold 12 `#828282`.
  - Tally:
    - Labels: "Skip **n**" (Skip in the error colour), "need X of Y" (`#828282`), "**n** Keep".
    - One 6 px bar: the skip share fills from the left in the error colour, the keep share from the right in white, and a 2 px white mark sits at the threshold.
  - Buttons side by side, 36 tall, radius full:
    - "Keep it": white @0.95, Bold 14 white.
    - "Skip": solid white, Bold 14 black.
- **Flow:**
  1. Dot.
  2. Pill: initiator head, "Rio wants to skip · 0:15", track title.
  3. The card stays open **until you vote** or the vote ends.
  4. After voting it shrinks to a **progress pill**: cover, "You voted skip · 6 of 7" in the error colour, the countdown, and a 4 px mini tally bar with the mark.
  5. The result shows as a pill: "Skipped · 7 of 12 voted", or "Keeps playing" when time runs out. It then collapses.
- Tally changes tween over 0.3 s.

## 4a. General toasts ("D" card, "A" pill)

The owner picked **D** out of 6 general toast styles, played with the island motion: dot → pill A → card D → pill A. This section was missed when the spec was first written, and was added after the owner asked why toasts still looked old.

- **Card D**, padding 14, gap 4:
  - Top row: the domain in spaced capitals ("M U S I C"), Bold 12 in the type colour; then a spacer; then "now", SemiBold 13 `#828282`.
  - The headline, Bold 18 white, wrapped.
  - The detail, SemiBold 14 `#bebebe`, wrapped.
- **Pill A:** a 32 px round badge (the type colour @0.82, the toast icon tinted in the type colour); the domain, SemiBold 12 `#828282`; the headline, Bold 14, truncated.
- **Type colours:** `Config.Notify.COLOR_*`. Couple uses pink `#ff6fae`.
- **When the title is just the domain name** (e.g. "[Profile] Saved"), the message becomes the headline and there is no detail line.

## 4c. Implementation status (2026-10-07)

All of §1–§4b is in code (see CHANGELOG `[Unreleased]`). Still open:

- **Phone ACM scale.** `ACM_GUI_DESKTOP` covers desktop only, so the phone keeps the current scale and its gaps were not re-measured.
- **Island vs general toasts.** Resolved: toasts are islands now (§4a), so they queue behind each other instead of overlapping. Every toast now takes about 7 s instead of about 3.5 s. When 2+ islands are waiting, a toast skips its card.
- **"Hide queue notifications" in Preferences.** Not built. Today only `Config.NotificationIsland.QUEUE_ENABLED` turns it off, venue-wide.
- **Requester's own copy.** The requester sees the island too (the "Added to queue" toast is skipped instead).
- **Vote from the panel button.** It counts as a local vote (via `PanelShell` → `noteLocalVote`). A vote cast before this client got "started" is unknown, because the payload has no voter list.

## 5. Traps found while doing this

- Gap × UIScale must be a whole number of pixels. Fractional sizes do not matter, because a whole-pixel gap shifts every edge equally.
- Offsets are integers. Split widths with `UIFlexAlignment.Fill`, not `(1/n, -gap·(n-1)/n)`.
- A CanvasGroup clips UIShadow, including an ancestor CanvasGroup.
- `AccentNoTint` covers the instance and all descendants. To exclude only a surface, use an empty backdrop child.
- The accent tint skips some design colours, such as near-transparent black, so those keep stale theme colours.
- `ForeignGuiGuardService` deletes unknown ScreenGuis in PlayerGui. Live mockups have to go inside an existing kit ScreenGui.
- Connections made from MCP `execute_luau` in a playtest stop firing after a while.
- AutomaticSize is not computed under an invisible ancestor. The island's card measured 44 while the shell was still `Visible = false`, so it is now measured off-screen in the visible layer first.
- `require` from MCP `execute_luau` gets its own module cache. A test island draws a second shell next to the game's real one.
