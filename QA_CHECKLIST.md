# QA Checklist — Club Kit v2.4.73 (post handover + review pass)

**Date:** 2026-07-07  
**Environment:** Roblox Studio (dev) → staging → production  
**Tester:** _______________  
**Build / place file:** _______________  
**Notes:** Check `[x]` after pass. Write `FAIL` + screenshot/log on failure.

---

## 0. Pre-flight (required before gameplay test)

| # | Test | Pass | Notes |
|---|------|------|-------|
| 0.1 | Rojo sync / place insert succeeds with no Output errors | [ ] | |
| 0.2 | `Secrets.luau` filled by deployer (if testing donation/API) | [ ] | Empty = API features off |
| 0.3 | `Config.HttpApi.ENABLED = false` (safe default) | [ ] | |
| 0.4 | `Config.HttpApi.COUNTERS_ENABLED = false` | [ ] | |
| 0.5 | `./tools/validate-handover.sh` → 0 fail (Git Bash/WSL + aftman) | [ ] | stylua/selene warnings OK if pre-existing |
| 0.6 | Server Output: `"Server initialized..."` with no red errors | [ ] | |
| 0.7 | Client Output: boot complete, no repeating red errors | [ ] | |

---

## 1. Critical — Data loss & shutdown (C1–C2, H3)

### C1 — Settings load gate

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 1.1 | Player joins with normal connection | Settings UI shows saved data (not empty defaults) | [ ] | |
| 1.2 | Change 1 setting → wait 5s → rejoin | Change persists | [ ] | |
| 1.3 | **Stress:** spam toggle setting 10x quickly → rejoin | Does not revert to default; not corrupted | [ ] | |
| 1.4 | Simulate load failure (disable DataStore API temporarily / budget exhausted) → join | Client may show defaults; **save/reset rejected** (no datastore overwrite) | [ ] | Check server log: `settings_not_loaded` |

### C2 — MusicRepository merge

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 1.5 | Edit playlist/track on 1 server → wait for sync | Change saved | [ ] | |
| 1.6 | (Multi-server / 2 Studio test places) edit different playlists nearly simultaneously | No playlist/track loss; highest revision wins | [ ] | Optional if 2 servers available |

### H3 — Autosave + BindToClose

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 1.7 | Play 2+ minutes (XP/settings/favorites change) → graceful server stop | Data saved | [ ] | |
| 1.8 | Check server log on shutdown: `BindToClose complete` or no timeout warn | [ ] | |
| 1.9 | Player leave → rejoin within 30s | XP, settings, favorites still present | [ ] | |

---

## 2. Critical — Memory & lifecycle (C3–C5, H5–H8)

### Studio hot-reload (dev-only, but required for hygiene fix)

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 2.1 | Hot-reload `Main.server` 3x (Rojo) | No duplicate join handler (settings sync 1x per join, not 3x) | [ ] | |
| 2.2 | Hot-reload `Main.client` 3x | No duplicate notif/donation/overhead events | [ ] | |
| 2.3 | After reload: 1 donation notif | Appears **once**, not double/triple | [ ] | |
| 2.4 | Monitor Server memory 10 min + 5 player join/leave (churn sim) | Does not rise without bound (flat trend after churn) | [ ] | Optional |

### Player leave cleanup

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 2.5 | Player join → see overhead rank/cash → leave | No server error | [ ] | |
| 2.6 | Couple: send request → sender leaves before accept | Request removed from target UI | [ ] | |
| 2.7 | Music playing → player leave | No error; session clean | [ ] | |

---

## 3. High — Abuse & edge cases (H9–H13)

| # | Area | Steps | Expected | Pass | Notes |
|---|------|-------|----------|------|-------|
| 3.1 | EffectDonate | Trigger donate effect (BlackHole/Blossom/GreenHammer/Nuke) | Effect runs; client does not freeze | [ ] | |
| 3.2 | EffectDonate | Let meteor effect run >90s (if loop exists) | Loop stops (90s deadline) | [ ] | |
| 3.3 | Donation leaderboard | Burst donations quickly (3+ in 5s) | Leaderboard updates debounced (~3s), no network spam | [ ] | |
| 3.4 | MusicService | Try injecting non-audio asset ID into queue | Rejected (`asset_not_audio`) | [ ] | |
| 3.5 | SignServer | Send string >64 char / non-string | Rejected + rate limited | [ ] | |
| 3.6 | RopeServer | Use rope without valid character / spam | Rate limited; no exploit | [ ] | |
| 3.7 | GiftPending | Buy gift → ProcessReceipt (or retry sim) | Gift delivered **once**, not double | [ ] | |
| 3.8 | PaidBroadcast | Buy broadcast → transient fail → Roblox retry | Broadcast still sent (pending not lost) | [ ] | |
| 3.9 | RoleToolService | Spam request sync tools | 2s debounce; no backpack flicker | [ ] | |
| 3.10 | GlowStick | Dual-color spam | Same cooldown as single color | [ ] | |

---

## 4. Client connection tracking (§5.1 — review pass 2026-07-07)

| # | Module | Steps | Expected | Pass |
|---|--------|-------|----------|------|
| 4.1 | Overhead | Join → overhead appears → hot-reload client → join again | Overhead still updates normally | [ ] |
| 4.2 | Settings (client) | Open settings → sync from server → reload client | Panel hydrates correctly | [ ] |
| 4.3 | Couple | Open couple panel → receive announce | Panel + announce work after reload | [ ] |
| 4.4 | Donation notif | 1 donation arrives | Notif appears 1x; queue works | [ ] |
| 4.5 | Donation leaderboard | Workspace board animates | Updates via remote + revision attribute | [ ] |
| 4.6 | Shop/Gift | Buy tier / receive grant notif | Grant callback fires once | [ ] |
| 4.7 | Admin giftcard | Send giftcard (if permitted) | Result remote routed correctly | [ ] |
| 4.8 | Avatar context | Click player → like effect | Like effect + panel work | [ ] |
| 4.9 | Cinematic dock | Permitted role → open dock | Broadcast + target list work | [ ] |
| 4.10 | EffectDonate scripts | Trigger effect → reload client script parent | No orphan connection (effect still triggerable) | [ ] |

---

## 5. Feature smoke (quick regression)

Check modules relevant to feature flags ON in your place.

| # | Feature | Quick steps | Pass | Notes |
|---|---------|-------------|------|-------|
| 5.1 | Settings | Toggle graphics + overhead visibility → save | [ ] | |
| 5.2 | Music player | Play / pause / skip / queue | [ ] | |
| 5.3 | Sync dance | Sync with partner | [ ] | Flag: `SyncDanceEnabled` |
| 5.4 | Couple | Request → accept → breakup | [ ] | Flag: `CouplesEnabled` |
| 5.5 | Shop / Gift | Prompt purchase (Studio test product) | [ ] | |
| 5.6 | Donation (cash/Robux) | Open panel → test donation | [ ] | |
| 5.6a | `/fakerobux 10` (showcase ON) | Aura appears; **no** Nuke/Smite/BlackHole; board unchanged | [ ] | preview only |
| 5.6b | `/fakecash 500` (showcase ON) | Low-tier showcase aura; board unchanged | [ ] | preview only |
| 5.6c | `/fakecash 2000 hello` (showcase ON) | Aura + world Nuke + message; board unchanged | [ ] | preview only |
| 5.6d | `/fakecash 150000` (showcase OFF) | Production aura + world Nuke (100k+); board unchanged | [ ] | preview only |
| 5.6e | `/testcash 1000` | Still works (deprecated alias `/fakecash`); board unchanged | [ ] | preview only |
| 5.6f | `/fakecash OtherPlayer 5000 msg` then check leaderboard | Notif/VFX on target; **board unchanged** (no persist) | [ ] | |
| 5.6g | `/addcash <self> 5000` | Board + overhead **change** (persist) | [ ] | |
| 5.6h | `DonationCash = false` | IDR donation panel tab hidden | [ ] | |
| 5.7 | Stickers | Place + clear sticker | [ ] | |
| 5.8 | Carry | Carry player | [ ] | |
| 5.9 | Admin panel | Open + 1 safe action (list players) | [ ] | |
| 5.10 | Command library | Execute 1 command | [ ] | |
| 5.11 | Streak | Login streak notif (simulated new day) | [ ] | |
| 5.12 | Chat tags | Chat in RBXGeneral | [ ] | Tag format correct |
| 5.13 | Leaderboard | Workspace board shows top entries | [ ] | |

---

## 6. HttpApi wrapper (only after staging baseline)

**Do not enable in production before this section passes in staging.**

| # | Steps | Expected | Pass | Notes |
|---|-------|----------|------|-------|
| 6.1 | Baseline 1–2 days with `ENABLED=false`, `COUNTERS_ENABLED=false` | No gameplay regression | [ ] | |
| 6.2 | Command Bar: `HttpApiTelemetry.Enable()` | Counter snapshot in server log | [ ] | |
| 6.3 | 30 CCU simulation workload (or max available) 1–2 days | Counters sensible; no new errors | [ ] | |
| 6.4 | Command Bar: `HttpApi.Enable()` (parallel-run) | Overhead rank/name resolve normal | [ ] | |
| 6.5 | Compare cache hit rate vs baseline | Same or better | [ ] | |
| 6.6 | Rollback test: `ENABLED=false` again | Returns to direct API without regression | [ ] | |

---

## 7. Sign-off

| Criteria | Status |
|----------|--------|
| All **§0 Pre-flight** pass | [ ] |
| All **§1 Critical** pass | [ ] |
| **§2 Hot-reload** pass (minimum 2.1–2.3) | [ ] |
| **§3 High** pass (minimum 3.1, 3.3, 3.7, 3.8) | [ ] |
| **§4 Connection tracking** pass (minimum 4.1, 4.2, 4.4) | [ ] |
| **§5 Smoke** pass for enabled features | [ ] |
| **§6 HttpApi** (if promoting wrapper) | [ ] N/A |

**Decision:**

- [ ] **READY for staging publish**
- [ ] **READY for production** (after §6 if using HttpApi wrapper)
- [ ] **BLOCKED** — list issues below

**Issues found:**

```
1.
2.
3.
```

---

## Quick reference — log strings to watch

| String | Meaning |
|--------|---------|
| `settings_not_loaded` | Load gate working; save rejected (expected on load failure) |
| `BindToClose complete` | Shutdown flush succeeded |
| `BindToClose: timeout` | **FAIL** — data may be lost |
| `Gift pending` + double delivery | **FAIL** — check GiftPendingRepository |
| `Paid broadcast receipt without valid pending` | Investigate PaidBroadcast flow |
| Duplicate settings sync on join | **FAIL** — connection leak / hot-reload |

---

*Generated for handover state as of 2026-07-07. See `HANDOVER.md` for fix details.*
