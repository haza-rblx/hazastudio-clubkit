# SyncBhms dance system — feel study vs kit (2026-10-20)

Source: `Workspace.SyncBhms` in NIGHT ZONE (added by owner for study; fully readable, not obfuscated). Active copies: `Main1` (server), `danceDraging1` (client); `Main`/`danceDraging` are disabled duplicates.

## How SyncBhms plays a dance (server-authoritative, like the kit)

Flow: client `AnimationStartRF:InvokeServer(anim, true, speed)` → `AnimationHandler.executeAnimation` →
1. same dance already playing → `Stop(0.5)` (click = toggle off)
2. `haltOtherDances` → every dance/emote track `Stop(0.5)`
3. `animator:LoadAnimation(anim)` **fresh track each time** (never cached, never destroyed), `TimePosition = 0`, `Play(0.5)`, then `AdjustSpeed(speed)`
4. **No `Priority` override** → the uploaded asset's own priority. No `Looped` override.

`Config.FadingTime = 0.5` is used for everything: play, stop, switch, sync-join.

## Side-by-side

| Aspect | SyncBhms | Kit (NZ live values) |
|---|---|---|
| Fade idle→dance | 0.5 | `FADE_IN` 0.45 |
| Fade dance→idle | 0.5 | `FADE_OUT` 0.45 |
| Switch A→B | A `Stop(0.5)` + B `Play(0.5)` crossfade | `prepareDanceCrossfade` 0.45/0.45 crossfade |
| Sync-join fade | 0.5, `TimePosition = leader` instantly | `SYNC_JOIN_FADE_IN` 0.4 + phase snap (waits for Length>0) |
| Priority | asset's own (not forced) | **forced `Action4`** |
| Track lifecycle | new `LoadAnimation` per play | cached `getOrCreateTrack`, AdjustWeight back if mid-fade |
| Client preload | **all** dance+emote Animations, `PreloadAsync` on join (background) | `DanceWarmupService` with `DANCE_PRELOAD_FULL_CATALOG = true` in NZ → all 150, batched + device-aware (the 32 cap applies only when that flag is off). Equivalent. |
| Server preload | `PreloadAsync` all at boot, sets `StoredAnimations@Loaded` | track prewarm max 8 |
| Walk while dancing | untouched | `DANCE_WALK_SPEED` 16 |
| Follower drift fix | Heartbeat, but only on leader state change; snap if >0.3 s | kit SyncService phase logic |
| Auto-sync on join | after 5 s, auto-syncs to the first active dancer | — |

Fade numbers are almost the same (0.5 vs 0.45), so the timing alone doesn't explain the feel. Real candidates:
1. **Priority**: the asset priority (likely Action/Core) blends with Animate (walk/idle/tool) the way the animator authored it; Action4 overrides everything.
2. ~~Preload all on join~~: ruled out, NZ already preloads the full catalog. Preload is ContentProvider only and creates no instances; instance growth comes from `LoadAnimation` tracks.
3. **Fresh track + `TimePosition = 0` every play**: every switch starts clean from frame 0.

To confirm 1–3: runtime A/B that records `WeightCurrent`/`TimePosition`/`Priority` per frame during play → switch → stop, SyncBhms vs kit, same dance IDs.

## NZ experiment (2026-10-20, live place only)

The client plays breakbeat; the dances themselves change moves quickly, so 0.45 s fades (≈1 beat at 140 BPM) feel mushy. NZ `ClubKitConfig.Sync` was lowered to FadeIn/FadeOut 0.25, SwitchFadeIn/Out 0.2, SyncJoinFade 0.25, SwitchInputCooldown 0.2; verified at runtime as `Config.Sync.*`. Backup: `ServerStorage._Backup_SnapFade_2026-10-20.ClubKitConfig`. Engine defaults unchanged. If the client approves, consider a documented "snappy" preset in the template instead of changing the defaults.

## Auto-dance / beat mode (`/dance [speed]`, `/ad`)

- Random favourite (or any) dance every **5 s** via `playOneDance` (same 0.5 crossfade).
- Beat mode: client samples `SoundService.Sound.PlaybackLoudness` 6× per 0.05 s, every 0.5 s → speed buckets <300: 0.3, <400: 0.5, <600: 1.0, <750: 1.5, else 2.0. Drops require 2 consecutive low readings (hysteresis). Quiet zone (<100) forces "N.anti gravity" dance.
- Speed changes are applied with `AdjustSpeed` on all playing tracks (instant, no ramp).

## Panel UI motion (danceDraging1)

- List load: each button slides in from x −50 with a BG fade, `0.4 s Quart Out`, staggered **0.02 s per item**.
- Hover: BG colour `0.2 s Quart Out` + highlight bar fade 0.2.
- Press: shrink `0.1 s Quart Out` → release `0.12 s Back Out`.
- Tabs: colour/transparency tween 0.2. Auto button colour 0.2.

## Caveats

- Unbounded `LoadAnimation` per play (no Destroy) → track leak toward the 64-track Animator limit; the kit guards this (`MAX_USER_TRACKS`).
- Uses `_G` (autoDanceStates/autoDanceFunctions), `Remotes2`, `EventsACMS`, `StoredAnimations`, DataStore `FavoritedAnimations`. None of it is installed in NZ.
- **Server Scripts in `Workspace` run.** `Main1`, `WarningSystems` and `PersistentAnimations` are enabled and just infinite-yield on `RS.SyncSettings`/`Remotes2`. Harmless, but move the folder to ServerStorage before publishing.
