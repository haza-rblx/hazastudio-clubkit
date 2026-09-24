# P4b — inventory of `OverheadGUIMainTemplateV4` (THE BASIC TEST 1.3)

Read 2026-09-24 from the open place **THE BASIC TEST 1.3** (placeId `75916114543452`, Studio instance
`instance:lw2-9il`), edit mode, **read-only** `execute_luau` (no property writes, no playtest). Place config:
`ClubKitConfig.Overhead.GuiType = "V4"`. `Workspace.StreamingEnabled = false`, so every client holds every
player's head, and so every head's nametag.

Templates present in `ReplicatedStorage` (recursive search): **only `OverheadGUIMainTemplateV4`**
(V1, V2, V3, V5 are missing from this place). Class totals (BillboardGui included):

| Class | Count | | Class | Count |
|---|---|---|---|---|
| BillboardGui | 1 | | UIAspectRatioConstraint | 12 |
| Frame | 24 | | UIGradient | **18** |
| ImageLabel | 13 | | UIStroke | 8 |
| TextLabel | 13 | | UIPadding | 8 |
| UIListLayout | 4 | | UICorner | 3 |
| UIScale | 2 | | CanvasGroup | **0** |
| **Total** | **106** | | | |

BillboardGui: `Size {5,0},{4,0}` (studs), `StudsOffset (0, 3.5, 0)`, `MaxDistance 30`, `AlwaysOnTop false`,
`LightInfluence 0.5`, `ZIndexBehavior Sibling`, `Enabled true` (the server sets `Enabled = false` on every clone).

## Classification key

What the kit does with each instance, from reading the renderer (`Client/UI/OverheadUI.luau`, the client
`OverheadController`, `Shared/Utils/SpecialTitleRenderer.luau`, the server `OverheadController`
`attachGui`, `AdminPanelUI` preview, `ChatBubbleAdornee`):

- **R — read by code.** Found by name, or by `FindFirstChildWhichIsA`, and written by the renderer. Removing
  or renaming it changes behaviour.
- **D — pure decoration / layout.** Nothing reads it; it only shapes how the tag looks. It can be dropped if
  the same look comes from a property on an instance we keep (Size/Position instead of UIPadding,
  `SizeConstraint = RelativeYY` instead of a 1:1 UIAspectRatioConstraint, `BackgroundColor3` instead of a
  one-colour UIGradient).
- **X — duplicate / overwritten.** The kit rewrites every property on it at runtime, or creates an
  identical one itself when it is missing, or it does nothing visible (a white→white gradient).
- **H — never visible.** It is disabled, the engine never shows it, or the code looks for a different name.

## Tree

Sizes are `{xScale,xOffset,yScale,yOffset}`. `Vis` is the template value; the renderer hides every wrapper
row on attach (`resetGuiUntilPayload`, `OverheadUI.luau:170-191`) and then shows what the payload needs.

| # | Instance | Key properties | Class | Why |
|---|---|---|---|---|
| 1 | **BillboardGui** `OverheadGUIMainTemplateV4` | see above | R | Cloned by the server (`S/Controllers/OverheadController.luau:521-588`); `MaxDistance` is overwritten on every `apply` (`OverheadUI.luau:1565`, Near 28 / Medium 48 / Far `PERF_FAR_MAX_DISTANCE` = 90), so the template's 30 is never what a player sees |
| 2 | ├ Frame `Frame` | `{1,0,1,0}`, BgT 1 | R | the wrapper (`Config.OverheadGuiVariants.V4.wrapperName`) |
| 3 | │ ├ UIListLayout | Vertical, Sort **Name**, pad 0.005, HA Left, VA Bottom | R | `findOverheadListLayout` sets `SortOrder`/`HorizontalAlignment` (`:1608-1620`); `ChatBubbleAdornee` reads `AbsoluteContentSize` |
| 4 | │ ├ UIScale `UIScale` | 0.95 | D | Decoration. The kit adds its own `_OverheadPopScale` UIScale to the same wrapper (`:193-204`) — **two UIScale siblings on one object**; which one Roblox honours is not something the kit controls. Bake 0.95 into the BillboardGui size instead |
| 5 | │ ├ Frame `00-DonationLayers` | `{1,0,0.12,0}` | R | `setDonationLayers` (`:1134-1228`) |
| 6 | │ │ ├ UIGradient | **Enabled=false**, #450063 | H | disabled, never enabled |
| 7 | │ │ ├ UIListLayout | Horizontal, Sort Name, pad 0.02, Center/Center | D | chip layout |
| 8 | │ │ ├ UIPadding | Bottom 0.12 | D | = chip height 0.88 with VA Top |
| 9 | │ │ ├ Frame `RobuxRankWrapper` | `{0.33,0,1,0}`, BgT 0, white | R | by name; also **cloned** into `RoleChipWrapper` on every apply (`ensureRoleChip`, `:1056-1071`, called unconditionally at `:1201`) |
| 10 | │ │ │ ├ TextLabel `RobuxRank` | ExtraBold, TextScaled | R | `FindFirstChildWhichIsA("TextLabel")` |
| 11 | │ │ │ │ └ UIStroke | Contextual 1.0 #2D2D2D | X | `applyTextOutline` renames it `__OverheadTextOutline` and overwrites colour/thickness/transparency (`:636-673`); creates one if missing |
| 12 | │ │ │ ├ UICorner | 1,0 (pill) | D | |
| 13 | │ │ │ ├ UIGradient | 4-stop rainbow | R | `setChipGradientAnim`, `paintRoleChip` |
| 14 | │ │ │ ├ UIPadding | T/B 0.18 | D | = label Size `{1,0,0.64,0}` Pos `{0,0,0.18,0}` |
| 15 | │ │ │ └ UIStroke | Thick 0.03, **Enabled=false** | H | |
| 16–22 | │ │ └ Frame `RupiahRankWrapper` + same 6 children (`RupiahRank` R, text UIStroke X, UICorner D, UIGradient R, UIPadding L/R 0.1 T/B 0.18 D, UIStroke Enabled=false H) | | R/X/D/R/D/H | same as 9–15 |
| 23 | │ ├ Frame `00-SpecialStatus` | `{1,0,0.09,0}`, BgT 0, Bg #00FFAA, Vis false | R | `rowSet("00-SpecialStatus")` (`:1775-1783`) |
| 24 | │ │ ├ UIGradient | #000000 → #000000 | D | turns the green background black = `BackgroundColor3 = #000000` |
| 25 | │ │ └ TextLabel `StatusValue` | ExtraBold, TextScaled, #D9D9D9 | R | first TextLabel of the row |
| 26 | │ │   └ UIGradient | #FFFFFF → #FFFFFF | X | white × colour = identity: does nothing |
| 27 | │ ├ Frame `01-SpecialTitle` | `{1,0,0.08,0}`, BgT 1, LO 3 | R | `ensureSpecialTitleRow`, `SpecialTitleRenderer` |
| 28 | │ │ ├ UIGradient | #630051 | H | `SpecialTitleRenderer.clearRowBackground` sets every row UIGradient `Enabled=false` and row `BackgroundTransparency=1` on every apply (`:1686-1687`, `SpecialTitleRenderer.luau:95-109`); `applyGeneratedStyle` writes its colour but it is never drawn |
| 29 | │ │ ├ UIPadding | T/B 0.1 | X | `normalizeSpecialTitleLayout` zeroes all four paddings (`SpecialTitleRenderer.luau:127-133`) |
| 30 | │ │ └ TextLabel `SpecialTitleText` | Bold, TextScaled | R | by name |
| 31 | │ │   └ UIGradient | white | R | generated-style text colours + shared animation loop (`:1393-1425`, `:1369-1385`) |
| 32 | │ ├ Frame `02-BadgeGroup` | `{1,0,0.14,0}` | R | `setBadges` (`:924-954`) |
| 33 | │ │ ├ UIListLayout | Horizontal, Sort Name, HA Center, VA Top | D | |
| 34–36 | │ │ ├ Frame `01-OwnerCoOwnerBadge` `{0.3,0,1,0}` → ImageLabel `Badge` (Fit) + UIAspectRatioConstraint 1.0 | | R / D / D | frame toggled by name (`ALL_BADGES`, `:43-56`); image = art; AR = square |
| 37–39 | │ │ ├ `02-DeveloperBadge` (same 3) | | R/D/D | |
| 40–42 | │ │ ├ `03-AdminBadge` | | R/D/D | |
| 43–45 | │ │ ├ `04-MemberBadge` | | R/D/D | |
| 46–48 | │ │ ├ `05-VIPMemberBadge` | | R/D/D | |
| 49–51 | │ │ ├ `06-VVIPMemberBagde` (typo is the contract) | | R/D/D | |
| 52–54 | │ │ ├ **`07-SupremeMemberBadge`** (same 3) | Vis false | **H** | the code looks for **`07-ELITEMemberBadge`** (`OverheadUI.luau:50`, `Config.luau:168`, `OverheadDomain.luau:534`). This frame is never found, never shown: **the Elite/Supreme badge cannot appear on THE BASIC TEST's nametags** (separate bug, see below) |
| 55–59 | │ │ ├ `08-StreakBadge` → `Badge` → TextLabel `TextLabel` + UIPadding; + AR | | R/D/R/D/D | `setStreakCount` finds the first TextLabel recursively (`:956-965`) |
| 60–64 | │ │ ├ `09-LikeCounterBadge` → `Badge` → TextLabel `LikeCounts` + UIPadding; + AR | | R/D/R/D/D | `setLikeCount` (`:1009-1018`) |
| 65–70 | │ │ ├ `10-CommunityBadge` → `Badge` → ImageLabel `CommunityLogo` (+UICorner 0.3) + UIPadding; + AR | | R/D/R/D/D/D | `setCommunityBadge` finds `CommunityLogo` recursively (`:1020-1030`) |
| 71–73 | │ │ ├ `11-DJBadge` (same 3) | | R/D/D | |
| 74–76 | │ │ └ `12-InfluencerBadge` (same 3) | | R/D/D | |
| 77 | │ ├ Frame `03-Level` | `{1,0,0.065,0}` | R | `setLevelRow` (`:967-993`) |
| 78 | │ │ └ TextLabel `LevelCounterText` | Bold, TextScaled | R | found as "first TextLabel" (the code asks for `LevelText` first). No `XPBarFill` in V4, so no XP bar |
| 79 | │ ├ Frame `04-SpecialRank` | `{1,0,0.08,0}`, BgT 0, Bg #00FFAA | R | `rowSet("04-SpecialRank")` |
| 80 | │ │ ├ UIGradient | #000000 | D | = `BackgroundColor3 = #000000` |
| 81 | │ │ ├ UIPadding | T/B 0.1 | D | = label Size `{1,0,0.8,0}` Pos `{0,0,0.1,0}` |
| 82 | │ │ └ TextLabel `SpecialRoleName` | ExtraBold | R | |
| 83 | │ │   └ UIGradient | #FFAF0F → #FFA01C | R | `applyRoleStopsGradient` (`:562-594`, `roleColor.stops`) |
| 84 | │ ├ Frame `05-TopSpender` | Vis false | H | shown only when `Config.Donation.SHOW_LEGACY_TOP_SPENDER_ROW == true`; engine constant, **false**, not a buyer key (`Config.luau:3061`, `OverheadUI.luau:1800-1810`). Superseded by `00-DonationLayers` |
| 85 | │ │ ├ TextLabel `TopSpenderDisplayName` | | H | |
| 86 | │ │ └ UIGradient | #0D3800 | H | |
| 87 | │ ├ Frame `08-DisplayNameAndMembership` | `{1,0,0.1,0}`, LO 7 | R | `:1874-1900` |
| 88 | │ │ ├ UIListLayout | Horizontal, Sort **LayoutOrder**, pad 0.005, Center | D | |
| 89 | │ │ ├ TextLabel `PlayerDisplayName` | AutoSize X, Bold, RichText | R | `setNamedText` |
| 90 | │ │ │ └ UIStroke | T 0.8 | X | overwritten by `applyDisplayNameMembershipOutlines` |
| 91 | │ │ ├ TextLabel `Separator` "•" | AutoSize X, TextSize 42 | R | toggled with the membership label (`:1883-1887`); outline-skip list |
| 92 | │ │ │ ├ UIScale | 0.6 | D | = label height 0.6 |
| 93 | │ │ │ └ UIStroke | T 0.8 | D | the kit leaves it (Separator is on the skip list, `:36-40`) — a 0.8-transparent outline on a dot |
| 94 | │ │ └ TextLabel `MembershipLevel` | AutoSize X, Bold, RichText | R | text + gradient choice |
| 95–99 | │ │   ├ UIGradient `UIGradientElite` / `Guest` / `Member` / `VIP` / `VVIP` | one enabled at a time | R | `applyMembershipGradients` enables the one whose **name** matches (`:1518-1524`, `RANK_GRADIENT_MAP` `:110-116`); `AfterTeam` adds a 6th at runtime (`:1528-1537`) |
| 100 | │ │   └ UIStroke | T 0.8 | X | overwritten |
| 101 | │ └ Frame `09-CoupleDisplayName` | `{1,0,0.07,0}`, LO 8 | R | `:1906-1910` |
| 102 | │   └ TextLabel `CoupleDisplayNameText` | ExtraBold | R | `getRelationshipStatusLabel` (`:775-785`) |
| 103–105 | │     ├ UIGradient `UIGradient` (Taken) / `UIGradientFun` / `UIGradientSingle` | | R | enabled by name (`:787-793`, `RELATIONSHIP_GRADIENT_MAP` `:104-108`) |
| 106 | │     └ UIStroke | T 0.8 | X | overwritten |

Rows the renderer supports that **V4 does not have**: `06-TopDonate`, `07-Rank`, `08-DisplayName`,
`02-AddOnCustomImageBadge` (V5). All lookups are nil-safe. Note the Settings menu still shows a **"Role"**
toggle (`overheadLayerVisible.Rank`, `MenuSettingsCore.luau:374`) that controls `07-Rank` — on V4 that toggle
does nothing.

## Totals by classification

| Class | Count | What it is |
|---|---|---|
| **R** read by code | **49** | the renderer contract (names + the classes it searches for) |
| **D** decoration / layout | **40** | 22 are badge art + badge squares (11 `Badge` images, 11 AR constraints); the rest paddings, list layouts, corners, 2 one-colour background gradients, 2 UIScales, 1 separator stroke |
| **X** duplicate / overwritten | **7** | 5 text UIStrokes the kit rewrites, 1 no-op white gradient, 1 title padding the kit zeroes |
| **H** never visible | **10** | 2 disabled gradients, 2 disabled chip strokes, the whole `05-TopSpender` row (3), the misnamed `07-SupremeMemberBadge` (3) |

Only 49 of 106 instances are part of the contract; 17 (X + H) do nothing at all.

UIGradients, 18 in all: **12 read** (2 chips, title text, special-rank text, 5 membership, 3 couple),
2 decoration (status and rank backgrounds, both one solid colour), 1 no-op (status text, white→white),
3 never visible (donation container, title row, top spender). Of the 12 read, **8 exist only so the code can
pick one by name** (5 membership tiers, 3 relationship modes) — one of each set is enabled at a time.

## What the client adds at runtime (not in the template)

The template count is what the **server replicates** to every client for every head. On top of it, for every
head the client builds an `OverheadUI` for (a head whose payload reached this viewer), the renderer creates:

| Added | Per head | Where |
|---|---|---|
| UIStroke outline on every TextLabel that lacks one (not under the title, not `Separator`): `StatusValue`, streak `TextLabel`, `LikeCounts`, `LevelCounterText`, `SpecialRoleName`, `TopSpenderDisplayName` | +6 | `applyOverheadTextEffects` in `OverheadUI.new` (`:454`, `:723-773`) |
| `_OverheadPopScale` UIScale | +1 | `ensurePopScale` (`:193-204`) |
| `RoleChipWrapper` = clone of `RobuxRankWrapper` (Frame, TextLabel, text UIStroke, UICorner, UIGradient, UIPadding, disabled UIStroke) — created on **every** apply whether the role uses a chip or not | +7 | `ensureRoleChip` (`:1201`) |
| Shared `UIShadow` | 0 | `Config.UIShadow.ENABLED = false` |
| Special title holders only: `TitleTextHost` Frame + `RuntimeUIScale` + TitleColorPreset gradients/strokes/drop-shadow clone | +2 … +6 | `SpecialTitleRenderer`, `TitleColorPreset` |
| `AfterTeam` role only: `UIGradientAfterTeam` on membership (and rank row) | +1 | `ensureAfterTeamGradient` |

So a V4 head with an `OverheadUI` is **~120 instances** on the client (106 + 14), not 106.

`ENABLE_LAZY_ROWS = true` parks hidden rows with `Parent = nil` after 1 s (`:347-374`). That takes them out of
layout, but they stay in memory; they are not "0 instances".

## Per client at 200 players (streaming off)

`heads × template + k × runtime additions`, where `k` = heads this client built an `OverheadUI` for (payload
received; with the 30-nearest-viewer interest cap roughly 30–60 on a packed floor, 200 worst case):

- V4, k = 60: 200 × 106 + 60 × 14 = **22,040** GUI instances (worst case k = 200: 24,000), of them
  **3,600 UIGradients** from the template alone. The server holds the same 21,200 as clones.

## Other findings made while reading

1. **Elite/Supreme badge never shows on THE BASIC TEST** — template frame `07-SupremeMemberBadge`, code
   expects `07-ELITEMemberBadge`. Either a place-side rename or a template that predates the name; not a P4b
   concern but P4b must use the code's name. Worth a separate look at other buyers' V4.
2. **V4's wrapper is a plain Frame, not a CanvasGroup.** CONTEXT.md's "Overhead budget … one CanvasGroup
   texture each" does not hold for V4 (corrected in the same turn), and the pop-in fade
   (`GroupTransparency`) is a no-op on V4 — only the scale pop runs.
3. `ClubKitConfig.luau` comment for `GuiType` says an unknown or missing version "falls back to V1". Neither is
   true: `ConfigBootstrap` keeps the engine default for an unknown name (`ConfigBootstrap.luau:406-414`), and a
   known name whose template is **missing from the place** gives **no nametags at all** — the server logs
   `Template BillboardGui not found` and `attachGui` returns nil (`S/Controllers/OverheadController.luau:532-536`,
   `:568-571`). P4b has to fix this before a new variant ships (design §5).
4. The Settings "Role" toggle drives a row (`07-Rank`) V4 does not have.
