# Upgrade v2.2.9 → v2.3.0

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` / `Secrets`

## What's new

- Money ProcessReceipt safety (dedupe after grant, gift consume-after-grant, Robux LB intent-before-Increment, frozen communityId)
- Studio DataStore isolation **on by default** again (`Studio_*` keys in Play) — safer than v2.2.2 live-keys default
- DataStore join-storm relief (deferred LB pre-warm, SharedProfileLoader fold, streak skip)
- Gravity/Ungravity: **all players** + Owner/Leadership gate only
- World VFX memory (single-flight, prewarm, sound cleanup) + longer server effect queue durations
- Loading `enterGameplay` if LoadingScreenUI misses; LB MessagingService cache invalidate; CharacterAdded cleanup

## Breaking / behavior changes

- **Studio Play uses `Studio_*` DataStore keys by default** (reverses v2.2.2 “Studio = live”). Live production data is not written from Studio unless you set `USE_STUDIO_DATASTORE_ISOLATION = false` in kit `Config.luau` (engine — not buyer ClubKitConfig).
- **Gravity/Ungravity** no longer self-float for regular players; staff-only, server-wide.

`ClubKitConfig` / `Secrets` tidak diganti oleh source sync.

## Config notes

- Engine flag: `Config.USE_STUDIO_DATASTORE_ISOLATION` (default `true`)
- New: `WORLD_EFFECT_DURATIONS` / `NUKE_DEFAULT_DURATION` 90s (engine Config)

## QA setelah upgrade

- [ ] Plugin shows kit **2.3.0** after Update Engine
- [ ] Studio Play: boot log shows isolated (`Studio_*`) keys — not live
- [ ] Only Owner/Leadership: `/ungravity` / `/gravity` / Shift+U / Shift+G floats **everyone**
- [ ] Regular player cannot self-float
- [ ] Join ~4 players: no DataStore request-queue flood
- [ ] Robux purchase / gift membership / paid broadcast: retries still work after transient fail
- [ ] Loading finishes → dance/gameplay ready even if LoadingScreenUI absent
- [ ] Nuke/BlackHole overlap: prior VFX cleans up (no stuck Lighting)
