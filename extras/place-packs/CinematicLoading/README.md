# CinematicLoading — place-specific pack (not Club Kit engine)

Cinematic loading screen ported from the pre-kit Hierapolis Theatre place: camera fly-through
over `Workspace.CameraParts`, story text, loading bar, Skip, and a High / Balanced /
Performance graphics picker. Runs **instead of** the kit loading screen for one place owner.
Not part of Rojo `default.project.json`, not part of Update Engine, not in the buyer changelog.

## Folder contents

| Path | Purpose |
|------|---------|
| `CinematicLoadingUI.rbxm` | Export of the `LoadingUI` ScreenGui (MainFrame, Graphics buttons, Bar, Skip, Click/Hover SFX) |
| `bridge/CinematicLoading.client.luau` | LocalScript source for `ReplicatedFirst.CinematicLoading` — the ported controller, place settings at the top (`SETTINGS`) |
| `README.md` | This guide |

## How it cooperates with the kit (engine contract, kit ≥ 2.10.0 + unreleased `ClientBoot` attributes)

`Main.client` writes three attributes on `Players.LocalPlayer` (names in `Config.ClientBoot`):

| Attribute | Written by | Meaning |
|---|---|---|
| `ClubKitBootProgress` (0..1) | kit | fraction of interactive client boot tasks done — drives the bar |
| `ClubKitBootSettled` (true) | kit | interactive boot finished — bar may reach 100 % |
| `ClubKitGameplayReady` (true) | kit | gameplay entered (join prompt / greetings fired) |
| `ClubKitExternalLoading` (bool) | **pack** | `true` while this screen is up; the kit holds `enterGameplay` until it is `false` (safety-net timeout `EXTERNAL_LOADING_TIMEOUT`, 300 s) |

The pack refuses to run unless `ClubKitConfig.Features.LoadingScreen == false` (two loading
screens would fight over PlayerGui / CoreGui). It also skips itself on the kit's AFK auto-rejoin.

## Studio setup (place owner)

1. **Config** — in `ClubKitConfig.Features`:
   ```lua
   LoadingScreen = false, -- kit loading screen off; CinematicLoading pack owns boot
   ```
2. Insert `CinematicLoadingUI.rbxm` → you get a `LoadingUI` ScreenGui. Create a **LocalScript**
   `ReplicatedFirst.CinematicLoading`, paste `bridge/CinematicLoading.client.luau` as its
   Source, and parent `LoadingUI` **under that LocalScript** (the script does `script.LoadingUI`).
3. Make sure `Workspace.CameraParts/Camera1`, `Camera2`, `Camera3` exist with BaseParts named
   `Cam1`, `Cam2`, … (sorted by name). Missing folder = the screen still works, just no fly-through.
4. Edit `SETTINGS` at the top of the script: `PresentedBy`, `WelcomeMessage`, `Story`, `Tips`,
   `LoadingMusicId`, `MaxWait`. `GameIcon` falls back to `ClubKitConfig.Branding.LogoImage` when
   the template image is blank.
5. Playtest: bar should track the kit boot (not a fixed timer), Skip appears at 45 %, the
   graphics menu appears only after the kit settled, and the kit's Join Community prompt /
   join greeting show **after** a preset is picked.

## Mutually exclusive

- `Features.LoadingScreen = false` → kit `LoadingBootstrap` removes the default Roblox loading
  screen immediately and `Main.client` boots without its own overlay; this pack draws the screen.
- `Features.LoadingScreen = true` → pack no-ops (warns once); kit loading screen active.

## Maintenance

- This pack is **custom**; bugs in it are not universal kit bugs.
- The graphics picker mutates `Lighting` / `MaterialService` / `CastShadow` on the client only.
- CoreGui is restored per type to its pre-loading state (the kit hotbar keeps Backpack off).
