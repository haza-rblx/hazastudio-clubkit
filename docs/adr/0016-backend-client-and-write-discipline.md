# ADR 0016 — BackendClient (header-only secrets) and write discipline at 200 players

Status: Accepted, 2026-09-24 — implemented in the repo (production hardening P3), awaiting sync to
THE BASIC TEST and a 48 h soak. Plan: `docs/plans/production-hardening-2026-09-24.md` §2 A/B/C.

## Context

One Roblox server now holds 200 players (owner, 2026-09-24). The audit found the kit's HTTP and
DataStore use scale with the player count while the limits do not: HttpService is 500 requests/min
per server whatever n is; one DataStore key takes one write per 6 s; MemoryStore is 64 KB + 1 KB per
player. Concretely: XP wrote each player's `Overhead_v1` every 3–10 s; eight `RequestAsync` paths
had no shared limiter; four call sites put the game secret in the query string (and the VPS's Caddy
logged 1,403 such URLs); ReliabilityV2 posted once per player per donation; every server rewrote
the same global documents; the MemoryStore leaderboard cache stored full rows per limit.
The VPS side (P2, live 2026-09-24) already serves `players/lookup`, `has_commands`, Bearer auth on
every route and a 429 `{error:"rate_limited", retry_after}` contract (log-only until enforced).

## Decision

1. **One HTTP entry for the VPS: `Server/Net/BackendClient`.** Call sites pass a URL without a
   secret plus `auth = "donation" | "gamedata" | "none"`; the client adds
   `Authorization: Bearer <secret>`. **The kit never puts a secret in a URL.** P5 can then make the
   VPS reject `?secret=` once ≥ 95 % of active games run a P3 kit. The client owns one per-server
   token bucket (400/min, burst 40) with priority floors (critical 0 %, normal 25 %, bulk 50 % — bulk
   waits instead of being dropped), honours 429 `retry_after` for every priority, keeps a circuit
   breaker per endpoint group, and always sends a whole-second `Timeout`. It returns what
   `pcall(HttpService.RequestAsync)` returned, so call sites keep their handling. Licence and
   tripwire HTTP stay self-contained (ADR 0006; header auth already).
2. **Background per-player lookups are batched** through `GET /v2/players/lookup` (≤ 50 ids, 3 s
   window): join-time cash, rank resolution, the join's connections warm. Lookups a player waits on
   (donor panel, donation processing, profile opened, the group rank of the first overhead payload)
   stay direct. The per-user routes remain the fallback (404/405 → off for 30 min).
3. **One write path per player document: `PlayerDocWriter`.** XP-only changes are written on a
   per-player slot (`userId % 90`) in every 90 s (owner decision K1 = the crash window), urgent
   changes after a 3 s debounce, never two writes of one key within 7 s; a 1 Hz scheduler paces
   writes; shutdown is paced (≤ 12/s, Overhead first). XP-only writes are not published to other
   servers.
4. **Global documents are written once per revision** (`GlobalDocWriter`). The revision and the
   server's fetch time live in the key's **DataStore metadata** (`rev`, `fetchedAt`, `writtenAt`) —
   not in the value — so the stored shape is unchanged for older kits and no new key is needed.
   Revisions are content hashes, so "newer" means "fetched later". Values over 1 MB are refused.
5. **MemoryStore leaderboard cache v2**: a new map `ClubKitLeaderboardCache_v2` with one item per
   board, `{ v = 2, n = limit, r = { id, total, … } }`, ≤ 4 KB; names are resolved locally. A new map
   name (not new rows in the old map) so v1 and v2 rows never mix during a rollout; the v1 map
   expires by its 60 s TTL.
6. **Every part is switchable back** to the pre-P3 behaviour with an engine constant
   (`Config.BackendClient.ENABLED`, `Config.PlayerDocWriter.WRITE_POLICY = "legacy"`,
   `Config.InvalidateBus.V2`, `Config.LeaderboardCacheV2.ENABLED`, `Config.GlobalDocWriter.ENABLED`,
   `Config.VerifyCache.ENABLED`). The only buyer-visible addition is `ClubKitConfig.Telemetry.Enabled`
   (ADR 0007: opt-out, default on).

## Consequences

- Hard to reverse: once P5 rejects query secrets, a kit older than P3 stops talking to the VPS.
  Rolling a venue back to a pre-P3 tag after P5 therefore needs the VPS flag re-enabled.
- A server crash can lose up to 90 s of XP (was ~3 s); leave, restart and shutdown lose nothing.
- Players in other servers see someone's new XP (not level) only after their cached copy expires.
- A music library larger than 1 MB encoded is no longer cached in the DataStore (warning +
  `doc_oversize`); sharding `Tracks` into new versioned keys is designed (plan §2 B) but only gets
  built — as an additive, documented migration — if that event is ever seen.
- ReliabilityV2 defaults to on (owner decision K7). Update Engine's source patch only adds missing
  `Features` keys and whole missing sections, so buyer files almost never carry
  `Donation.ReliabilityV2`; the runtime fill-forward then applies the new default `true`. A buyer
  file that does say `false` keeps it off.
