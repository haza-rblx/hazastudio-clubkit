# ADR 0012 — Foreign GUI report: name the window, do not punish it

**Status:** Accepted — implemented 2026-09-16, unreleased. Cross-repo (kit + `clubkit-infra`).
**Date:** 2026-09-16

## Context

Most exploiters in Indonesian club places run a **GUI-based executor** — the tool is a window
on screen, not a headless script. The owner asked for a signal built on that shape: whatever
GUI was not registered at boot is suspicious. Their follow-up set the bar for what the signal
has to produce:

> "coba agar kita tidak menebak, laporan di discord harus menyertakan spesifik nama gui/script nya."

So a report that says "something appeared" is worthless. It has to name the GUI and the scripts
inside it, or there is nothing to act on and nothing to learn from.

### The measurement that decides the whole design

`game:GetService("CoreGui")` **returns nil at LocalScript identity** in this place (measured live
in the client VM, 2026-09-16). Kit code cannot see CoreGui, and it cannot see a `gethui()`
container either — that is where a competent executor parks its window, precisely because game
code cannot reach it.

**The detector can therefore see `PlayerGui` and nothing else.** A quiet log means "nothing
foreign landed in PlayerGui", never "this client is clean". Every comment in the shipped code
says this, because the first person to read a week of empty reports will otherwise conclude the
place is clean, and they will be wrong.

What is left is still worth having: the lazy tier of executor (and every "free admin GUI" a
player pastes into the console) does parent its window to `PlayerGui`, and we currently know
nothing at all about what runs in these places.

### What the false positives look like

This place alone carries non-kit GUIs — `1000-01-CT-ADDON`, `DanceGui` (BHMS pack),
`AvatarContextMenu`, `IconGroup` — and other buyer places run Adonis or Kohl's. The kit itself
creates GUIs at runtime (`TopbarStandard`, `99-NotificationCenter`, `CinematicDockBarsGui`, …),
and every `ResetOnSpawn` GUI is re-cloned out of `StarterGui` on each respawn. A naive
"anything new is an exploit" check would report all of it, on every honest player.

## Decision

1. **The signal reports and nothing else. There is no kick, no brick, and no knob to add one.**
   Not "default off" — absent. A client-side detector that ejects a paying guest is exactly the
   failure `SaveInstanceGuardService`'s own comment warns about, and we have zero field data
   about what actually appears in a live club. The report *is* the product of this change.

2. **Reach is `PlayerGui` only, and that is stated in the code, the config template and the
   Discord alert itself.** The alert text names CoreGui so the owner is never invited to read a
   quiet channel as an all-clear.

3. **Allowlist = boot snapshot + StarterGui + kit runtime GUIs + buyer list.** After a
   configurable grace period (`FOREIGN_GUI_GRACE_SECONDS`, default **20 s**) every child of
   `PlayerGui` is legitimate forever. On top of that, any name that exists in `StarterGui` is
   allowed — that single rule covers respawn re-clones, the kit's own StarterGui fallbacks, and
   every buyer-installed GUI, without anybody maintaining a list. The kit's runtime-created GUI
   names are a constant in the service; buyers add their own through
   `AntiTamper.ForeignGuiAllowNames`, in the spirit of `RuntimeGuard.SCRIPT_ALLOW_PARENT_NAMES`.

4. **The payload is hostile input and is treated as such server-side.** Any player can fire
   `SecuritySignals.ReportTamper` directly with any table. `Shared/Domain/ForeignGuiPolicy`
   holds the caps and the sanitiser; the client applies them as a courtesy and **the server
   re-applies every one of them** to what it receives. `apps/api` applies them a third time,
   because a stolen secret can POST to `/v2/beacon` with the kit removed from the picture.

5. **Sanitising rules** (`ForeignGuiPolicy.sanitize`, mirrored by `beaconText` in
   `license-routes.js`): backtick → `'` (it would close the fenced code block the embed renders
   this inside); `@` → `(at)` (kills `@everyone`, `@here` and `<@id>` in one rule); control
   characters → space; non-ASCII → `?`, collapsed. The last one is deliberate and costs us
   readability of non-Latin GUI names: it makes truncation safe (no split UTF-8 sequence to
   break `JSONEncode`), and it removes homoglyph and RTL-override disguises. A forged
   `@everyone` payload arrives in Discord as the literal text `(at)everyone`, inside a code
   block, in a webhook that now posts with `allowed_mentions: { parse: [] }`.

6. **Caps** — chosen so one exploiter cannot turn the alert channel into their toy:
   5 script names per GUI, 64 characters per name, 480 characters per detail string
   (Discord's field limit is 1024 and the fence costs 8, so better than 2× headroom),
   3 distinct GUIs per player per session, 8 per server, and a ceiling of 24 distinct tamper
   beacon keys per server in `LicenseService`. `TamperGuard` also hard-stops at 20 remote fires
   per player per session before it parses anything.

7. **The beacon key is per GUI name** (`foreign_gui:<sanitised name>`), because "which tools
   show up" is the question being asked; the budgets above are what keeps that key space
   bounded. `TamperGuard`'s old `seen[userId]` (one report per player, any kind) is now a budget
   per signal kind, so a saveinstance hit can no longer swallow a foreign-GUI report.

8. **Buyer privacy: only post-boot additions ever leave the place.** GUI names are a buyer's
   own build. The boot snapshot — i.e. the venue's actual GUI inventory — never leaves the
   client. The vendor learns "a window called X appeared in this place after loading", not what
   the place is made of. The buyer can switch the whole thing off with one boolean, and the
   template says so in plain words.

## Consequences

- We get data we have never had: real names of the tools players bring into club places, per
  place, with the scripts inside them.
- We get false positives, and they are cheap — a Discord line, never a kicked guest. Each one
  teaches us a name for `ForeignGuiAllowNames` or a bug in the grace period.
- A buyer's Discord-visible GUI names travel to the vendor. That is a real disclosure and is
  why point 8 exists and why the switch is in the buyer's own file.
- The signal is bypassed trivially by any executor that uses CoreGui/`gethui()`. We accept
  that; the alternative is nothing.
- `license_beacons` grows a nullable `detail` column (migration `0024`). Old rows and every
  non-tamper beacon keep it `NULL`.

## What would justify enforcement later

Enforcement is revisited only with **log evidence**, not intuition. Concretely: a month of
reports in which (a) the same GUI names recur across multiple buyer places, (b) those names do
not appear on players who are otherwise behaving (cross-check against `runtime:*` and
`movement:*` beacons from ADR 0008), and (c) no report in that month turned out to be a
legitimate place add-on. Even then the first step is a *warning*, not a kick, and it ships
behind a config value that is off by default — the same ladder `MovementGuard` and
`RemoteStorm` are still on.

## Alternatives considered

- **Name-blacklist scanning** ("Synapse", "KRNL", …). Trivially defeated by renaming, and it
  fires on innocent names. The whole point of an allowlist-at-boot is that it needs no
  knowledge of the tool.
- **Report the whole PlayerGui inventory at boot.** Far better forensics, and unacceptable: it
  ships a buyer's GUI list to the vendor on every join.
- **Kick on first foreign GUI.** Rejected by the same argument that keeps `BRICK_ON_DETECT`
  off (ADR 0006) and `MovementGuard` in `"log"` (ADR 0008): no field data, and the cost of a
  wrong answer lands on a paying guest.
- **Send the composed detail string from the client.** Rejected — the server then has to trust a
  string it cannot re-derive. The client sends a structured table; the **server** composes the
  text that reaches Discord.

## Addendum — 2026-09-17: off in Studio; the privacy wording

**Off in Studio.** `ForeignGuiGuardService.start` returns before taking its snapshot or watching
`PlayerGui` whenever `RunService:IsStudio()` is true. A playtest creates GUIs the place never
ships (plugin panels, MCP harnesses, a developer's scratch ScreenGui), and every one of them would
otherwise beacon the vendor's Discord as an exploit window. The server half is unchanged — a
`ForeignGuiReport` fired at a Studio server is still sanitised and budgeted — so the gate is only
on the client that would send it. Consequence for testing: the one live end-to-end fire this ADR
still owes has to come from a real client in a published place, not from a Studio session.

**The privacy line is decision 8's, verbatim: the boot snapshot never leaves the *client*.** The
buyer template's comment said "never leave the server", which is the wrong half — the server never
holds the snapshot at all; only post-boot additions are sent, and only their names. The template
comment is being corrected to match (code review, 2026-09-17); this ADR and `CONTEXT.md` say
"client".
