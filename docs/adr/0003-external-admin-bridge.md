# ADR 0003 — External Admin Bridge (Adonis / Kohl's)

**Status:** Accepted
**Date:** 2026-08-14

## Context

Many club places already run an external admin system (Adonis or Kohl's Admin) for moderation. Club Kit handles club roles/membership/announcements. Buyers wanted a way to keep one admin system for moderation while still letting Club Kit drive the club experience, and they wanted it selectable from `ClubKitConfig`.

The alternatives were:

1. **Fork the external admin** into Club Kit and maintain a custom patched copy. Rejected: creates an unbounded maintenance burden, violates licenses, and breaks whenever the original admin updates.
2. **Ship no bridge** and document manual rank mapping. Rejected: staff drift between Club Kit and the external admin is a daily pain for buyers.
3. **Ship optional, external, no-fork bridge modules** plus a runtime config selector. Accepted.

## Decision

Club Kit exposes a stable, server-only **facade** (`ExternalAdminFacade`) that optional place-pack plugins/addons call. The facade runs Club Kit commands through the same services as chat commands, so permission gates are never bypassed. `ClubKitConfig.ExternalAdmin.Provider` selects `"Adonis"`, `"Kohls"`, or `"None"` at runtime; it does **not** install or remove the admin system itself.

Key rules:

- **No MainModule forks.** Adonis/Kohl's must be installed from official sources by the buyer.
- **No reverse bridge by default.** Being an admin in Adonis/Kohl's does **not** grant Club Kit `canGift`/`adminPanel`. Reverse privilege bridge was explicitly excluded.
- **Membership + Spender roles never sync.** Kohl's `vip` collides with Club Kit `VIP`; leaderboard-driven roles are volatile.
- **Club Kit stays source of truth for staff.** External ranks are a session mirror driven by `Gift:RoleChanged` events.
- **Place-pack is outside engine sync.** It lives in `extras/place-packs/ExternalAdminBridge/` and is installed manually/RBXM, like `SyncBhms`.

## Consequences

- Buyers can pick one admin system and have staff roles stay aligned with Club Kit.
- Engine code is safe when the pack or the admin is missing: facade methods return `disabled`/`unavailable`, and event emissions with no listeners are free.
- Adding a new config section required schema + template + `ConfigBootstrap` updates (consistent with ADR 0001).
- External admin API skew is isolated: detection logic is one function in the facade; command/sync code is in the place-pack.
- Two admins in the same place is supported only as a migration state; the README recommends picking one.
