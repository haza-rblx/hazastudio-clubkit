# P3 kill-tests — results 2026-09-24

Gate from the plan §3: "P3: 0 lost XP in kill-tests". Harness `.tmp/kill-tests-*` (gitignored; README
`.tmp/README-kill-tests.md`). Two layers: lune specs against the real modules (red on the pre-P3 commit
`7990181`, green on HEAD), and one Studio script run through `eval_server_runtime` in a THE BASIC TEST
solo playtest on build `21c4e82` (P1+P3+P4 + the two fixes below). The Studio run uses a **private clone**
of `PlayerSessionStore` and in-memory fake DataStores — no live document or DataStore key was touched;
the only live traffic was one MessagingService publish/subscribe on a random private topic and the live
`PlayerDocWriter.guard` on private keys.

## Studio run (11:51 UTC, 33 s) — all pass

| Scenario | Result | Numbers |
|---|---|---|
| 1a Invalidate lands while dirty | pass | memory kept 160 XP after the invalidate (`kept_dirty`); next save landed **170 / v9** with the other server's `title="remote"` preserved (hand-computed expectation) |
| 1b Stored `_version` newer, invalidate message lost | pass | **507 / v23**, other server's `title="newer"` kept |
| 1c Invalidate during our own write | pass | `kept_dirty`; final **45 / v4 / "late"**; second write waited the store's gap (8.0 s) |
| Bus | real | MessagingService via `CrossServerCache.subscribe`, round trip **2.3 s** |
| 2 Leave flush, first two write attempts fail | pass | attempts at 7.03 s (fail), 9.04 s (fail), **13.05 s (landed 1026 / v12)**; 47 probes saw the session in memory the whole time; released after; first leave write 7.03 s after the previous save (gap honoured) |
| 2 `PlayerDocWriter.guard`, 2 callers + other key | pass | 0 / 7.03 s; other key at 0 |
| 2 `guard`, 3 callers on one key | pass | **0 / 7.03 / 14.02 s** (before fix D1: 0 / 7 / 7) |
| 3 Shutdown with 200 dirty docs (150 Overhead + 50 Settings, 0.1 s per write) | pass | **16.33 s** (budget 22), max **12 starts/s**, Overhead first (last Overhead 12.15 s = first Settings), 0 reported unsaved, 0 lost/wrong, every document written exactly once |

Switches live: `WRITE_POLICY = "v2"`, `MIN_GAP_SEC 7`, `SHUTDOWN_WRITES_PER_SEC 12`, `SHUTDOWN_BUDGET_SEC 22`,
`LEAVE_FLUSH_RETRY_DELAYS {2,4,8,16,30}`, `InvalidateBus.V2 = true`.

## Lune specs (real modules, fake store)

| Scenario | `7990181` (pre-P1/P3) | `55bdbf4` (P1) | HEAD |
|---|---|---|---|
| 1a/1b/1c invalidate | RED (60 XP lost / +7 dropped / title overwritten) | green | green |
| 2b leave, two whole attempts fail | RED (session dropped, 25 XP lost) | RED (no 7 s gap) | green (22 s, ≥ 7 s apart) |
| 2c guard 7 s gap | RED (module absent) | RED | green |
| 3 shutdown 200 | RED (143 writes in one second, Settings before Overhead, 2 unsaved) | RED | green (16.3 s, 12/s) |
| 3b shutdown with the 1 Hz writer running | — | — | green (15.3 s, max 12/s) |

## Defects found by the harness — fixed in `21c4e82`

- **D1** `Server/Persistence/PlayerDocWriter.guard`: the write slot was recorded only after the sleep, so
  a third (or later) caller in the same window slept against the old timestamp and ran together with the
  second. Fix: reserve `lastDirectWrite[key] = now + wait` before sleeping. Probe: 3000/3007/3007 →
  3000/3007/3014.
- **D2** `Shared/Utils/PlayerSessionStore.splitKey`: `%d+` rejected negative userIds (Studio test players),
  so their sessions were silently skipped by `flushDue` and `flushAllPaced` and not counted as unsaved.
  Fix: `%-?%d+`. Predates P3.

## What this does not prove

Real DataStore latency/throttling and `DataStoreScheduler`'s in-flight cap (the fake store answers in
0.1 s, so 16.3 s is a lower bound); a real second server; a real `BindToClose` with the other repositories
flushing in parallel and the 1 Hz writer still running (covered only by lune 3b; `BindToClose` in
`Main.server` does not stop the writer — noted, not shown harmful); the 90 s XP crash window (by design,
owner decision 1).
