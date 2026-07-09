# HANDOVER — Club Kit v1.3 Audit & Fixes

**Date:** 2026-06-15 (review pass 2026-07-07, donation effects 2026-07-08)  
**Codebase root:** `C:\Users\haza\Documents\Pull Studio The Basic Club Kit v1.3`  
**Rojo sync:** `src/` → `default.project.json`  
**Tooling:** `aftman.toml` (stylua, selene, rojo) — no Luau linter/typechecker CLI; typechecking via `--!strict` in Studio.

### Changelog (v1.3 handover)

| Date | Area | Summary |
|------|------|---------|
| 2026-06-15 | Audit C1–C6, H1–H13 | Critical/high severity fixes (data loss, leaks, abuse) |
| 2026-07-07 | Client lifecycle | `OnClientEvent` tracking, Carry/Settings cleanup, validate-handover paths |
| **2026-07-08** | **Donation effects** | Pisah `AuraTiers` + `WorldEffectTiers`; resolver shared; Robux = aura only; test commands `/testcash` + `/testrobux` |
| **2026-07-09** | **Provider preset + cash pipeline** | `Donation.Provider` (`bagibagi`/`saweria`); `DonationCash` feature flag; generic cash commands; `tools/OneTimeLeaderboardSeeder/` |
| **2026-07-09** | **Test commands** | `/testcash` & `/testrobux` = preview only (no persist); persist via `/addcash`, `/setrobux`, `/donatecash` |

Buyer-facing setup: [`CLUB_KIT_SETUP.md`](CLUB_KIT_SETUP.md) · HTML guide: [`docs/index.html`](docs/index.html) · QA matrix: [`QA_CHECKLIST.md`](QA_CHECKLIST.md) §5.6a–5.6h

---

## 1. Project Structure

```
src/
├── ReplicatedStorage/Hazastudio_ClubKit/Shared/
│   ├── Constants/     (Config.luau, etc.)
│   ├── Domains/
│   ├── Modules/
│   └── Utils/         (Cache, EventPool, BudgetGate, Result, EventBus, TTLSet, DonationEffectTierResolver, etc.)
├── ServerScriptService/Hazastudio_ClubKit/Server/
│   ├── Controllers/   (SettingsController, etc.)
│   ├── Repositories/  (SettingsRepository, FavoritesRepository, GiftPendingRepository, etc.)
│   ├── Services/      (SyncService, MusicService, CoupleService, OverheadService, etc.)
│   ├── Modules/       (BackgroundJobScheduler, DeltaCompressor, CrossServerCache, etc.)
│   └── Main.server    (server bootstrap + connection wiring)
├── StarterPlayerScripts/Hazastudio_ClubKit/Client/
│   ├── Controllers/   (DonationController, MusicPlayerController, etc.)
│   ├── Utils/         (ClientHttpApi, etc.)
│   ├── UI/
│   ├── Effects/       (EffectDonate, etc.)
│   └── Main.client    (client bootstrap + lifecycle)
└── StarterPack/, StarterCharacterScripts/, etc.
```

---

## 2. Critical Fixes Completed (C1–C6)

### C1 — Data Loss: SettingsService load gate
- **Files:** `SettingsService`, `SettingsController`, `FavoritesRepository`, `MusicFavoritesRepository`
- **Fix:** `loadedByUserId` gate prevents save before first load. `SettingsController.fireSyncWithRetry` uses backoff delays `{0,1,3,8}`. Repos expose `_loaded` flag; `save`/`addTrack`/`removeTrack`/`flushAll` early-return if not loaded.

### C2 — DataStore blind overwrite → last-writer-wins merge
- **File:** `MusicRepository._setAsync`
- **Fix:** Rewritten to merge by `syncRevision` inside `UpdateAsync` callback instead of blind `SetAsync`.

### C3 — Cache memory leak
- **File:** `ReplicatedStorage/Shared/Utils/Cache.luau`
- **Fix:** Full rewrite. Factory `Cache.new()` + backward-compatible module singleton. `_cleanupThread` cancellable via `Cache.destroy()` (wired to `Main.server script.Destroying`).

### C4 — OverheadService memory leak on player removal
- **File:** `OverheadService`
- **Fix:** `onPlayerRemoving` clears `cashDonatedCache`, `rankResolutionScheduled`, `inFlight`. `scheduleRankResolution` resets flag at end of `task.delay` callback.

### C5 — Main.server connection leak + shutdown cleanup
- **File:** `Main.server`
- **Fix:** `Cleaner` + `Cache` requires added. `connectionCleaner:add()` wraps all `Players.PlayerAdded`/`PlayerRemoving` connections (including Carry). `script.Destroying` calls `connectionCleaner:clean()`, `Cache.destroy()`, `_musicService:destroy()`, `syncService:destroy()`. `overheadService:onPlayerRemoving(player)` + `coupleService:cancelPendingFrom(player.UserId)` wired into PlayerRemoving handler. Server `SettingsController` tracks connections + `destroy()` via `trackLifecycle`.

### C6 — Secrets exposure
- **File:** `Secrets.luau`
- **Fix:** Live secrets cleared to `""` (deployer fills after insert).

---

## 3. High Severity Fixes Completed (H1–H13)

### H1 — TOCTOU race in GiftPendingRepository
- **File:** `GiftPendingRepository.consume`
- **Fix:** Single `UpdateAsync` with per-invocation capture (clear on `old=nil`) instead of `GetAsync→validate→RemoveAsync`.

### H2 — BindToClose timeout risk
- **File:** `Main.server`
- **Fix:** Repo `flushAll` calls now parallel via `task.spawn` with `done/total` counter, bounded 25s.

### H3 — No autosave on server shutdown
- **File:** `Main.server`
- **Fix:** `task.spawn` loop every 60s flushes dirty `levelService`, `settingsService`, `syncFavoritesRepo`, `musicFavoritesRepo`. `autosaveActive` flag cancelled on Destroying/BindToClose.

### H5 — MusicService memory leak
- **File:** `MusicService`
- **Fix:** `service:destroy()` cancels `_pollThread`, disconnects `_playerRemovingConn`, unsubscribes `_eventBusUnsub` via `pcall`, destroys all sessions, clears `playerZone`/`rankCache`/`roleCache`. `_musicService` hoisted to Main.server module level. `_eventBusUnsub = eventBus:on(...)` return value captured.

### H6 — SyncService scavenge leak
- **File:** `SyncService`
- **Fix:** `destroy()` sets `_scavengeActive = false` + `task.cancel(_scavengeThread)`.

### H7 — Unregistered background task
- **File:** `Main.server`
- **Fix:** Bare `task.spawn` HttpApiCounter snapshot → converted to `backgroundJobScheduler:register`.

### H8 — CoupleService retry spin on shutdown
- **File:** `CoupleService`
- **Fix:** `_destroyed` flag checked in `rollbackCoupleAsync`/`clearPartnerCoupleAsync` retry loops. `service:destroy()` sets `_destroyed = true`. `coupleService:cancelPendingFrom(player.UserId)` wired in Main.server PlayerRemoving.

### H9 — EffectDonate meteor infinite loop
- **Files:** `EffectDonate` (BlackHole/Blossom/GreenHammer/LocalNuke)
- **Fix:** `meteorStartTime = tick()` + 90s deadline `break` in meteor `while` loop. `pcall(...)` wrap on `OnClientEvent` handler body (all 4 effect files).

### H10 — DonationController network fan-out
- **File:** `DonationController.broadcastWorkspaceLeaderboards`
- **Fix:** 3s debounce on network fan-out with trailing `task.delay` fire to coalesce burst top-3 shifts.

### H11 — MusicService non-audio asset injection
- **File:** `MusicService.resolveOrCreateTrackForAsset`
- **Fix:** Verify `productInfo.AssetTypeId == 70` (Audio) after `GetProductInfoAsync`. Reject non-audio assets with `return false, "asset_not_audio"`.

### H12 — SignServer abuse
- **File:** `SignServer`
- **Fix:** `type(letters) ~= "string"` + `#letters > 64` rejection. `RateLimiter` per UserId.

### H13 — RopeServer abuse
- **File:** `RopeServer`
- **Fix:** Assert `_plr.Character == tool.Parent`. `RateLimiter` per UserId.

---

## 4. Medium Severity Fixes Completed

### PaidBroadcastController data loss
- **File:** `PaidBroadcastController`
- **Fix:** `pendingPaid[userId] = nil` moved AFTER successful `fireAll` (prevents permanent loss on transient failure).

### RoleToolService spam
- **File:** `RoleToolService`
- **Fix:** Per-UserId 2s debounce on `requestRemote.OnServerEvent`.

### GlowStick dual-color cooldown
- **Files:** 20× `Script.server.luau` (GlowStick tool)
- **Fix:** `onDualColor` gets same `colorCooldown` debounce as `SetColor`.

### MusicSession destroy coverage
- **File:** `MusicSession`
- **Fix:** Destroy covered by `MusicService:destroy()`.

### AvatarLikeRepository deadlock risk
- **File:** `AvatarLikeRepository.getSummary`
- **Fix:** Bare `BindableEvent:Wait()` → 0.1s polling loop with 10s timeout.

### AvatarPrewarmShared leak
- **File:** `AvatarPrewarmShared`
- **Fix:** `destroy()` method added (destroys pool, nils singleton). Wired to `Main.client script.Destroying`.

### Main.client connection tracking
- **File:** `Main.client`
- **Fix:** `AvatarPrewarmShared` require added. `CharacterAdded:Connect(attachToCharacter)` tracked via `table.insert(_clientConnections, ...)`.

### MusicPlayerController incident monitor leak
- **File:** `MusicPlayerController`
- **Fix:** `while true do` → `while not self._destroyed do`. Thread captured as `self._incidentThread`. `destroy()` sets `self._destroyed = true` + `task.cancel(self._incidentThread)`.

---

## 5. Remaining Work

### 5.1 — Client `OnClientEvent:Connect` lifecycle tracking ✅ DONE (2026-07-07)

All previously bare `OnClientEvent:Connect` handlers are now tracked via `self._connections` / `trackConnection()` / module-level `_connections` + `destroy()`, and registered in `Main.client` through `trackClientLifecycle()` so `clientLifecycle:destroyAll()` disconnects them on hot-reload.

**Pattern used:**
1. Class/factory modules: `_connections` table + `destroy()` method.
2. Flat `{ init, destroy }` modules: module-level `_connections` + `destroy` export.
3. EffectDonate `.local.luau` scripts: connection stored + `script.Destroying` disconnect.
4. `Main.client`: `trackClientLifecycle(name, module)` before/around `init()`.

**Still intentionally untracked (already had teardown):**
- `MusicPlayerController` (`_trackConnection` + `destroy()`)
- `SyncController` (`self.connections` + `destroy()`)
- `StickerController`, `CarryController`, `HotbarInventoryService` (`_track` / `track`)
- `NukeEffectController` (`destroy()` — disabled in Main.client; EffectDonate handles nuke VFX)

### 5.2 — Review-pass fixes (2026-07-07) ✅ DONE

| Fix | File(s) |
|-----|---------|
| Carry `PlayerAdded`/`PlayerRemoving` wrapped in `connectionCleaner` | `Main.server` |
| Server `SettingsController` connection tracking + `trackLifecycle` | `SettingsController`, `Main.server` |
| `Config.HttpApi.ENABLED` reset to `false` (safe default) | `Config.luau` |
| `validate-handover.sh` paths corrected to `src/` tree | `tools/validate-handover.sh` |

### 5.3 — User test screenshots (unreadable)

Two screenshots were provided but the model cannot read image files:
- `C:\Users\haza\Desktop\test1.png`
- `C:\Users\haza\Desktop\test2.png`

**Action needed:** User should provide text content from these screenshots (error messages, test results, flame graphs, etc.) to correlate with audit findings.

---

## 6. Validate Handover

**QA manual:** see [`QA_CHECKLIST.md`](QA_CHECKLIST.md) for Studio/staging test matrix.

```bash
./tools/validate-handover.sh           # full check
./tools/validate-handover.sh --quiet   # summary only
./tools/validate-handover.sh --json    # machine-readable
```

The script checks:
1. stylua formatting
2. selene linting
3. rojo build
4. HttpApi counter sites (18 sites, 17 unique buckets)
5. HttpApi wrapper migration (9 server, 3 client call sites)
6. Config toggles (default OFF = safe)
7. Phase 1 quick wins (S1_SHORTCIRCUIT, S2_DEBOUNCE_MS, RANK_CACHE_TTL, etc.)

---

## 7. Key Patterns & Conventions

| Pattern | Description |
|---------|-------------|
| `Cleaner` | Maid-like destructor; `cleaner:add(instance)` tracks instances for cleanup |
| `TTLSet` | Set with per-entry TTL expiration |
| `ObjectPool` | Pooled instances for reuse (e.g., ParticleEmitters) |
| `BudgetGate` | Throttles operations when MemoryBudget exceeded |
| `Result.withRetry` | 3 attempts, backoff 2/4/8s + jitter |
| `NetworkFlushScheduler` | Coalesces NetworkServer flush calls |
| `DeltaCompressor` | Minimizes DataStore payload via delta encoding |
| `CrossServerCache` | MessagingService-backed cross-server cache |
| `MemoryStoreCache` | MemoryStore-backed fast cache |
| `BackgroundJobScheduler` | Registered background jobs with budget awareness |
| `EventBus` | Returns `() -> ()` unsubscribe function |
| `trackLifecycle` / `trackClientLifecycle` | Server/client module teardown registration |

---

## 8. Deployer Notes

- **Secrets:** `Secrets.luau` has live secrets blanked (`""`). Deployer must fill after Rojo insert.
- **Config toggles:** All default OFF. Toggle ON in Command Bar for production:
  - `HttpApiTelemetry.Enable()` (sets `Config.HttpApi.COUNTERS_ENABLED = true`)
  - `HttpApi.Enable()` (sets `Config.HttpApi.ENABLED = true` — only after Phase 2.6 parallel-run verification)
- **Validate before publish:** Run `./tools/validate-handover.sh` and ensure 0 failures.

---

## 9. Donation Effects Separation (2026-07-08)

Pemisahan config & runtime untuk **aura per-player** vs **world VFX global**. Robux donation tidak lagi memicu Nuke/Smite/BlackHole.

### 9.1 — Apa yang berubah

| Sebelum | Sesudah |
|---------|---------|
| Tier Robux & world VFX tercampur / naming tidak konsisten | Dua tabel config eksplisit: `AuraTiers` + `WorldEffectTiers` |
| Resolver tersebar di service | `DonationEffectTierResolver.luau` — satu sumber untuk aura (Robux/IDR) & world (IDR) |
| Satu command test `/testdonate` | `/testcash` (cash path) + `/testrobux` (Robux path); `/testsaweria` & `/testdonate` = deprecated alias |
| Robux bisa ikut world VFX | **Robux = aura only** — world VFX hanya Bagi-Bagi/Saweria |

### 9.2 — Behavior matrix

| Sumber donasi | Aura karakter | World VFX (Nuke / Smite / BlackHole) | Tier config |
|---------------|---------------|--------------------------------------|-------------|
| **Robux** | Ya | **Tidak** | `AuraTiers` — match `min` (Robux), highest wins |
| **Bagi-Bagi / Saweria** | Ya | Ya | Aura: `idrMin`..`idrMax`; World: `min` IDR, highest wins |

Notifikasi duration juga lewat resolver (`resolveNotifDuration`) — Robux pakai aura tier Robux; cash pakai aura tier IDR.

### 9.3 — Config schema (`ClubKitConfig.luau`)

```lua
Donation = {
    MinAmount = 1000,  -- threshold notif + leaderboard (IDR), bukan tier aura
    AuraTiers = {
        -- min = Robux | idrMin/idrMax = range Bagi-Bagi | effect/sound = folder ServerStorage.DonationEffects
        { level = 1, min = 10, idrMin = 0, idrMax = 9999, effect = "Level1", sound = "Level1", duration = 4, cameraDuration = 0 },
        -- ...
    },
    WorldEffectTiers = {
        -- Hanya Bagi-Bagi/Saweria — model di ReplicatedStorage.WorldEffects
        { min = 100000, effect = "Nuke" },
        { min = 250000, effect = "Smite4" },
        { min = 500000, effect = "BlackHole" },
    },
    NukeWorldPosition = Vector3.new(...),  -- posisi stage world VFX
},
```

**Runtime keys** (di-set `ConfigBootstrap` dari buyer config):

| Buyer key (baru) | Internal (`Config.Donation`) | Legacy alias (buyer) | Internal legacy |
|------------------|------------------------------|----------------------|-----------------|
| `AuraTiers` | `AURA_TIERS` | `RobuxAuraTiers` | `ROBUX_EFFECT_TIERS` |
| `WorldEffectTiers` | `WORLD_EFFECT_TIERS` | `SaweriaWorldTiers` | `SAWERIA_NUKE_TIERS` |

Legacy alias **masih dibaca** — buyer lama tidak wajib rename segera. Disarankan migrasi ke key baru untuk kejelasan.

### 9.4 — Showcase overrides (`ClubKitShowcase.luau`)

Saat file showcase **ada** & `ACTIVE = true`, tier donasi di-override untuk demo (threshold rendah):

| Test command | Amount (showcase) | Expected |
|--------------|-------------------|----------|
| `/testrobux 10` | 10 Robux | Aura Level4 — **tanpa** world VFX |
| `/testcash 500` | 500 IDR | Aura showcase tier rendah |
| `/testcash 2000` | 2000 IDR | Aura + world **Nuke** |
| `/testcash 150000` (showcase **OFF**) | 150k IDR | Aura production + world Nuke (100k+) |

Showcase `WorldEffectTiers` demo: Nuke @ 2k, Smite4 @ 5k, BlackHole @ 10k IDR (vs production 100k+).

### 9.5 — Test commands (admin)

| Command | Path | Efek | Catatan |
|---------|------|------|---------|
| `/testcash <idr>` | `testCashDonation` → `presentCashDonation` (testOnly) | Notif + aura + world VFX | Preview only — tidak persist |
| `/testrobux <robux>` | `testRobuxDonation` → `presentRobuxDonation` (testOnly) | Notif + aura **only** | Preview only — tidak persist |
| `/testsaweria <idr>` | alias → `/testcash` | Sama seperti testcash | Deprecated |
| `/testdonate <idr>` | alias → `/testcash` | Sama seperti testcash | Deprecated — log warn sekali per server |
| `/addcash <user> <idr>` | `addManualCashAdjustment` | Leaderboard + overhead | Persist |
| `/setrobux <user> <robux>` | `addManualRobuxAdjustment` | Leaderboard Robux | Persist |

**Penting:** `/testcash` dan `/testrobux` tidak menulis leaderboard, DataStore, atau manual adjustment. Untuk data board sungguhan pakai `/addcash`, `/setrobux`, atau `/donatecash`.

### 9.6 — Key files touched

| File | Peran |
|------|-------|
| `Shared/Utils/DonationEffectTierResolver.luau` | **Baru** — `resolveAuraByRobux`, `resolveAuraByIdr`, `resolveWorldByIdr`, `resolveNotifDuration` |
| `Shared/Config/ConfigBootstrap.luau` | Map `AuraTiers`/`WorldEffectTiers` + legacy alias → `Config.Donation` |
| `Shared/Config/ClubKitShowcase.luau` | Demo tier rendah (`AuraTiers`, `WorldEffectTiers`, `MinAmount = 100`) |
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template buyer — schema baru |
| `Shared/Constants/Config.luau` | Komentar + default internal tiers; alias `ROBUX_EFFECT_TIERS` / `SAWERIA_NUKE_TIERS` |
| `Server/Services/DonationEffectService.luau` | Pakai resolver; world VFX hanya dari path IDR |
| `Server/Services/DonationService.luau` | `testCashDonation`, `testRobuxDonation` — preview tanpa persist; `donate*Manual` untuk persist |
| `Server/Controllers/DonationController.luau` | Handler `/testcash`, `/testrobux`, legacy alias |
| `Shared/Domain/CommandLibraryDomain.luau` | Registrasi command + deskripsi |
| `Client/Controllers/DonationNotificationController.luau` | Notif duration via resolver |
| `CLUB_KIT_SETUP.md` | Panduan buyer — matrix aura vs world, test commands |
| `QA_CHECKLIST.md` | §5.6a–5.6e regression donasi |

### 9.7 — Migration notes (buyer / deployer)

1. **Rename config (opsional tapi disarankan):** `RobuxAuraTiers` → `AuraTiers`, `SaweriaWorldTiers` → `WorldEffectTiers`. Alias lama tetap jalan.
2. **Robux tidak punya world tier** — jangan expect Nuke dari donasi Robux; itu by design.
3. **Showcase vs live:** hapus `ClubKitShowcase.luau` (atau `ACTIVE = false`) sebelum production agar threshold world VFX kembali 100k+ IDR.
4. **Script test lama:** ganti `/testdonate` atau `/testsaweria` dengan `/testcash`; pakai `/testrobux` untuk uji path Robux terpisah.
5. **Persist manual:** pakai `/addcash` atau `/setrobux` untuk isi leaderboard; `/testcash` / `/testrobux` hanya preview VFX.

### 9.8 — Cara test cepat (Studio)

1. Pastikan admin permission (group rank / `AdminUserIds`).
2. Showcase ON → `/testrobux 10` → cek aura, **tidak** ada rocket/hammer/blackhole di stage.
3. Showcase ON → `/testcash 2000` → cek aura + Nuke di `NukeWorldPosition`.
4. Showcase OFF → `/testcash 150000` → cek tier production.
5. `/testsaweria 1000` → harus sama dengan `/testcash 1000` (alias).
6. Full matrix: [`QA_CHECKLIST.md`](QA_CHECKLIST.md) baris 5.6a–5.6e.
