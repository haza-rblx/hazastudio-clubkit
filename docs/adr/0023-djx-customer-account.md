# ADR 0023: djX customer account on the shared VPS

**Status:** Accepted, direction only (owner, 2026-10-26). Nothing built.
**Date:** 2026-10-26

## Context

djX is sold as its own product under a different studio brand ("djX Dual Deck by kosmik"; see `docs/plans/djx-promo-site/`). Activation (ADR 0022) already depends on the Hazastudio VPS. The owner wants buyers to log in after the marketing page and manage everything from one account, the way Club Kit buyers use the clubkit-infra customer dashboard. It should be the same VPS and the same domain (`hazastudio.id`), but a separate product.

## Decided

1. **Login with Roblox** (official OAuth). The logged-in Roblox user is the identity the licence already binds to (ADR 0022: universe + owner). Activation and the account match without a second identity. For a group-owned place, the account that can act is the group owner (rank 255), the same rule as `Roles.isOwner`.
2. **One login, separate products.** A person with both Club Kit and djX signs in once. Each product has its own pages and its own data. djX pages never show Club Kit venues, and the reverse also holds.
3. **Address `djx.hazastudio.id`**, served by the same VPS as the Club Kit dashboard and the licence API.
4. **Account scope (v1):**
   - Licences and guest passes: per-venue status, trial time left, activation codes.
   - Updates and downloads: latest djX version, changelog, update files.

   Live server / DJ-activity monitoring is out of scope for now.

## Consequences

- The promo page's claim "no external server" is no longer true once activation ships. It must be reworded (the deck itself still runs in-game; only licensing talks to the VPS).
- Roblox OAuth needs an OAuth app registered with Roblox plus a redirect on `djx.hazastudio.id`. Both are infra work in `clubkit-infra`.
- Sharing login with Club Kit means a shared `accounts` (Roblox user id) table with per-product licence tables. The Club Kit dashboard's current login must be checked before building, so the two can meet.

## Open

- How the current Club Kit dashboard authenticates (it decides whether "one login" is a migration or a fit).
- Where update files are hosted and how a buyer installs them (rbxm download vs. package).
