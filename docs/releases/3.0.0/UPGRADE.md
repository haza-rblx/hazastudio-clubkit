# Upgrade v2.12.0 → v3.0.0

**Date:** 2026-10-09

3.0.0 is the first release that needs more than Update Engine. Scripts still come through Update Engine, but the **music panel** and the **event board** need GUI from the 3.0.0 package, which source sync does not touch. Read "Breaking changes" and "Before you start" before you update a live place.

## Breaking changes

- **Music panel GUI replaced.** `06-MusicPlayerGUI` is now the v3 panel. The v2 panel does not work with 3.0 code. Rollback copy: `docs/releases/3.0.0/rollback/06-MusicPlayerGUI_v2.rbxm`.
- **Music is web-only.** The in-game Manage tab is gone. The library is edited in the customer dashboard. On first boot the venue's existing in-game library is imported automatically.
- **Music is four times louder by default.** Fill-forward adds `Music.MaxVolume = 4`, so every venue gets louder music on update. Set it to `1` to keep the old loudness.
- **Image custom titles are off by default.** Fill-forward adds `Features.ImageCustomTitle = false`. If you sell image titles, set it to `true`. It is a paid add-on.
- **Profile likes reset daily.** Fill-forward adds `AvatarContext.DailyLikeReset = true`: each player can like someone once per WIB day, and every like adds +1 to that player's lifetime total. Set `false` for the old one-standing-like rule.
- **Retired config keys** are left in your file and ignored. The boot log names them once: `Features.MusicCatalogSeed`, `Features.MusicReadOnlyLibrary`, `Features.MusicWebLibrary`, `Features.AvatarContextMenuV2`, `Features.DailyQuest`, `DailyQuest`.

## Before you start

1. **Back up** `Hazastudio_ClubKitConfig` and `Hazastudio_ClubKitSecrets`. Update Engine does not replace them, but keep a copy.
2. **Check the venue's VPS (`ApiUrl`) is up.** The music web library, the event board and budget telemetry all talk to it. Music keeps playing from its DataStore copy if the VPS is down.
3. **Do not update a live place's scripts until the 3.0.0 music panel GUI is published** (see Known issues). The v3 scripts need the v3 panel.

## Quick steps

1. **Engine.** Plugin → Settings → Update plugin → **Engine → Update Engine** → Save place. Engine folders are replaced wholesale, so the removed modules (`CoupleUI`, `InventoryDragController`, the old music panel helpers, `MusicCatalogSeeder`) go with them. New config keys are filled into `ClubKitConfig`.
2. **Music GUI (required).** Replace `06-MusicPlayerGUI` with the 3.0.0 v3 panel from the 3.0.0 package.
3. **Event board GUI (required if you run the event board).** `07-MenuGUI` → `EventTab`, `18-EventQuestPopup` and `19-EventReminders` come with the same package.
4. **Back buttons (optional).** Add `BacktoMainMenuButton` to the Profile, Settings and Event tabs of `07-MenuGUI`. Without it those tabs have no back button, as before.
5. **Buyer config.** Review the table below. Set `Music.MaxVolume`, `Features.ImageCustomTitle` and `AntiTamper.ForeignGuiDetect` to what you want.
6. **Old emoji button (optional cleanup).** `09-DonationSystemGUI` may still carry `AddEmojiButton`. It does nothing now. Delete it, or re-import the GUI.
7. **Overhead nametag (optional).** Packager → Install V6 for the trimmed nametag template.
8. Playtest → run the QA list → Publish.

## What's new

- **Music v3.** Web-only library. Request From ID plays once and is never saved to the library. Per-track covers. Track covers drawn by the kit when no image is set (nothing to upload). Sets up to 3 hours long. Live control is its own role privilege, `musicControl`.
- **Event board.** An **Event** tab in the top menu with announcements and quests, authored in the dashboard. Quests can have up to 5 milestones with Robux or manual rewards and optional quotas. Countdown posts and reminders (ADR 0019).
- **Accent theme.** Settings → Appearance offers 14 Workshop colours. `Branding.DefaultAccent` sets the venue default.
- **UI motion pass.** One motion vocabulary across panels, slower and smoother by design.
- **Preferences restructure.** Bloom and Player Particles toggles, new section order.
- **Islands.** Notification, toast, queue and vote islands replace several popups.
- **Free Title event from the topbar.** `FreeTitleEvent.Trigger = "Overlay" | "Topbar" | "Both"`.
- **Leaderboards.** Level, Streak and Couple boards show live data.
- **Top menu.** Admin Panel and Music Player rows.
- **Auto Dance and Lead Dance topbar pills.** Each can be switched off (`Features.AutoDance`, `Features.LeadDanceTopbar`).
- **Dance panel.** Speed slider and visual polish.
- **Production hardening and client footprint.** Write discipline, HTTP budget, leaderboard cache v2, batched overhead, fewer client instances. No buyer action.
- **Foreign GUI report.** Log-only. When a GUI that was not in the place appears, the report goes to the Hazastudio Discord, with the GUI and script names.
- **Off by default:** onboarding modal (`Config.Onboarding.ENABLED`) and cinematic loading (`Config.Loading.STYLE`). Nothing to do.

## Config changes

Fill-forward adds every key below to your `ClubKitConfig` on update. It never overwrites a key you already have.

| Key | 3.0.0 default | What it does | Effect on an existing file |
|-----|---------------|--------------|----------------------------|
| `Music.MaxVolume` | `4` | Sound volume at the Settings slider's 100% (1 = old loudness) | **Added as 4: music is louder for everyone** until you set `1` |
| `Music.PlayOnceRequest` | `"everyone"` | Who may play a Request From ID once: `everyone`, `control`, `off` | Added |
| `Features.ImageCustomTitle` | `false` | Image custom titles, a paid add-on | **Added as false: image titles stop** until you set `true` |
| `Features.AutoDance` | `true` | Auto topbar pill | Added: the pill appears |
| `Features.LeadDanceTopbar` | `true` | Lead Dance topbar pill | Added |
| `Features.WutwutDance` | `true` on new installs | Same-emote click restarts the dance | Your existing value is kept |
| `Branding.DefaultAccent` | `"multicolor"` | Venue default accent | Added |
| `FreeTitleEvent.Trigger` / `TopbarIcon` | `"Overlay"` / `""` | Where the Free Title door sits; topbar icon | Added |
| `AvatarContext.DailyLikeReset` | `true` | Likes once per WIB day, each adds to the lifetime total | **Added: behaviour change** (`false` = old rule) |
| `AvatarGuard` (section) | enabled | Trims oversized accessories | Added, same behaviour as before |
| `AntiTamper` (section) | `ForeignGuiDetect = true`, 20 s grace, allow list | Foreign GUI report (log-only) | Added; reports go to the Hazastudio Discord |
| `Telemetry.Enabled` | `true` | Budget counts to the VPS every 15 min (no player ids) | Added |
| `Donation.ReliabilityV2` | `true` on new installs | Batched donation acks | Your existing value is kept |
| `Loading.ArtworkImage` / `ArtworkVideo` | `""` | Cinematic loading background (only with `STYLE = "cinematic"`) | Added, empty |
| `ExternalAdmin.Perks` (section) | enabled | Fly for VVIP+, smite for top tier (3 per week) | Added. Only matters with the Kohl's bridge pack |
| `musicControl` (role privilege) | omitted = follows `musicManage` | Live music control: DJ mode, effects, soundboard, skip | No change for existing roles |

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## Known issues

- **Music panel GUI (3.0.0 `06-MusicPlayerGUI`) is not published yet.** Until it is, the v2 panel is the only one buyers have, and the 3.0.0 scripts will not drive it. The track-cover stack (`BackdropNear`, `BackdropFar` and their `CoverImage` children) exists only in the owner's reference GUI until it is saved into the template.
- **Live production test not done.** The 50 → 100 → 200 player network and DataStore run is still owed. The Studio test cannot replace it.
- **Not yet verified in playtest:** two-player music pass, reduced-motion manual run, phone-emulator pass, and the volume at `MaxVolume = 4` on a real device.
- **Foreign GUI report needs migration `0024` on the VPS.** Until it is live, reports arrive without the GUI and script names.
- **Onboarding modal and cinematic loading** are built but off. No owner verdict yet.

## QA after upgrade

- [ ] No kit errors at boot. Retired keys in your file appear once in the boot log.
- [ ] The v3 music panel opens, a track plays, and the Settings slider at 100% matches your `Music.MaxVolume`.
- [ ] Topbar shows the Auto and Lead Dance pills (if enabled). Auto turns on and off.
- [ ] Settings → Appearance shows 14 accent colours, and the picked one survives a rejoin.
- [ ] Profile, Settings and Event tabs open. Back buttons return to the top menu (if added).
- [ ] The Event tab shows dashboard announcements and quests (if the venue has any).
- [ ] A profile like counts once per WIB day.
- [ ] If you sell image titles: `Features.ImageCustomTitle = true`, then set one.

## Rollback

1. Re-apply the 2.12.0 engine through Update Engine.
2. Put back the v2 music panel from `docs/releases/3.0.0/rollback/06-MusicPlayerGUI_v2.rbxm`.

The new DataStore keys (`CoupleLeaderboard_v1`, `ClubKitLeaderboardCache_v2`, the `claims` map in `VenueQuestProgress_v1`, the `accent` field in `Settings_v1`) are additive. The 2.12.0 engine ignores them.
