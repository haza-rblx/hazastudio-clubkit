# P4b — trimmed overhead nametag template (design, not built)

Status: **designed 2026-09-24, not built.** Plan item H14 (`production-hardening-2026-09-24.md` §2 H), owner
decision 18: *design now, ship later as its own template release (Packager step)*. Nothing here goes into the
current source-sync release. ADR: [`0018-trimmed-overhead-template.md`](../../adr/0018-trimmed-overhead-template.md) (Proposed).
Inventory this is built on: [`p4b-template-inventory.md`](p4b-template-inventory.md).

## 0. Verdict in five lines

1. V4 is 106 instances per head, **49 of them are the renderer contract**; 17 do nothing (overwritten or never
   visible), 40 are decoration that can mostly move into properties of instances we keep.
2. **No-feature-loss floor is 49 instances, 6 UIGradients** (build level B below), with four small, backward-
   compatible renderer changes. With no renderer change at all (level A) the floor is 58 / 12.
3. **≤ 40 per head is not reachable without removing something** (10 layers, 12 badge kinds, 2 donation chips,
   the image title). 40 needs a badge pool (renderer change) plus two visual cuts (level C).
4. Per client at 200 players: V4 ≈ 22,000 GUI instances → B ≈ 10,500 (−52 %). The plan's 8,000 budget is only
   met by C-plus-cuts (≈ 8,600, still over) or by P4b-client (client-built pool of 40, ≈ 2,400). Owner decision.
5. The name `V5` is taken (image-title variant, `Config.luau:886-894`). The trimmed template is **`V6`** and it
   is a trimmed **V5** (image row included, hidden), so one template serves V4 and V5 venues.

## 1. Targets, argued from the inventory

| Target | Plan | Proposed | Why |
|---|---|---|---|
| Instances per head (template) | ≤ 40 | **≤ 50** (B = 49) | the contract alone is 49 in V4; B gets there with zero visible change. 40 costs features (§3 level C) |
| UIGradients per head | ≤ 6 (brief) | **6** | 2 chips + title text + special-rank text + 1 membership + 1 couple. The 5 + 3 "pick one by name" sets become one gradient each, painted from attributes (R2/R3) |
| TextLabels per head | — | **≤ 12** | one per text the renderer writes; `TopSpenderDisplayName` (dead) removed |
| CanvasGroup | — | **0** | V4 has none; a CanvasGroup wrapper is one texture per enabled head. Keep it that way |
| `MaxDistance` on the template | ≤ 90 | **48** | inert: `OverheadUI:apply` overwrites it on every apply (`OverheadUI.luau:1565` → Near 28 / Medium 48 / Far `PERF_FAR_MAX_DISTANCE` 90), and the server clones with `Enabled = false`. 48 = the renderer's default, so the template states what a player actually gets. The ≤ 90 guarantee lives in `Config.Overhead.PERF_FAR_MAX_DISTANCE`, not in the template |
| Text outlines in the template | — | **0 UIStroke** | the kit re-creates and overwrites every text outline at runtime (`applyTextOutline`, `:636-673`), so template strokes are replicated for nothing |

## 2. Before → after (level B, recommended)

Numbers `#n` refer to the inventory table. `Keep` = unchanged apart from the sizing notes.

```
BEFORE (V4, 106)                                   AFTER (V6, 49)
BillboardGui  5×4 studs, MaxDistance 30            BillboardGui OverheadGUIMainTemplateV6  4.75×3.8 studs (0.95 baked), MaxDistance 48     1
└ Frame 'Frame'                                     └ Frame 'Frame'                                                                          2
  ├ UIListLayout                                      ├ UIListLayout (Vertical, Sort Name)                                                   3
  ├ UIScale 0.95                     → baked into BillboardGui size (see §6 risk 2)
  ├ 00-DonationLayers (+LL, +UIPadding, +disabled grad)
  │                                                   ├ Frame 00-DonationLayers                                                              4
  │                                                   │ ├ UIListLayout (Horizontal, VA Top)  — bottom padding → chip height 0.88              5
  │ ├ RobuxRankWrapper (7)                            │ ├ Frame RobuxRankWrapper {0.33,0,0.88,0}                                              6
  │ │                                                 │ │ ├ UICorner 1,0                                                                      7
  │ │                                                 │ │ ├ UIGradient (rainbow)                                                              8
  │ │                                                 │ │ └ TextLabel RobuxRank {1,0,0.64,0} @ {0,0,0.18,0}  — replaces UIPadding            9
  │ └ RupiahRankWrapper (7)                           │ └ Frame RupiahRankWrapper (same 4; label {0.8,0,0.64,0} @ {0.1,0,0.18,0})         10-13
  ├ 00-SpecialStatus Frame+bg grad+label+no-op grad   ├ TextLabel 00-SpecialStatus  Bg #000000, BgT 0, #D9D9D9 text        (R4)            14
  ├ 01-SpecialTitle (+row grad, +UIPadding)           ├ Frame 01-SpecialTitle                                                                15
  │                                                   │ └ TextLabel SpecialTitleText                                                         16
  │                                                   │   └ UIGradient                                                                       17
  │                                    (V5 row)       ├ Frame 02-AddOnCustomImageBadge  Visible=false  (sizing from the V5 master)          18
  │                                                   │ └ ImageLabel ChangeableImage (ScaleType Fit)                                         19
  ├ 02-BadgeGroup: 12 × (Frame+Badge image+AR),       ├ Frame 02-BadgeGroup                                                                  20
  │   + 2 text + 3 paddings + logo + corner (45)      │ ├ UIListLayout (Horizontal, Sort Name)                                               21
  │                                                   │ ├ ImageLabel 01-OwnerCoOwnerBadge   Size {1,0,1,0} SizeConstraint RelativeYY          22
  │                                                   │ ├ ImageLabel 02-DeveloperBadge                                                       23
  │                                                   │ ├ ImageLabel 03-AdminBadge                                                           24
  │                                                   │ ├ ImageLabel 04-MemberBadge                                                          25
  │                                                   │ ├ ImageLabel 05-VIPMemberBadge                                                       26
  │                                                   │ ├ ImageLabel 06-VVIPMemberBagde   (typo is the contract)                            27
  │                                                   │ ├ ImageLabel 07-ELITEMemberBadge  (V4 place had '07-SupremeMemberBadge': never shown) 28
  │                                                   │ ├ ImageLabel 08-StreakBadge                                                          29
  │                                                   │ │ └ TextLabel TextLabel {0.37,0,0.48,0} @ {0.34,0,0.32,0}                          30
  │                                                   │ ├ ImageLabel 09-LikeCounterBadge                                                     31
  │                                                   │ │ └ TextLabel LikeCounts {0.42,0,0.43,0} @ {0.29,0,0.26,0}                          32
  │                                                   │ ├ ImageLabel 10-CommunityBadge                                                       33
  │                                                   │ │ └ ImageLabel CommunityLogo {0.64,0,0.64,0} @ {0.19,0,0.19,0}                      34
  │                                                   │ │   └ UICorner 0.3,0                                                                 35
  │                                                   │ ├ ImageLabel 11-DJBadge                                                              36
  │                                                   │ └ ImageLabel 12-InfluencerBadge                                                      37
  ├ 03-Level Frame + label                            ├ TextLabel 03-Level                                               (R4)            38
  ├ 04-SpecialRank Frame+bg grad+pad+label+grad       ├ Frame 04-SpecialRank  Bg #000000, BgT 0 — replaces the black row gradient           39
  │                                                   │ └ TextLabel SpecialRoleName {1,0,0.8,0} @ {0,0,0.1,0}  — replaces UIPadding          40
  │                                                   │   └ UIGradient (#FFAF0F→#FFA01C)                                                     41
  ├ 05-TopSpender (3, never shown)   → removed
  ├ 08-DisplayNameAndMembership (14)                  ├ Frame 08-DisplayNameAndMembership                                                    42
  │                                                   │ ├ UIListLayout (Horizontal, Sort LayoutOrder)                                        43
  │                                                   │ ├ TextLabel PlayerDisplayName (LO 0, AutoSize X)                                     44
  │                                                   │ ├ TextLabel Separator "•" (LO 2) Size {0,0,0.6,0} — replaces its UIScale 0.6         45
  │                                                   │ └ TextLabel MembershipLevel (LO 3)                                                   46
  │                                                   │   └ UIGradient 'UIGradient' + attributes per tier                 (R2)            47
  └ 09-CoupleDisplayName Frame + label + 3 grads      └ TextLabel 09-CoupleDisplayName                                   (R4)            48
                                                          └ UIGradient 'UIGradient' + attributes per mode                 (R2/R3)         49
```

Every removal, with the instance that now carries its job:

| Removed (V4 #) | n | Job moved to |
|---|---|---|
| wrapper UIScale 0.95 (#4) | 1 | BillboardGui Size × 0.95 |
| donation container UIGradient, disabled (#6) | 1 | — (never visible) |
| donation container UIPadding (#8) | 1 | chip height 0.88 + list VA Top |
| chip text UIStrokes (#11, #18) | 2 | kit creates them at runtime (it overwrote these anyway) |
| chip UIPaddings (#14, #21) | 2 | label Size/Position |
| chip disabled UIStrokes (#15, #22) | 2 | — (never visible) |
| status row: Frame + black gradient + no-op text gradient (#23, #24, #26) | 3 | the row **is** the TextLabel, `BackgroundColor3 = #000000` (R4) |
| title row UIGradient (#28), title UIPadding (#29) | 2 | — (the renderer disables / zeroes them every apply) |
| 12 badge Frames + 12 UIAspectRatioConstraints (#34-76) | 24 | the named ImageLabel itself, `SizeConstraint = RelativeYY` (square of the row height = what AR 1 + FitWithinMaxSize produced) |
| 3 badge UIPaddings (streak, like, community) | 3 | child Size/Position |
| level row Frame (#77) | 1 | the row is the TextLabel (R4) |
| special-rank row gradient + UIPadding (#80, #81) | 2 | `BackgroundColor3 = #000000`; label Size/Position |
| `05-TopSpender` row (#84-86) | 3 | — (`SHOW_LEGACY_TOP_SPENDER_ROW = false`, engine constant, not a buyer key) |
| name-row strokes (#90, #100), separator UIScale + stroke (#92, #93) | 4 | kit strokes at runtime; Separator height 0.6; the 0.8-transparent dot outline dropped |
| 4 of 5 membership gradients (#95-99) | 4 | one gradient, colour + rotation per tier from attributes (R2) |
| couple row Frame, stroke, 2 of 3 gradients (#101, #106, #103-105) | 4 | row is the TextLabel (R4), kit stroke, one gradient from attributes (R3) |
| **Total removed** | **59** | |
| Added: V5 image row (`02-AddOnCustomImageBadge` + `ChangeableImage`) | +2 | so V6 also serves V5 venues |

106 − 59 + 2 = **49**, matching the tree. Renames, not additions: `StatusValue` → the row
`00-SpecialStatus`, `LevelCounterText` → `03-Level`, `CoupleDisplayNameText` → `09-CoupleDisplayName`, each badge
`Badge` image → its frame's name, `07-SupremeMemberBadge` → `07-ELITEMemberBadge`.

### Attribute scheme for the one-gradient sets (R2/R3)

The buyer's customisation point stays in the template (Studio attribute editor), not in code:

- `MembershipLevel.UIGradient` carries one **ColorSequence attribute per tier, named exactly like the V4
  gradient it replaces** (`UIGradientElite`, `UIGradientGuest`, `UIGradientMember`, `UIGradientVIP`,
  `UIGradientVVIP`, plus any custom `membershipGradientName` a buyer added) and a number attribute
  `<name>_Rotation`.
- `09-CoupleDisplayName.UIGradient` carries `UIGradient` (Taken — V4's Taken gradient is literally named
  `UIGradient`), `UIGradientFun`, `UIGradientSingle` (+ `_Rotation`).
- `UIGradientAfterTeam` needs no attribute: the renderer paints solid black when asked for it and the attribute
  is absent (today it creates an instance, `OverheadUI.luau:1528-1537`).

Because the names do not change, the payload (`membershipGradientName`, `RANK_GRADIENT_MAP`,
`RELATIONSHIP_GRADIENT_MAP`) does not change either.

## 3. Build levels

| Level | Renderer change | Template/head | UIGradient | TextLabel | Runtime adds/head | Feature loss |
|---|---|---|---|---|---|---|
| **V4 today** | — | **106** | 18 | 13 | +14 (6 outlines, pop scale, 7-instance role-chip clone) | — |
| **A** zero renderer change | only R0 (variant entry + fallback) | **58** | 12 | 12 | +16 (10 outlines, pop scale, 5-instance role-chip clone) | none |
| **B** recommended | R0–R4 | **49** | **6** | 12 | +11 (10 outlines, pop scale) | none |
| **C** badge pool | R0–R5 | **44** | 6 | 12 | +11 | overflow: more than 4 plain badges at once → lowest-priority dropped |
| **C + cuts** | R0–R5 | **40** | 6 | 11 | +10 | no Separator dot, square community logo, no image-title row in the default template |

Level A differs from B in: status / level / couple stay Frame + TextLabel (+3), membership keeps 5 gradients
and couple 3 (+6).

## 4. Renderer contract impact (all backward compatible with V1–V5)

Each change branches on the template's **shape**, never on the variant name (`renderer` stays inert metadata,
CONTEXT "Overhead GUI variant"), so V4/V5 places keep rendering exactly as today.

| # | Change | Anchor | Size |
|---|---|---|---|
| **R0a** | Add `V6 = { templateName = "OverheadGUIMainTemplateV6", renderer = "V6", wrapperName = "Frame", preserveLayoutOrder = true }` | `Sh/Constants/Config.luau:861-895` | 6 lines |
| **R0b** | Missing-template fallback. Today a known `GuiType` whose template is absent gives **no nametags** (`S/Controllers/OverheadController.luau:521-536`, `attachGui` returns nil at `:568-571`). Resolve once at boot: wanted → V5 → V4 → V3 → V2 → V1, first one present; `warn` once naming both; publish the chosen name as a `ReplicatedStorage` attribute (`ClubKitOverheadTemplate`) so the client (`C/Controllers/OverheadController.luau:61-62`), `AdminPanelUI:_getOriginalOverheadWrapper` (`AdminPanelUI.luau:842-876`, uses `Config.Template.TEMPLATE_NAME`) and `LoadingScreenUI.isProjectOverheadGui` (`LoadingScreenUI.luau:147-156`) agree. Pure resolver in `Sh/Domain/` (lune-testable, tdd-luau seam) | server controller + 3 readers | ~40 lines |
| **R0c** | Fix the `GuiType` comment in the **template** `ClubKitConfig.luau` (`:568-575`): add `"V6"`, and replace "falls back to V1" with what R0b does. Buyer files are not touched (comments are not fill-forwarded) | template only | comment |
| **R1** | Create `RoleChipWrapper` only when the payload has a `roleChip` text (today: cloned on **every** apply for every head) | `C/UI/OverheadUI.luau:1199-1214` (`ensureRoleChip` call at `:1201`) | ~5 lines. Also saves 7 instances per head on **V4** |
| **R2** | `applyMembershipGradients(root, name)`: if `root` has a UIGradient carrying attribute `name` (ColorSequence) → set `Color`, `Rotation` (`<name>_Rotation`, default 0), `Enabled = true`; missing / nil name → `Enabled = false`. `AFTER_TEAM_GRADIENT_NAME` without attribute → solid black, no new instance. Return early when the painted name is unchanged (server echoes full state). Old path (one gradient per name) untouched when no gradient carries attributes | `:1518-1537`, call sites `:1837`, `:1889-1895` | ~30 lines |
| **R3** | `applyRelationshipGradients` — same scheme for `UIGradient` / `UIGradientFun` / `UIGradientSingle` | `:787-793`, call `:809-812` | shares R2's helper |
| **R4** | A row may itself be the TextLabel: `setRow` writes `row.Text` when `row:IsA("TextLabel")` (`:513-525`); `setLevelRow` accepts the row as its label (`:974-977`); `getRelationshipStatusLabel` returns the row when it is a TextLabel (`:775-785`) | 3 functions | ~10 lines |
| R5 (level C only) | Badge pool: `02-BadgeGroup` holds `Slot1..4` + the three counter badges by name; badge art as string attributes on `02-BadgeGroup` named after the frame (`01-OwnerCoOwnerBadge = "rbxassetid://…"`); `setBadges` fills slots in `ALL_BADGES` order | `:924-954`, `resetGuiUntilPayload` `:182-190` | ~50 lines |

Untouched on purpose: every row/label/badge **name** (`ALL_BADGES`, `lazyEnsureRow` list `:1636-1647`,
`SpecialTitleRenderer`, `AdminPanelUI` preview), the wrapper name `Frame`, the list sort by Name, the payload.
Nothing server-side reads the template beyond cloning it (`OverheadPremiumBadge.apply` looks for
`RobloxPlusBadge`/`RobloxPremiumBadge`, absent in V4 and V6). No DataStore key, no buyer config key: `GuiType`
already exists in the schema (`ClubKitConfigSchema.luau:468`), and ConfigBootstrap only accepts names that
exist in the engine's `OverheadGuiVariants` (`ConfigBootstrap.luau:406-414`) — so an **old engine given
`GuiType = "V6"` warns and stays on V4**, which is the natural guard against template/engine skew.

Register budget: R0b adds one require to the server `OverheadController` (a controller, not `Main.*`);
R1–R4 are local functions inside `OverheadUI.luau`. Re-check `.\tools\count-locals.ps1` on `OverheadUI.luau`
when building.

## 5. Offline measurements

### Counts

| | V4 | A | **B** | C | C + cuts |
|---|---|---|---|---|---|
| Template instances / head | 106 | 58 | **49** | 44 | 40 |
| UIGradient / head | 18 | 12 | **6** | 6 | 6 |
| TextLabel / head | 13 | 12 | **12** | 12 | 11 |
| Runtime adds / head with an OverheadUI | 14 | 16 | **11** | 11 | 10 |
| `instancesAtN(200)`, k = 60 heads with a UI | 22,040 | 12,560 | **10,460** | 9,460 | 8,600 |
| `instancesAtN(200)`, worst k = 200 | 24,000 | 14,800 | **12,000** | 11,000 | 10,000 |
| Template UIGradients per client at 200 | 3,600 | 2,400 | **1,200** | 1,200 | 1,200 |
| Same on the server (200 clones) | 21,200 | 11,600 | **9,800** | 8,800 | 8,000 |

`instancesAtN(N) = N × template + k × runtimeAdds`. `k` = heads this client built an `OverheadUI` for
(payload received). With the 30-nearest-viewer interest cap, ~30–60 on a packed floor; the worst case
assumes every head. Streaming is off on THE BASIC TEST, so all N heads replicate to every client.

Reference, P4b-client (client builds nametags from a local template for the 40 nearest only, server
replicates none): 40 × (49 + 11) ≈ **2,400** per client, 0 nametag replication.

### Replication bytes per head — rough model

Roblox does not publish per-instance wire sizes, so this is an **uncalibrated order-of-magnitude model**,
per class, instance header + its properties (strings and sequences dominate):

| Class | ≈ bytes | Class | ≈ bytes |
|---|---|---|---|
| BillboardGui | 180 | UIGradient (2–4 keypoints) | 110 |
| Frame | 160 | UIStroke / UIPadding / UIListLayout | 55 |
| TextLabel (FontFace family id, text) | 300 | UIAspectRatioConstraint | 35 |
| ImageLabel (content id) | 190 | UICorner / UIScale | 30 / 25 |
| ColorSequence attribute (name + 2 keypoints) | 60 | number attribute | 25 |

| | V4 | A | B | C |
|---|---|---|---|---|
| ≈ bytes per head | **14.0 KB** | 10.0 KB | **9.5 KB** (incl. 0.7 KB attributes) | 9.0 KB |
| one head rebuilt (respawn / avatar change) → 199 viewers | 2.8 MB | 2.0 MB | **1.9 MB** | 1.8 MB |
| a client joining a full server (199 heads) | 2.8 MB | 2.0 MB | **1.9 MB** | 1.8 MB |

Reading: instances drop 54 %, bytes only ~32 %, because the survivors are the heavy classes (12 TextLabels,
14 ImageLabels). Replication is the argument for P4b-client, not for trimming further. Calibrate the model in
the acceptance run (§8 C4) and replace this table with measured numbers.

## 6. Risks

1. **Buyers who customised V4** (badge art, fonts, text colours, chip/membership/couple gradient colours,
   extra decoration). V6 is a new instance tree; nothing flows over by itself. Mitigation: the Packager
   action ports by name (§7 step 4) and prints what it could not port (extra instances, renamed rows). The
   Elite badge mapping (`07-SupremeMemberBadge` → `07-ELITEMemberBadge`) is explicit. A buyer with heavy
   custom decoration keeps V4 — nothing forces the switch.
2. **Two UIScales on V4's wrapper** (template 0.95 + kit `_OverheadPopScale`). Which one Roblox honours
   decides whether V4 is really drawn at 0.95. Baking 0.95 into the BillboardGui is only right if the 0.95
   was in effect. First build step: read V4's wrapper `AbsoluteSize` in a playtest against the BillboardGui's
   and set V6's size from the measurement, not from the assumption. Pixel check (§8 B2) is the gate.
3. **Property-for-modifier swaps are not always pixel-identical** (UIPadding → Size/Position rounds
   differently; `RelativeYY` vs AR `FitWithinMaxSize` if a buyer's row is narrower than 12 squares).
   Gate: pixel diff against V4 for the same payloads (memory recipe "Verifikasi UI identik per piksel").
4. **CanvasGroup / texture memory.** V4 and V6 have none; a buyer who converts the wrapper to a
   CanvasGroup (for the fade the renderer supports) pays one texture per enabled head — up to 40. Documented as
   "don't" in the upgrade guide; the fade is not worth it.
5. **TextScaled cost.** The BillboardGui is sized in studs, so every camera move changes each enabled
   label's pixel size and TextScaled refits. V6 has 12 TextScaled labels (V4 13) × ≤ 40 enabled heads. Not made
   worse; measured in §8 C3. Do not add labels to V6.
6. **`MaxDistance` 90 vs the cull.** Template value is inert (renderer overwrites). The real ceiling is
   Far = 90 with ≤ 40 enabled heads; at 90 studs a nametag on a phone is a few pixels tall and unreadable,
   which is acceptable only because Medium (48) stays the default. No change proposed.
7. **Mobile readability.** V6 keeps V4's geometry and font sizes; no regression expected. The Separator at
   0.6 height and the chip labels at 0.64 of chip height are the smallest texts — check them on the phone
   emulator (memory: open panels through the icon, not by force).
8. **Engine / template skew.** V6 without R4 would show blank status/level/couple rows. Guarded twice: the
   Packager action refuses on an engine without `OverheadGuiVariants.V6`, and an old engine rejects
   `GuiType = "V6"` in ConfigBootstrap and stays on V4. An engine **downgrade** after the switch lands on V4
   too — hence "keep V4 in the place for at least two releases".
9. **Level C only:** badge-pool overflow (> 4 plain badges at once) silently drops the lowest-priority badge.

## 7. Rollout (Lane B — template / place data)

Release surface per `UPGRADE_PROGRESS.md` "Release surface": the engine half is Lane A (source sync), the
template is Lane B (Packager action + written manual steps, one-way on a live place).

**Stage 0 — engine (Lane A, any later engine release, before the template exists anywhere).** R0–R4 (R5 only
if level C). No visible effect on a V4/V5 place except R1 (fewer instances) and R0b (a missing template now
falls back instead of blanking every nametag). CHANGELOG + `CHANGED_FILES.md` as usual.

**Stage 1 — Packager plugin action "Nametag → Install V6"** (new action in
`tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` / `PackagerPanel.luau`, template shipped inside the plugin
build like other packs):

1. **Precondition:** the place's engine has `Config.OverheadGuiVariants.V6` (i.e. Stage 0 is installed).
   Otherwise refuse with "Update Engine first".
2. **Backup:** save `OverheadGUIMainTemplateV4` (and V5 if present) to a backup RBXM (S7 dry-run + automatic
   backup, the thing that makes Lane B shippable).
3. **Install alongside, never in place:** insert `OverheadGUIMainTemplateV6` into `ReplicatedStorage` next to
   V4. If a V6 already exists, rename it `OverheadGUIMainTemplateV6_backup_<date>` — never overwrite.
   **V4 is never modified or removed by the plugin.**
4. **Port customisations (default on):** by name, from V4/V5 into V6 — badge `Image` + `ScaleType` (with the
   Supreme→ELITE mapping), `FontFace` / `TextColor3` per label name, chip and special-rank gradient colours,
   status/rank background colour (= the V4 row gradient's colour), membership and couple gradient
   `Color`/`Rotation` → attributes (including custom-named membership gradients), image-row size from V5.
   Print a report: ported N, not portable M (with paths).
5. **Do not touch `ClubKitConfig`.** Print the one line to change instead.

**Stage 2 — buyer switches:** plugin **Config** tab → Overhead → `GuiType = "V6"` (or edit the line), save,
publish. `GuiType` is an existing buyer key, so ADR 0001 is untouched: no new key, no fill-forward, the value
is the buyer's own edit.

**How a buyer verifies:**
- Studio Output after Play: no `Template BillboardGui not found`, no fallback warning from R0b.
- Command bar (read-only): `print(#game.ReplicatedStorage.OverheadGUIMainTemplateV6:GetDescendants() + 1)` → 49.
- In Play: own nametag shows name + membership + level; Settings → Name Tag Details → toggle every layer and
  badge on and off; a couple, a title holder and a donor look the same as on V4.

**Why this is one-way for them, and the undo.** The template is place data: Update Engine / source sync cannot
restore it, Studio undo does not survive a publish or a closed session, and any customisation the buyer makes
to V6 afterwards exists only in V6. Servers already running keep their template until they restart (a mixed
period is harmless — nametags are per server). **Undo:** set `GuiType = "V4"` again (V4 is still in the place)
— the next server uses V4. Deleting V6 is optional. If V4 was deleted by hand, re-insert it from the step-2
backup RBXM. Keep V4 in every place for at least two releases after V6 ships.

## 8. Acceptance test

**A. Static (Studio edit, read-only snippet, no playtest).** V6: instances ≤ 50 (B: 49), UIGradient ≤ 6,
TextLabel ≤ 12, CanvasGroup 0, UIStroke 0; every name in the contract list present (`00-DonationLayers`,
`RobuxRankWrapper`, `RupiahRankWrapper`, `00-SpecialStatus`, `01-SpecialTitle`/`SpecialTitleText`,
`02-AddOnCustomImageBadge`/`ChangeableImage`, `02-BadgeGroup` + the 12 `ALL_BADGES` names, `CommunityLogo`,
`03-Level`, `04-SpecialRank`, `08-DisplayNameAndMembership`/`PlayerDisplayName`/`Separator`/`MembershipLevel`,
`09-CoupleDisplayName`); every membership/couple attribute present and of type ColorSequence.

**B. Parity (Studio solo playtest, harness in `.tmp/`, never `src/`).**
1. Client side: V4 and V6 cloned onto two anchored parts, one `OverheadUI` each, the same payload matrix
   applied to both (~40 payloads: each layer on/off, all 12 badges, 5 tiers + AfterTeam + one custom gradient
   name, 3 relationship modes, role chip, donation chips ranked/supporter, image title, generated and preset
   titles). Snapshot per named node: `Visible`, `Text`, effective gradient `Color`/`Rotation`/`Enabled`,
   `AbsoluteSize` ± 1 px. **Pass: 0 differences.**
2. Pixel diff (PrintWindow + C# diff, memory recipe) on 6 representative payloads. **Pass: anti-aliasing
   noise only.**

**C. Performance at 200 (Studio "Local Server + 1 client", crowd-harness extension; not a real 200-player
test).** Server spawns 200 dummy R15 characters and attaches the template through the real `attachGui` path;
payloads reach the client through the real remote. Run V4, then V6, same seed.

| # | Measure (client) | Pass |
|---|---|---|
| C1 | nametag instances (clone descendants + runtime adds) | V6 ≤ 12,000 worst case and ≤ 50 % of V4 |
| C2 | `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)` | V6 ≤ 60 % of V4 |
| C3 | frame time, 40 enabled, 30 s camera orbit: p50/p95 `RenderStepped` dt + MicroProfiler dump | p95 not worse than V4; `OverheadUI` + gradient loop ≤ 1 ms/frame avg (plan) |
| C4 | replication: server rebuilds all 200 heads; client `Stats.DataReceiveKbps` integrated over the storm minus baseline, ÷ 200 | V6 ≤ 75 % of V4 bytes/head (model says 68 %); replaces the §5 model |
| C5 | join a full server: time until 199 heads present | not worse than V4 |

Studio numbers are ratio-only (plugin CPU contamination, memory "Ukur performa via Studio MCP").

**D. Live peak (one buyer, after owner OK).** Client Gui memory tag and FPS from the budget line vs that venue's
previous peak on V4. Pass: Gui memory down ≥ 40 %, FPS not lower.

## 9. Owner decisions (≤ 3)

1. **Target.** Accept "≤ 50 per head, 6 gradients, no feature loss" (level B, ~10,500 per client at 200) and
   restate H14's 8,000 accordingly — or hold 8,000, which means level C + visual cuts (still ~8,600) or
   P4b-client (client-built pool, ~2,400, bigger code change, removes nametag replication). *Recommended: B
   now; P4b-client only if the live peak says client memory or join bandwidth still hurts.*
2. **Name and scope.** `V6` = trimmed **V5** (image row included, hidden), one new template for every venue.
   *Recommended* — `V5` is taken, and two trimmed templates would double the Packager work.
3. **Customisation porting.** Packager ports V4 art/colours/fonts by name and reports the rest
   (*recommended*), or V6 ships with the default look and buyers restyle by hand.

## 10. Not in this document

- Building anything: no kit source, no RBXM, no place change was made (Studio was read-only).
- The Elite/Supreme badge name mismatch on THE BASIC TEST (inventory finding 1) and the dead "Role" Settings
  toggle on V4 (finding 4) are separate from P4b; P4b just uses the code's names.
