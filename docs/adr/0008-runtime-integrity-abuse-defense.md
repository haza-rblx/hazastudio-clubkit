# ADR 0008 — Runtime integrity & abuse defense (anti-cheat for club venues)

Status: **Proposed** (2026-08-29). Research + design; nothing in this ADR is built yet except the scanner in `tools/security/`.

Trigger: a buyer venue was hit by a *guest with no rank* who made a laughing audio play **for everyone in the server**. ADR 0006 covers theft of the kit; this ADR covers the other half — someone abusing a live venue.

## Context

### What the platform actually allows an attacker to do (2026)

| Class | How | What they can do | What they can **not** do |
|---|---|---|---|
| **A. Client executor** (injected Luau on the attacker's own client) | Windows: Hyperion/Byfron makes injection rare, paid and ban-waved; still common on **Android, emulators and macOS** where Hyperion is not (fully) rolled out. | Fire **any RemoteEvent/RemoteFunction with any arguments**, at any rate; move their own character however they want (fly, speed, noclip, teleport); hide or spoof their own UI; `saveinstance` (asset theft, ADR 0006); play sounds **only on their own client**. | Run code on the server. Make other clients hear or see anything unless a **server** path replicates it. |
| **B. Backdoor** (malicious code already inside the place) | Free models / plugins / "admin" scripts that `require(<asset id>)` a remote `MainModule`, or `getfenv`/`loadstring` obfuscated payloads. The module typically hands a **server-side executor GUI** to a whitelist of user ids — often "anyone who knows the chat trigger". | Everything a server can: play global sounds, kick/ban, spawn parts, drain DataStores, post to Discord, install more backdoors. **This is the profile of the incident** ("random guest, everyone hears it"). | Nothing — a backdoor *is* the server. |
| **C. Unguarded place-level remotes** (third-party scripts the buyer added) | A `RemoteEvent` whose server handler trusts its arguments: `PlaySound(soundId)`, `Announce(text)`, `SetRole`, `GiveTool`. | Combined with A: any client plays any audio for everyone, spams announcements, grants itself roles. | Only what the handler exposes. |
| **D. Admin-system abuse** | Kohl's `:music <id>` / Adonis `:music`, rank thresholds set too low (group rank 1 "Member" counted as mod), leaked admin lists, stolen "HD Admin"-style modules that phone home. | Global audio, kicks, bans, chat spam — legitimately, via the admin tool. | — |
| **E. Account / social** | Compromised staff account, phishing for Studio access, Discord webhook token pasted into a place script (copy the place → spam their Discord). | Anything that staff could do; webhook spam. | — |
| **F. Resource abuse** | Remote spam, DataStore budget exhaustion, physics spam (welds, unanchored parts through a remote). | Lag the server for everyone until it dies. | — |

Sources: [Roblox Anti-Cheat in 2026 (Hyperion)](https://endsights.com/roblox-anti-cheat), [Hyperion — Roblox Wiki](https://roblox.fandom.com/wiki/Hyperion), [How backdoors work](https://rbxdevnotofficial.medium.com/how-backdoors-work-f65494b71e21), [Complex free-model backdoor explained](https://rbxdevnotofficial.medium.com/complex-freemodel-backdoor-explained-159a75df6383), [Find getfenv — backdoor finder](https://devforum.roblox.com/t/find-getfenv-extremely-fast-and-easy-backdoor-virus-finder/1373304), [Backdoor prevention (DevForum)](https://devforum.roblox.com/t/backdoor-prevention/3122952), [Script Injection Vulnerability (plugins)](https://devforum.roblox.com/t/script-injection-vulnerability/221954), [Asset privacy (audio permissions)](https://create.roblox.com/docs/projects/assets/privacy).

### What the kit already does (audit 2026-08-29)

- Every kit remote handler validates payload shape (`Shared/Utils/Validator`), requires a `requestId` (idempotency cache) and runs through `RateLimiter` (64 `OnServerEvent`/`OnServerInvoke` sites, 151 permission/rate-limit checks across 19 controllers).
- Audio the kit plays server-side comes only from **templates already in the place** (`DonationEffectService.playSound` clones `ServerStorage.DonationSounds/LevelN`, filtered by `SoundAssetSanitizer`). The music player plays **library tracks only**; adding a new asset id (`MusicService:resolveOrCreateTrackForAsset`) needs the manage role, and `requestTrack` is rate-limited + DJ-mode gated. **A guest cannot make the kit play an arbitrary sound id.**
- `TamperGuard` / `SaveInstanceGuardService` / `IntegrityTripwire` / `LicenseService.reportTamper` (ADR 0006) already give us a server → VPS → Discord evidence path (`postBeacon("tamper:<reason>")`).
- DataStore admission control (`Budget admission deferring`) protects the kit's own stores from spam.

So for the incident, the kit is the least likely vector. The buyer places ship with: Kohl's **and** Adonis loaders, `Pyrotechnics-Pack` (`require(89224403262662)` at boot), GLights, VideoScreen, NekoDono, CenzMusic, `Discord` server scripts, a `MainModule` in ReplicatedStorage (old Hierapolis), and dozens of unaudited `RemoteEvent`s (`DonationAnnounce`, `GlobalAnnouncement`, `Req`, `Sync`, `Remotes2`, `RoleAdminRemotes`). Any one of these is a plausible B, C or D.

### The honest limits

- We cannot stop client injection on Android/macOS; we can only make the server refuse what an injected client asks for. That is what "server-authoritative" means and the kit already is.
- We cannot audit third-party code at runtime — but we **can** see its *effects*: a `Sound` appearing where none should, a `Script` being created at runtime, a remote being fired 200×/s.
- A backdoor that runs before us can disable us. Hence detection must be cheap, early (`Server/Init`), and beacon **first, act second**.

## Decision (proposed)

Four layers, cheapest and most durable first.

### Layer 1 — Place hygiene, before publish (tooling, no engine risk)

`tools/security/PlaceSecurityScan.luau` (built with this ADR) runs in Studio (command bar, MCP `execute_luau`, or the Packager panel later) and reports, by severity:

- **CRITICAL** `require(<number>)` anywhere — remote module = remote code. The only acceptable ones are the ones the buyer can name (Kohl's `1868400649`); everything else is replaced by a vendored copy or removed.
- **HIGH** `getfenv` / `setfenv` / `loadstring`, `string.reverse` next to `require`, dense `\ddd` escape sequences, `discord.com/api/webhooks` (secret in source), scripts living in odd services (Lighting, SoundService, TextChatService, Teams, StarterPack).
- **MEDIUM** non-kit `RemoteEvent`/`RemoteFunction` handlers (audit list), `HttpService` outside the kit, minified one-liners, non-kit `Instance.new("Sound")` on the server.
- **INFO** inventory: all non-kit remotes, all server scripts that can create sounds, all scripts requiring anything by id.

Ships with a **buyer checklist** (`docs/delivery/SECURITY_CHECKLIST.md`): one admin system only; rank thresholds reviewed; no `Discord` webhook scripts in the place (the VPS forwards instead); every free model scanned before insert; staff 2FA; group rank audit; collaborator list audit; asset privacy set on the venue's own audio.

### Layer 2 — Runtime guards in the kit (`Server/Init/RuntimeGuard.luau`, log-only first)

Independent of the kit boot gate, started in `Server/Init` next to `IntegrityTripwire`:

- **SoundGuard** — snapshot every `Sound` in the DataModel at server start (their `SoundId`s become the allowlist, plus anything under kit-owned roots). On `DescendantAdded` of a `Sound` (or `SoundId` change) whose id is not allowlisted and whose ancestor is not kit-owned: log `{soundId, path, creatorGuess}`, beacon `runtime:rogue_sound` (deduped per id), and — when `Config.RuntimeGuard.SOUND_ENFORCE = "block"` — stop + destroy it. Default `"log"` for one release, then `"block"`.
- **ScriptGuard** — any `Script`/`LocalScript`/`ModuleScript` created at runtime outside kit roots and outside a small allowlist (Kohl's/Adonis loaders create their own) → log + beacon `runtime:script_injected` with parent path and the first 200 chars of Source; optional destroy.
- **RemoteStorm** — a global per-player counter across kit remotes (the limiters are per remote); above `REMOTE_STORM_PER_SEC` for `REMOTE_STORM_WINDOW` → kick + beacon `runtime:remote_storm`. Cheap, catches spam bots before the limiters do.
- All three reuse `LicenseService.reportTamper` (reasons prefixed `runtime:`), so evidence lands in the same VPS table and Discord channel as ADR 0006 beacons.

### Layer 2b — MovementGuard: client-side movement cheats, auto-kick (added 2026-08-29)

Owner asked for fly/speed/etc. to be kicked automatically. What these cheats are, what the server can actually see, and why a club venue needs a *whitelist-first* detector.

#### The cheats (what an injected client does to its own character)

| Cheat | Mechanism on the client | Server-visible symptom | Why a club cares |
|---|---|---|---|
| **Fly** | Loop that sets `AssemblyLinearVelocity`/`CFrame` on the HRP, or a `BodyVelocity`/`LinearVelocity` on the character (client-created movers replicate through the owned assembly). | HRP rises/hovers with no floor beneath and no jump impulse; `Humanoid` state stuck in `Freefall`/`Flying`/`Physics`. | Floats over the stage, blocks camera shots, ruins photos. |
| **Speed** | `Humanoid.WalkSpeed = 100` (replicates because the client owns its Humanoid) or CFrame stepping. | Horizontal displacement per second ≫ what the server-set `WalkSpeed` allows. | Runs through the crowd, spams distance. |
| **Noclip** | `CanCollide = false` on own parts every frame, or CFrame through walls. | Path between two samples crosses a `CanCollide` wall/floor. | Enters backstage / VIP rooms / DJ booth. |
| **Teleport** | `HRP.CFrame = target` once. | Displacement > N studs in one sample with no server teleport token. | Jumps onto the stage, onto the DJ, into staff rooms. |
| **Infinite jump / high jump** | `Humanoid:ChangeState(Jumping)` mid-air, or `JumpPower = 200`. | `Jumping` state while airborne; rise height > `JumpPower` physics. | Same as fly, cheaper. |
| **Anti-AFK** | Fake input (`VirtualUser`) to dodge the 20-min idle kick. | Not detectable server-side per se; the kit's own `AfkGuard` idle ladder is the countermeasure (it measures *movement + input reports*, so spoofers stay "active"). | Seat squatting, crowd inflation. |
| **Emote / animation spam** | `Animator:LoadAnimation` of arbitrary ids (client-owned animator replicates). | Animation tracks on the character that are not in the kit dance catalog / Roblox default set. | Lewd or seizure-inducing animations on the dance floor. |
| **Chat filter bypass / spam** | Unicode look-alikes, zero-width chars, rapid sends. | Roblox `TextChatService` filters server-side already; kit can add per-player rate + repeated-message hash. | Harassment. |
| **Fake UI** | Client-only edits: fake "donated Rp 10.000.000" toasts, fake ranks. | Nothing replicates — only the cheater sees it. Screenshots are the only "harm". | Reputation; nothing to detect, educate staff. |
| **Avatar / item spoof** | Local-only appearance changes. | Nothing replicates (server owns `HumanoidDescription`). | None. |
| **Remote spam / lag switch** | Fire remotes in a loop; throttle own connection. | RemoteStorm (Layer 2) + kit rate limiters. | Lag. |
| **Ban evasion / alts** | New account. | `AccountAge`, no history. | Repeat trolls. |

#### What the server can see, honestly

Roblox gives the client **network ownership of its own character**: `WalkSpeed`, `JumpPower`, HRP `CFrame`/velocity and animation tracks all replicate *from* the client. The server cannot prevent those writes — it can only **observe the replicated result** and react. A server-side movement guard is therefore a sampler + a set of physics-plausibility rules + a strike ledger, never a blocker. Detection lag of ~1 s is fine for a venue; false kicks are the real cost.

#### Detector design (server, `Server/Init/MovementGuard.luau`; rules in a pure `Shared/Domain/MovementPolicy.luau`)

Sample every character every `SAMPLE_INTERVAL` (0.5 s): HRP position, `AssemblyLinearVelocity`, `Humanoid.WalkSpeed`/`JumpPower`/`FloorMaterial`/state, `Player:GetNetworkPing()`. The **pure policy** takes the last two samples + an exemption bitset and returns zero or more violations; the guard only does I/O.

**Exemptions come first** (this is what makes it safe in a club, and all of them are states the kit itself creates):

- Kit **Gravity float** (`GravityService` owns a `LinearVelocity` on the HRP; guard asks `GravityService:isFloating(player)`), and its restore fall.
- **Carry** in either role (`CarryService` welds + `PlatformStand`; attributes/`CarryWeld` present).
- **Server teleports**: `/to`, `/bring` (`SessionCommandService.handleTo/handleBring`), respawn, `CharacterAdded`, AfkGuard rejoin landing, `Seat`/`VehicleSeat` occupancy. The teleport path stamps `character:SetAttribute("ClubKitTeleportAt", os.clock())`; any displacement within 2 s of the stamp is ignored.
- **Sync dance** (`Syncing`/`IsLeader` attributes): animation checks skip catalog dances; movement rules still apply.
- Roles in `Config.MovementGuard.EXEMPT_ROLES` (default `Owner`, `CoOwner`) — staff use Freecam/fly tools legitimately.
- First 5 s after spawn; any sample with ping > 600 ms is discarded rather than judged.

**Rules** (each yields a strike weight; tolerances are deliberately loose):

| Rule | Condition (per 0.5 s sample) | Weight |
|---|---|---|
| Speed | horizontal distance / dt > `max(WalkSpeed, 16) × 1.6 + 4` for **3 consecutive** samples | 1 |
| Speed-property | `Humanoid.WalkSpeed` > `MAX_WALKSPEED` (default 32) or `JumpPower` > `MAX_JUMPPOWER` (75) — a client-set property, seen directly | 2 |
| Fly | vertical velocity ≥ 0 and `FloorMaterial == Air` and no downward raycast hit within 8 studs for **4 consecutive** samples, state not `Seated/PlatformStanding/Climbing` | 1 |
| High-jump | rise since last floor contact > `jumpApex(JumpPower) × 1.8 + 5` studs | 2 |
| Noclip | raycast from previous to current position hits a `CanCollide` part whose thickness the sample crossed (ignore parts in `Config.MovementGuard.IGNORE_COLLECTION_TAG` and anything under kit boards), for 2 samples in 10 s | 2 |
| Teleport | displacement > `max(60, speedCap × dt × 3)` studs in one sample with no teleport stamp | 3 |
| Infinite jump | `Jumping` state entered while `FloorMaterial == Air` ≥ 3 times within 3 s | 1 |
| Foreign animation | a playing `AnimationTrack` whose `Animation.AnimationId` is not in the kit dance catalog, Roblox default animate ids, or `Config.MovementGuard.ALLOWED_ANIMATION_IDS` | 1 (log-only until the catalog allowlist is proven complete) |

**Ledger**: strikes decay 1 per `STRIKE_DECAY_SEC` (20 s). At `WARN_AT` (3) the player gets a kit notification ("Movement looks modified — stop or you will be removed") and a beacon `runtime:movement_warn`. At `KICK_AT` (5) → kick with a plain-language reason, beacon `runtime:movement_kick {rule, samples, ping}`, and a `Config.MovementGuard.SOFT_BAN_MINUTES` (15) memory-only re-join block for this server. Owner can flip `ENFORCE = "log"` per place.

**Not detected on purpose**: fake UI, avatar spoof (nothing replicates — nothing to fix); "wall-hugging" or animation-cancel micro-cheats (no venue harm, high false-positive rate).

#### Why this is safe enough to ship as kick-by-default

Every rule needs either a client-set property that legitimate players can never have (WalkSpeed 100), or **repeated** physically impossible samples with all kit-driven states excluded and lag samples dropped. A laggy phone player produces one bad sample, not four in a row; a teleport by staff carries a stamp. The remaining risk is third-party place scripts that move players (e.g. a buyer's own teleporter pads) — those are covered by the same attribute stamp, documented in the checklist, and by log-only mode for the first week on a new place.

### Layer 3 — Response tools for staff

- `/purgesounds` (Staff+): stop and destroy every non-allowlisted `Sound` right now; `/soundlog` prints the last 20 rogue-sound events with the actor guess.
- `/lockdown` (Owner): kick everyone below `Membership.Tier1`, set `RuntimeGuard.SOUND_ENFORCE = "block"` for the session, beacon `runtime:lockdown`. Reversible with `/unlock`.

### Layer 4 — Telemetry (ADR 0007 phase B+)

`security_event` counters (rogue_sound, script_injected, remote_storm, purge, lockdown) in the aggregate flush, so the Fleet page shows which venues are under attack without anyone reading logs.

## Consequences

- Layer 1 finds the class-B/C/D problems that caused this incident **without touching engine code** and can be run today on every buyer place.
- Layer 2 is a speed bump with evidence: a backdoor can still delete `RuntimeGuard`, but the beacon fires on the first rogue sound before the operator reacts, and `ScriptGuard` sees the dropper. Log-only first release avoids false positives against legitimate third-party sound systems (the venue's own music/lights packs create sounds too — hence the boot snapshot allowlist, not a hardcoded list).
- Register budget: RuntimeGuard is its own `Server/Init` module (adds 1 local to `ServerModuleBag`, none to `Main.server`).
- Non-goals: client anti-cheat heuristics (speed/fly detection) — a club venue has no gameplay integrity to protect, and false kicks cost more than a flyer; hooking `require`; scanning obfuscated code semantically.

## Decisions needed from the owner

1. Default enforcement after one log-only release: `"block"` rogue sounds automatically, or keep it staff-triggered (`/purgesounds`)?
2. Should `ScriptGuard` destroy injected scripts by default (breaks a buyer's legitimate runtime-script loaders) or only beacon?
3. Buyer policy: is "one admin system only, scanned free models only" a delivery requirement (we refuse to ship otherwise) or a recommendation?
4. MovementGuard default: `ENFORCE = "kick"` from the first release (owner's ask) with `EXEMPT_ROLES = {Owner, CoOwner}` and a 1-week log-only window on newly delivered places — or log-only kit-wide first?
5. Foreign-animation rule: keep log-only until the dance catalog allowlist is validated on RUST/NIGHT ZONE, or kick from day one?

## Implementation phases

0. **Now** — run `PlaceSecurityScan` on the attacked place and on Hierapolis; publish the checklist; strip/replace anything CRITICAL.
1. `RuntimeGuard` log-only + beacons (`[Unreleased]`, next kit release). `MovementGuard` + pure `MovementPolicy` (TDD seam: sample pairs → violations) in the same release; kick default per decision 4.
2. Enforcement + `/purgesounds` + `/lockdown` (release after the owner decides).
3. Telemetry counters when ADR 0007 phase B lands.
