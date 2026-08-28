# Club Kit 2.10.0 — Upgrade Guide

**From:** 2.9.x → **2.10.0** · **Date:** 2026-08-28 · **Type:** source sync (Update Engine). No RBXM re-import needed.

This release bundles two things: the **CanvasGroup rendering fixes** (panels/toasts/boards going blank on some devices) and a new **license-hardening layer** (ADR 0006) that protects your hand-made place against copying. Your donation data, config, and secrets are untouched.

---

## ⚠ REQUIRED before you update: enable HttpService

2.10.0 will **not boot** if HTTP requests are disabled. This is deliberate (thieves disable HTTP to blind the anti-copy beacon), and legit venues already need HTTP on for donations — but confirm it before you update or your place will show a "Club Kit paused" screen.

1. Roblox Studio → **Game Settings** → **Security**
2. Turn **ON** "Allow HTTP Requests"
3. **Save**

If you skip this, players see a full-screen *"Club Kit paused — enable Allow HTTP Requests in Game Settings → Security, then rejoin"* overlay and nothing else loads. Turn HTTP on and rejoin to fix.

---

## How to update

1. **Enable HttpService** (above).
2. Open your place in Studio, open the **Club Kit** packager panel → **Update Engine**. This replaces the engine folders wholesale; your `ClubKitConfig` and `Secrets` are merged forward, never overwritten.
3. **Ctrl+S** (publish) — nothing the sync does persists until you save.
4. Playtest: confirm the kit boots (`Server initialized … ready` in the console), donations/leaderboards work, and panels open without going blank.

No `ClubKitConfig` changes are required for this release — the new settings all live in engine files with safe defaults.

---

## What changed for you

### Rendering fixes (ADR 0005) — automatic, no action
- Panels, toasts, donation boards, and nametags that could go **blank or flicker** (especially mid-range devices, and heavy places with many posters) now use size-stable motion + a texture-budget guard that culls far-away Workspace boards to free GPU memory.
- **Opt-outs** (engine `Config.luau`, only if you preferred the old behaviour):
  - `Config.UIMotion.CANVAS_GROUP_SIZE_STABLE = false` — restore the old scale-pop animation.
  - `Config.CanvasGroupBudget.ENABLED = false` — disable the far-board culling.
  - Cull distance is `Config.CanvasGroupBudget.SURFACE_CULL_DISTANCE` (default **250** studs). Add attribute `ClubKitKeepSurfaceGui = true` to any SurfaceGui you never want culled.

### Admin Hub — manual Robux now persists
- Previously the Admin Hub's Robux "score edit" only *previewed* (the number vanished on rejoin). It now has a **Cash / Robux toggle** and Robux edits save permanently, exactly like Cash. Owner-tier, same admin-panel gate as before.

### License hardening (ADR 0006) — protects your place
You do not need to configure anything; sensible defaults ship on. Highlights:
- **Copies are now non-functional + traceable.** A place copied to another universe loses its premium features and quietly reports itself (universe, place, owner) to Hazastudio for takedown — this all runs server-side and cannot be read by exploiters.
- **Live-exploiter defence.** A `saveinstance`/injection detector **kicks** the exploiter and logs them. It does **not** brick by default (`Config.AntiTamper.BRICK_ON_DETECT = false`) — leave it off unless you've watched the detector behave in your place; a false brick on a real guest is worse than missing a thief.
- **Watermark + ownership notice** in code and the F9 console (proof for DMCA takedowns).

If your place is ever copied, contact Hazastudio — the leak signal + per-buyer secret rotation let us kill the stolen copy surgically without affecting you.

---

## If something breaks

- **"Club Kit paused" screen / nothing loads** → HttpService is off. Enable it (top of this guide) and rejoin.
- **Premium features (donations/shop/admin commands) off in a legit place** → the license layer may have hard-denied on a bad verdict. Confirm HTTP is on and your `Secrets` are intact; contact Hazastudio if it persists (universe re-bind may be needed after a place transfer).
- **A panel looks wrong after update** → try the `Config.UIMotion` / `Config.CanvasGroupBudget` opt-outs above, and report it.

See [`CHANGED_FILES.md`](CHANGED_FILES.md) for the exact file list, and [`CHANGELOG.md`](../../../CHANGELOG.md) `[2.10.0]` for full technical detail.
