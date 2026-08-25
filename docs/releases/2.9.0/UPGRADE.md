# Upgrade v2.8.9 → v2.9.0

Reliability release: three silent-failure bugs fixed (settings option buttons, `/announce`, vote-skip timer), an AFK auto-rejoin reliability overhaul, and a new UI image warm-up system to remove first-open pop-in. No breaking changes — everything defaults to current behavior.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (they are never replaced by Update Engine).
2. In Studio: Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine** → Save place.
3. Done — no new buyer config fields to review this release.

## What's fixed
- **Settings option buttons (e.g. Graphics "Overall Quality") were completely dead** on any place whose GUI wrappers were redesigned from `CanvasGroup` to plain `Frame` — labels showed placeholder text and clicks did nothing. Fixed to identify the button container by content instead of class/position.
- **`/announce` and paid broadcasts silently stopped rendering** under the same CanvasGroup→Frame redesign — the broadcast wrapper's type check now accepts any `GuiObject`.
- **The vote-skip modal closed after ~1 second instead of 15** — a stale config value never matched the code's own fallback. Fixed to 15s.
- **AFK auto-rejoin could fail permanently after one bad attempt**, leading to an avoidable 20-minute idle disconnect. The rejoin flow now escalates across 4 timed attempts (same-server first, then any-server) instead of one, and no longer gets starved by its own rate limiter.
- **Donation notification / rejoin reliability edge cases**: a notification-center hiccup could no longer silently swallow an AFK rejoin attempt; a teleport that never actually happened is no longer reported as a success.

## What's new
- **UI images now warm up during the loading screen** instead of popping in blank the first time a panel is opened (settings icons, badges, topbar chrome, and anything authored directly into your GUIs). Purely internal — nothing to configure unless you want to tune `Config.ImagePreload`.
- **Grouped-list corner rounding** for settings/profile rows — the first row in a group rounds its top corners, the last rounds its bottom, middle rows stay square, matching common grouped-list UI conventions.

## Config changes
- New `Config.ImagePreload` table (batch size, timeouts, fade duration). Safe defaults; no action needed.
- New `Config.AfkGuard.REJOIN_LADDER` (4-step escalation) replaces the old single-threshold + attempt-counter fields. Old fields (`MAX_RETRY`, `RETRY_DELAY_SEC`, `CLIENT_RETRY_BACKOFF_SEC`, `MAX_CLIENT_ATTEMPTS`) are kept as harmless no-ops if your place set them manually — no migration needed.
- Amendment to ADR 0004: unlinked donor nicknames on the **cash workspace board only** now display raw (unfiltered) instead of risking false-positive censorship (`####`). Every other filtered surface (donation messages, bio, `/status`, music names, community name, linked donors) is unchanged.

## QA after upgrade
- Open Settings → Graphics → confirm "Overall Quality" buttons show Low/High/Balance labels and clicking one switches the selection.
- Run `/announce test message` (or trigger a paid broadcast) → confirm the announcement card appears in the notification center.
- Start a vote-skip → confirm the modal stays open for the full countdown, not ~1 second.
- Open a menu panel for the first time in a session → icons should appear immediately, not blank-then-pop.
