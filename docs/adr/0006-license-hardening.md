# ADR 0006 — License hardening: server-side enforcement, leak forensics, tamper response

**Status:** Accepted — implemented 2026-08-28 (Pillars 2–6). **Released in kit 2.10.0** (2026-08-28); VPS backend half deployed live the same day. Deferred to a later release: Pillar 1's universe check on the *data* endpoints (rotate-secret already exists) and the per-buyer hidden canary (Pillar 4 Packager step); the live-exploiter brick (`Config.AntiTamper.BRICK_ON_DETECT`) ships default-OFF until validated live.
**Date:** 2026-08-28

## Context

The kit is sold per-buyer; buyers run their own Studio place. GUI and client assets are hand-made and are the product's value. A buyer place was copied ("map copy") and the manual GUI lifted. The owner wants the strongest realistic protection.

### Hard limit (physics of the platform, not a choice)

Anything the client renders can be extracted — `saveinstance` / synapse-class tools copy every replicated instance, map, GUI, and LocalScript. The DevForum consensus is unanimous: **you cannot stop client-side theft**; the server has to hand the client the data. Claims of "unbreakable" Roblox protection (e.g. "Rapine Engine", a Denuvo-alike) are vaporware the community openly mocks. Obfuscation is weak *and* can get the asset/account terminated under Roblox ToS. So this ADR does **not** try to prevent copying. It makes the copy **non-functional, traceable, and takedown-ready**, and it hardens the live game against the exploiters who do the copying.

### What exists today (from a code audit, 2026-08-28)

One mechanism: a server-only poll `LicenseService.luau` → donation-api `/v2/license/verify`, gated on a plaintext boolean `KitProduct.LicenseEnforcementEnabled` (`KitProduct.luau:13`). Only two consumers: `DonationService` (`donation_http`) and `ShopService` (`shop_grant`). Backend binds universe trust-on-first-use in `license-routes.js` and can block on `license_status`/`maintenance_until`.

Audited gaps that make a copied place still work:
1. **Fails OPEN everywhere.** A never-verified server, a blank ApiUrl, and a `universe_mismatch` 403 all fall through `applyOfflinePolicy()` → all features enabled (`LicenseService.luau:74-85, 198-201`). A freshly copied place therefore runs at full features.
2. **Kill switch is one plaintext boolean** in the copied place — flip to `false`, or delete the `Main.server.luau:105-120` block, done.
3. **Universe is checked only at `/license/verify`.** The data endpoints (`v2-routes.js:82`, `v3-routes.js:71`) call `isLicenseBlocked(game)` but never compare the caller's universe to `games.universe_id` — a copied place with the stolen `Secrets.DonationApiSecret` reads/writes the real buyer's donation + leaderboard data.
4. **Only donations + shop consult the license.** Music, levels, streaks, gifts, admin, all GUIs, all effects work with no backend at all.
5. **No per-buyer identifier, no watermark, no leak signal.** `KitProduct.luau` is byte-identical for every buyer.
6. **The webhook path Roblox devs reach for is dead in production:** Discord blocks Roblox datacenter IPs, so `HttpService:PostAsync` to `discord.com/api/webhooks` returns 403 in a live server (works in Studio on a home IP — a common false comfort). Direct Discord calls can also flag the game for "redirecting users off-site".

### The one honest truth that shapes the whole design

Enforcement that runs **inside the copied place** (a boolean, a `LicenseService` check, even a signed-token check) is a **speed bump** — the thief owns that source and can edit it out. Roblox gives no cryptographic proof-of-universe to an external server, so a determined thief with the stolen secret can spoof `universe_id` too. Therefore the durable teeth are the two things the thief does **not** control:

- **The VPS refusing to serve an unlicensed universe**, plus **per-buyer secrets that can be rotated** to kill one leaked copy surgically.
- **DMCA**, armed by per-buyer watermark + leak forensics.

Everything in the kit is a filter for the lazy majority and a delivery vehicle for the forensics; the kill lives on the server and in the takedown.

## Decision

Six pillars, ordered by durability. Pillars 1, 3, 4 are the real protection; 2, 5, 6 are speed bumps + evidence delivery.

### Pillar 1 — VPS-side universe enforcement + per-buyer rotatable secrets (durable core)

- Every game data endpoint (`v2-routes.js`, `v3-routes.js`, and the game-data-api worker, which today has **zero** license coupling) verifies the caller's asserted `universe_id` against `games.universe_id` and **blocks + logs on mismatch** — closing gap #3/#4 and the game-data-api gap. A non-spoofing (lazy) thief is refused instantly; a spoofing thief is handled by rotation below.
- Secrets become **per-buyer and rotatable**. `Secrets.DonationApiSecret` / `GameDataApiSecret` are already per-place (buyer-owned, never overwritten — ADR 0001). Add a VPS admin action `rotate-secret <game_key>` that issues a new secret and invalidates the old. When a leak is detected (Pillar 3/4), rotate → the thief's copy loses all backend features while the legit buyer receives the new secret through the normal delivery/fill-forward path.
- Backend keeps trust-on-first-use bind + the existing admin `rebind` for legitimate place moves.

**Status (2026-08-28):** `rotate-secret` **already exists** — `POST /admin/games/{key}/rotate-secret` (`app.js`) issues a fresh `rbx_…` secret and returns it, so a detected leak can be killed by rotating + redelivering to the legit buyer. **Remaining (not yet built):** the universe check on the *data* endpoints (`v2-routes`/`v3-routes` gate only on `isLicenseBlocked`, not the caller's universe). Closing it needs the kit to send its `universe_id` on every data call so the VPS can compare — a cross-cutting kit+backend change. Lower urgency now: the `/license/verify` universe check (live) + the beacon (Pillar 3) already catch and log the lazy copy, and secret rotation kills it; a determined thief who spoofs universe on data calls is only stopped by rotation + DMCA regardless.

### Pillar 2 — In-kit fail-CLOSED gating, distributed (speed bump for the lazy majority)

- Fix the fail-open bugs: a **never-verified** server and a `universe_mismatch` fail **CLOSED** (premium features off). Transient VPS outage for an **already-verified** server keeps working on the last good verdict until a grace window expires (see Open Decisions) — so a real buyer survives a VPS blip, a fresh copy does not.
- Replace the single boolean + single service with checks folded into **several hot server paths** (donation grant, shop grant, music session start, DataStore write wrapper), each verifying independently. Stripping one misses the others. `admin_commands` (today computed but consumed nowhere) gets wired in.
- Honest scope: a thief who reads the whole server tree can still remove all of them. This pillar buys nothing against that thief; it stops the copy-paste reseller who never opens the code, which is most of them.

**Fail-closed rework: implemented + validated 2026-08-28** (`LicenseService.luau`). Fixed the fail-open bugs by classifying the server's answer instead of treating every non-success as "offline → open": a **definitive denial** (403 `universe_mismatch`, or a returned status of `revoked`/`expired`/`unlicensed`) sets a **sticky `_hardDenied`** → all features off, and a later network blip cannot re-open it (`isFeatureEnabled` checks `_hardDenied` before any optimism). A **previously-verified** server that goes unreachable keeps its last verdict for the 24h grace, then closes. The genuinely-undeterminable cases (timeout / DNS / no ApiUrl / Studio-no-secret) stay optimistic on purpose — we cannot distinguish a flaky-network or non-donation legit buyer from a thief who firewalled the endpoint, and bricking them would hurt real buyers; the VPS-side universe check (Pillar 1) + beacon (Pillar 3) close that gap instead. Validated live against the real VPS in `the-basic`: licensed path → `status=active`, all features on, `enforcementActive=true`; a request carrying a mismatched `universe_id` returns `403 {"ok":false,"error":"universe_mismatch"}` and the detection flips `_hardDenied` → features off. No regression to the licensed place (donations/leaderboards keep working). **Follow-ups:** (1) ~~`admin_commands` not consumed~~ **DONE 2026-08-28:** wired into `CommandExecutionService:execute` (the single choke point for every raw + registered command) — if `isEnforcementActive()` and not `isFeatureEnabled("admin_commands")`, the command is refused with a "not licensed" notify before any handler runs. So a hard-denied copy loses all staff/admin commands too, now alongside donations (`donation_http`) and shop grants (`shop_grant`) — all three feature bits are consumed at independent sites. Validated in `the-basic`: gate condition is false (pass) in the normal/optimistic state and true (block) when the license is forced to a denied state; a real `/refreshleaderboard` executed in the normal state (no regression). (2) In the `the-basic` Studio session the boot-time `LicenseService.start()` came up pristine (never verified) — likely a stale place sync since the repo wiring (`Main.server` passes `Config.Donation.SHEETS_WEB_APP_URL`) is correct and a manual `start()` reached `active`; confirm on next real sync that a live server actually verifies. (3) Consider extracting the decision table into a pure function with a lune test (tdd-luau).

**HttpService-required boot gate (owner's idea, 2026-08-28).** Before the kit initialises anything, it confirms HttpService actually works — by attempting the license/challenge request and catching the "Http requests are not enabled" error. If HTTP is **off, the kit does not run at all** (halts init, shows an "enable HttpService / unlicensed" state). Rationale: thieves commonly disable HttpService specifically to blind the beacon/phone-home (a limitation noted across the DevForum leak-protection threads). This gate converts that bypass into a dead kit: the thief must either enable HTTP (beacon + universe check fire and catch them) or have a non-functional kit. Legit buyers are unaffected — they already run with HttpService on for donations. Strippable in-place like the rest of Pillar 2, so it is a filter for the lazy majority, not a wall.

**Status: implemented + tested 2026-08-28.** Gate sits in `Server/Main.server.luau` right after the boot log, before every other system, keyed on `HttpService.HttpEnabled` (the setting — instant, cannot false-halt on a network blip; a live request probe is left to the license path). Verified live in the `the-basic` test place: HTTP off → `BOOT HALTED` warn, server stops before init, zero remotes/services created, client stalls (dead kit); HTTP on → `Server initialized … ready`, no regression. Sets `Hazastudio_ClubKit:SetAttribute("BootHalted", "http_disabled")`.

**Client prompt: implemented + verified 2026-08-28.** `Client/UI/BootHaltedNotice.luau` (new) draws a full-screen "Club Kit paused — HttpService is turned off … Enable Allow HTTP Requests in Game Settings → Security, then rejoin." overlay. `Main.client` reads the replicated `BootHalted` attribute in the deps-timeout branch and shows it. Rendered correctly in the `the-basic` test place (screenshot). Caveat found there: that place runs a **non-kit** anti-injection guard that disables any unfamiliar ScreenGui added to PlayerGui (a plain test ScreenGui is disabled too) — not present in the shipped kit (repo has no such suppressor), so the overlay renders normally in a clean buyer place; in the test place it only rendered when force-enabled. If a buyer runs such a place-level guard, the robust home for the message is inside `LoadingBootstrap` (the loading screen it owns is whitelisted) — noted as a possible future hardening, not needed for the kit itself.

### Pillar 3 — Leak beacon via the VPS (evidence, not attack)

- Server-side beacon (HTTP is server-only, so exploit clients can't read the URL) POSTs to `api.hazastudio.id/v2/beacon` on boot **when the universe does not match the bound one**: `universe_id`, `place_id`, `game.CreatorId` (the infringing owner — the DMCA target; note `CreatorId = 0` in unpublished places, but a thief who publishes has a real one), `kit_build_id`, buyer canary (Pillar 4), timestamp.
- The **VPS** forwards to Discord/owner notification from an allowed IP — this is the only way that works (Discord IP-blocks Roblox). Fires the notification the current AC webhook silently fails to send.
- "Small chance / low frequency + buried in a hot path" per the owner's request: harder for a tinkering thief to notice the HTTP call, and cheap on the endpoint.

**Status: implemented + tested 2026-08-28.** VPS (`clubkit-infra/apps/api`): migration `0019_license_beacons.sql` (leak log table), `POST /game/{key}/v2/beacon` handler (`license-routes.js:handleBeacon`, routed in `v2-routes.js` **before** the license gate so a hard-denied copy can still report), and Discord forward from the VPS's allowed IP (`discord.js:queueBeaconAlert` + `buildBeaconEmbed`, `config.DISCORD_BEACON_WEBHOOK_URL`). Kit (`LicenseService.luau`): `sendBeacon("universe_mismatch")` fires once when a verify returns 403 universe_mismatch, posting `universe_id`, `place_id`, `creator_id` (the infringer — the DMCA target), `job_id`, kit version/build, player count. Validated: the full infra test suite passes (37/37, incl. two new beacon tests — records the place+owner, and still records when the license is revoked); migration applies cleanly. **Deploy steps** (owner): deploy the infra repo (restart auto-applies 0019) and set `DISCORD_BEACON_WEBHOOK_URL` in the VPS `.env` to the provided webhook (kept out of the repo). The kit half ships with the next kit sync/release.

**Deployed + extended 2026-08-28.** VPS beacon backend is live (endpoint + migrations + webhook set + health verified end-to-end; a real beacon POST → recorded → Discord). Two extensions landed:
- **Human-readable enrichment** (`discord.js`): the VPS looks up the **place name** and **owner (display + @username)** from the universe id via Roblox's public APIs (the VPS IP can reach them; game servers cannot), so the embed shows `THE BASIC TEST 1.3` and `haza (@hazatargz)` with clickable links instead of raw ids. Owner is derived from the universe when the kit did not send `creator_id` (the verify path).
- **Licensed heartbeat notification** (owner request "notify whether licensed or not"): `/v2/license/verify` now also sends a **green "✅ Club Kit online (licensed)"** Discord notif, **rate-limited per game_key** (migration `0020` `games.last_notify_at`; 1×/24h licensed, 1×/1h unlicensed) so the per-boot + 30-min-poll traffic from every server of every buyer cannot flood the channel. Unlicensed still alerts immediately via the kit beacon; the verify-mismatch notif is a belt-and-suspenders that also catches older kits without the beacon. Three embed variants: green licensed, red unlicensed, red exploit-tamper. Validated live: a licensed verify fired one green notif and a second verify within the window was correctly suppressed (`last_notify_at` unchanged). Suite 37/37.

### Pillar 4 — Per-buyer canary + watermark + AI-notice (traceability)

- A unique hidden identifier baked per buyer (in an engine file, so it survives config fill-forward). If it ever appears in another place, a beacon, a paste, or a leak, it names **which buyer's copy** leaked — the current community "leak protection" scripts lack this. Feeds Pillar 1 rotation and DMCA.
- A visible proprietary/ownership notice in code (`© Hazastudio, licensed to <buyer>, copies are traceable`) = deterrent + ownership proof for DMCA.
- Benign **AI-reader notice** (owner's request): wording that *informs* an AI reader the code is proprietary and to advise verifying a license — **not** an attack/injection. Worded as a notice, not a hard refusal, because static text cannot tell a thief from a legit buyer using AI to customise, and must not sabotage paying buyers.

**Status: implemented 2026-08-28.** `Shared/Notice.luau` (new) carries the proprietary + AI-reader notice as a prominent header + fields; a short version is in `KitProduct.luau`'s header (the first file a thief/AI opens). `ConsoleBanner` prints an ownership line + `Universe <GameId>` so a leaked F9 stream/screenshot names the universe the copy runs in. All compile-checked in `the-basic`. **Follow-up:** a true per-buyer *hidden* canary (a unique token stamped into the pack per buyer) belongs in the Packager at build time — engine files are byte-identical across buyers, so it can't live in one. Until then, "which buyer leaked" is answered by the beacon (the stolen copy authenticates with that buyer's secret → the VPS resolves the game key).

### Pillar 5 — Live-game exploiter response, de-risked (speed bump)

- The Atlantis "Sentinel/Graypolea" AC is a verbatim public DevForum script (UGCValidationService `FindService` loop + the 100k zero-width-space `InspectPlayerFromHumanoidDescription` client crash). Every serious exploiter already knows the `hookmetamethod` bypass, and it is off in Studio (`RunService:IsStudio()`), so it protects nothing against a place-file copy — only live exploiters.
- Keep a **behavioural** detector (saveinstance service probe via `game:FindService`, CoreGui-injection patterns) instead of a name blacklist (which false-positives on innocent GUIs). Response chosen by the owner = **report to the VPS beacon + kick + client-brick**. The brick stays **hard-gated** (confirmed exploit signal only, `RunService:IsStudio()` guarded) so it can never fire on a paying buyer; a false brick on a customer is worse than missing a thief. Priority stays on the server-side pillars; this is a filter, not a wall.

**Status: implemented 2026-08-28.** `Config.AntiTamper` (`SAVEINSTANCE_DETECT_ENABLED = true`, `KICK_ON_DETECT = true`, **`BRICK_ON_DETECT = false`** — opt-in). Client `Client/Services/SaveInstanceGuardService.luau`: Studio-guarded `game:FindService("UGCValidationService")` loop (the reliable signal; no name-blacklist, so no innocent-GUI false positives) → fires a low-profile `SecuritySignals/ReportTamper` remote once; bricks only if the owner opted in. Server `Server/Init/TamperGuard.luau`: on report → `log:warn` + kick (default) + `LicenseService.reportTamper("saveinstance", {actor_id, actor_name})` → a distinct Discord embed ("🛠️ Exploit tool detected in a licensed place", links the player). Reporter is always the sender, so it cannot kick others. Validated: all modules compile-check in `the-basic`; server wiring boots clean. Brick default-off is deliberate — the owner enables it once they trust the detector in their place (a live brick was not validated with the owner absent).

### Pillar 6 — Self-integrity tripwire

- A small server routine periodically checks that the license layer's modules still exist / match expected hashes. If the layer was stripped, a surviving tripwire fires the beacon and degrades premium features. Cat-and-mouse, but raises the bar past "delete one script".

**Status: implemented 2026-08-28.** `Server/Init/IntegrityTripwire.luau` (new) runs at boot **before** the enforcement gate and **independently** of it — its own HTTP post, so the most common strip (`KitProduct.LicenseEnforcementEnabled = false`, which silences LicenseService) does not silence this. On a configured, licensed place where enforcement has been explicitly flipped `false`, it beacons `enforcement_disabled` (Studio-guarded; an older build's missing flag is `nil`, not a strip, so it checks `== false` specifically). Validated: compile-check + clean boot in `the-basic`. Deeper module-hash self-checks remain a future iteration.

## Consequences

- **Real buyers can be affected by fail-closed.** A VPS outage past the grace window disables premium features for legitimate buyers. The grace window is the safety valve; its length is a business trade-off (Open Decision 1).
- **Secret rotation is a manual-ish delivery step.** Because `Secrets.luau` is buyer-owned (ADR 0001), rotating means issuing a new secret on the VPS and delivering it to the legit buyer through the existing pack/fill-forward flow. Rotation is surgical (one buyer) but not instant.
- **Universe enforcement can 403 a legit buyer** whose universe genuinely changed (place transfer). Mitigated by trust-on-first-use + the admin `rebind` path that already exists.
- **False-positive risk** on the live-exploiter detector — the single biggest operational hazard, because crashing/kicking a paying player is worse than missing a thief. Hence behavioural detection + hard gates + kick-not-brick default.
- **Register budget (ADR 0002):** new client/server wiring must go through the `Init` bags, not new top-level `local` requires in `Main.server`/`Main.client`. Check with `count-locals.ps1`.
- **Nothing here touches `ClubKitConfig.luau` structurally**; new engine constants live in engine files; the only buyer-owned surface is the per-buyer secret + canary value, delivered, not merged.

## Decisions (resolved by the owner, 2026-08-28)

1. **Fail-closed grace window**: **24h**.
2. **Live-exploiter response**: **kick + report + brick** (brick hard-gated per Pillar 5).
3. **Beacon target**: a Discord webhook (provided 2026-08-28) — stored on the VPS as an env var, **never** in the kit or this repo; the VPS forwards to it from an allowed IP.
4. **Universe enforcement launches immediately (blocking, not log-only).** Accepted risk: a legit buyer whose universe legitimately changed may get 403 and must contact the owner for a whitelist/`rebind`. Chosen deliberately for tighter protection.
5. **Secret rotation** rides the existing delivery-pack / fill-forward flow (to confirm operationally on first rotation).

**Test bed:** the owner opened `THE BASIC TEST 1.3` (placeId `75916114543452`, game_key `the-basic` / `clubkit-test`) for live experimentation — "all yours".

## Implementation phases (smallest-durable-first)

1. **Phase A — VPS universe enforcement (log-only) + beacon endpoint.** Backend only, zero kit risk. Add universe check (log mismatches, don't block yet) to v2/v3 + game-data-api; add `/v2/beacon` + Discord forward; add `rotate-secret` admin action. Observe real buyer traffic.
2. **Phase B — Fix fail-open → fail-closed + distributed gating in the kit** (`LicenseService.luau`, hot-path checks, grace window). Engine files only.
3. **Phase C — Per-buyer canary + watermark + AI-notice**, wired into build/delivery so each buyer's pack carries its identifier; beacon starts reporting it.
4. **Phase D — Flip universe enforcement from log-only to blocking** once Phase A data shows no legit-buyer false positives.
5. **Phase E — Self-integrity tripwire + de-risked live-exploiter detector.**

Each phase ships behind `KitProduct.LicenseEnforcementEnabled` semantics and is independently revertible.

## Non-goals (explicitly out of scope)

- Destroying, corrupting, or force-closing a thief's machine, Studio, or place file. Impossible under the Luau sandbox and out of bounds as intent; the client-brick in Pillar 5 only crashes a live exploiter's own session (non-permanent) and is optional.
- Obfuscation as a primary defence (weak + ToS risk).
- Prompt-injection that attacks a thief's AI (backdoor/harm/deceive) — hits your own buyers by accident and makes you the bad actor. Only the benign AI-notice in Pillar 4 is in scope.
