# Foreign Avatar Menu + Carry — study notes (NIGHT ZONE, 2026-10-20)

Goal: the client prefers the other dev's avatar menu feel (smoothness/transitions). Study it for the kit, then remove it from NZ. **Nothing removed yet.**

## Inventory (live NZ place, not in repo)

| Piece | Path | Readable? |
|---|---|---|
| Menu GUI | `StarterGui.AvatarMenu` | yes (layout) |
| Menu client logic | `StarterGui.AvatarMenu.Assets.Scripts.AvatarMenu` (LocalScript, 393k) | **obfuscated** (`--Sstudio[Protect]`) |
| Helpers | `…Assets.Scripts.TargetUtil`, `…BuyAllSummary`, `…CurrentlyWearing.LocalScript` | yes |
| Menu server | `ServerScriptService.AvatarMenu` (325k) | **obfuscated** |
| Gift VIP server | `ServerScriptService.CharacterMenu` | yes; needs `RS.TitleSystem.RolesConfig` (missing in NZ, so Give VIP always says "not available") |
| Profile helper | `ReplicatedStorage.ProfileFetcher` → `RS.Events.GetProfileInfo` | yes |
| Remotes | `RS.Events`: playerData, RequestPrivateChat, LikeUser, GetWearingAssets, GetProfileInfo, GetLikeInfo | — |
| Like plumbing | `ServerStorage.LikeGranted`, `ServerStorage.LikeNotify`; `SPS.TopLikes` + `SSS.TopLikesServer` (both disabled) | — |
| Carry GUI | `StarterGui.Carry` (Carryhandler, CarryPlay; ContextButtonAdder disabled) | yes |
| Carry shared | `RS.CarryReplic` (CarryWeld, remotes, 5 CarryChoices w/ KeyframeSequences) | yes |
| Carry server | `ServerScriptService.CarryMenu` (132k) | **obfuscated**, uses `getfenv` |

Kit state in NZ: `Features.AvatarContextMenu = false`, `Features.Carry = false` — so the foreign stack is the only live ACM/carry. Kit `AvatarContextMenu` + `08-CarryGUI` ScreenGuis are still present (that is the "mix").

## Menu layout (static)

- `Container` 288×288, AnchorPoint (0.5,1), Pos {0.5,0},{0.619,100}, UIScale 0.9, corner 16, bg #3F3F3F @0.08, vertical gradient #808080→#000, `ClipsDescendants`.
- Animated border: UIStroke 2px white + UIGradient (black→white→black, rot −44) driven by a tiny LocalScript (rotating shine). Same trick on display name and ItemMenu.
- Content = one vertical `ScrollingFrame` (`character`), SortOrder=Name: `aAvatar` (full-bleed avatar image + community banner, name/username overlaid bottom-left, stats row) → `bStatus` (Bio) → `buttonFramesscrl`.
- Buttons: full-width 40px rows, #2E2E2E @0.875, corner 4, GothamMedium 20 — Coordinate Dances, Carry Choices, Add Connection, Private Chat, Hide Avatar, Give VIP; plus "Currently wearing" carousel (72×64 tiles, ‹ › pagers, Buy all).
- `ItemMenu` 264×264 sub-card (item preview + Buy) and a full-screen `BuyAllOverlay` summary.
- Like (🤍 + count) top-left, Close (two 20×2 bars = X) top-right.

## Runtime capture (2-player playtest, 2026-10-20)

Method: a per-frame diff recorder on Player2's `PlayerGui.AvatarMenu` (every GUI property), plus camera, Lighting post-effects, Highlight, Text and Image; real mouse input sent through `Roblox_Studio.user_mouse_input`.

Result: **the panel itself has no animation.** The feel comes from responsiveness, not motion:

| Event | What happens | Timing |
|---|---|---|
| Hover over avatar | nothing (no highlight, no cursor change) | — |
| Mouse **down** on avatar | `Highlight` (Fill 1 = none, Outline white) parented under the GUI, Adornee = target; outline fades 0→visible | HL +80 ms, fade ≈0.3 s |
| (same click) | `Container.Visible = true` + `ClickOutsideDetector.Visible = true`, **instant**, no tween on Position/Size/UIScale/transparency | +260 ms after mouse down, **before mouse up** |
| Mouse down outside / Close | `Container.Visible = false` instantly; outline fades out, Highlight destroyed | hide +120 ms; fade ≈0.2 s; destroy +430 ms |
| Scroll card | native ScrollingFrame smoothing (100px steps eased) | — |
| Camera / Blur / DoF / FOV | **untouched** | — |

- Fires on **InputBegan (down)**, not on click-release. That is the main reason it feels snappy.
- Card is fixed (bottom-centre, does not follow the target). Avatar = `rbxthumb://type=Avatar&w=420&h=420` (static full-body thumbnail, not a ViewportFrame).
- Only continuous motion: the 12 s linear UIGradient rotation on the border stroke (shine).
- Not verified in Studio: ItemMenu/BuyAll transitions (test avatars have userId −1, so the wearing list stays as template), Sync/Carry flows.

Takeaways for kit ACM: open on press, not release; skip the open/close zoom (or keep it ≤0.15 s); white outline Highlight fade on the target; click-outside-to-close; one compact scrolling card.

## Dance investigation (no deletes)

- Old external dance (`ExternalDance`: DanceMenu, LeadDancePanelClient, LeadDanceRegistry, Animations) is already archived in `ServerStorage._Backup_PreKit3_2026-10-19` — inert.
- **Leftover live remotes** in `RS.Events`: RequestSync, UpdateAnimation, ToggleFavorite, RequestFavorites, AdjustSpeed. No readable script listens to them (the kit uses its own remotes). Only reader: foreign `CarryWeld` (looks up UpdateAnimation/RequestSync). The foreign menu's "Coordinate Dances" button likely fires `RequestSync` → probably a dead button now (unconfirmed; client is obfuscated).
- **A foreign dance backend is still alive at runtime.** During playtest, `RS.Events` gains 7 more remotes: UpdateSyncStatus, UpdateSpeed, DanceShutdown, ResetCamera, TransferLead, CheckWhitelist, SyncDanceClient. No readable script (2378 searched) and no kit file mentions them, so they come from an obfuscated server script (`SSS.AvatarMenu` or `SSS.CarryMenu`). Clicking "Sync Dances" fired nothing on any `RS.Events` RemoteEvent (it may use a RemoteFunction, which wasn't hooked). To confirm which script it is: disable one obfuscated script at a time in a test copy.
- `RS.Emotes` is used by the kit (`AnimationLoader`) — keep. `IconGroup.DancePanel*` is the kit's. `ServerStorage.Tools.LEAD DANCE` = role tool bundle, not a dance system. Kohl's Admin emote commands = admin, separate.
