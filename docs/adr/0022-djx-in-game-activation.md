# ADR 0022 — DJX standalone: in-game licence activation

**Status:** Accepted. The design was settled with the owner on 2026-10-26.

The in-game half was built the same day and tested in DJX Lite against a Studio stand-in for the licence server (`LicenseApi`, attribute `HazaDJ_LicenseStub`):
- `shared/LicensePolicy` (Lune-tested)
- `server/Services/License` + `LicenseApi` + `Stamp`
- the boot gate in `init.server`, `Commands`, `Roles` and `Sync`
- `client/Features/Lock` and the Settings › License section

Still to do:
- the real VPS endpoints, the account and stamped downloads (ADR 0023)
- obfuscation
**Date:** 2026-10-26

## Context

The standalone DJ booth (ADR 0020, `dj-booth/`) ships with no licence check at all. On 2026-10-23 the owner decided not to obfuscate it (shipped code is removable). The owner now wants a licence the buyer activates **inside the game**, bound to the universe and the place owner.

The leak that matters today: a secret pasted into a place file (like the Club Kit's `Secrets.luau`) travels with every copy of that file. A secret held in the universe's DataStore does not, because DataStore belongs to the universe, not the place file.

## Decided (owner, 2026-10-26)

1. **Product:** DJX standalone first.
2. **Before activation the deck is fully locked**: it does not run at all until activated.
3. **Only the owner activates**: the place's user owner, or the group owner (rank 255) when the place is group-owned. Reuse `Roles.isOwner`.
4. **No legacy path**: every existing DJX install must activate once, on the update that ships this.
5. **Studio is locked too.** Activation therefore needs a published place (`GameId ~= 0`) with Studio API access + HttpService on; the owner can activate from a Studio playtest. `Roles.lookupOwner`'s Studio stand-in branch (`CreatorId == 0`) must not count as an owner for activation.
6. **Grace 7 days.** An activated venue keeps the last-good verdict (stored in DataStore with its timestamp) for 7 days when the VPS is unreachable. Only a definitive VPS denial (revoked / universe or owner mismatch) locks immediately.
7. **Backend = the existing VPS** (`api.hazastudio.id`): reuse the licence tables, beacon → Discord, `rotate-secret` and `rebind`; add a `djx` product and an `activate` endpoint.
8. **Codes are issued manually** from the dashboard, one per sale. Codes are **long and pasted** (owner, 2026-10-26), not short typed codes: the in-game field is a single plain input that strips whitespace and keeps case.
9. **Non-owners see nothing while locked**: no icon, no panel. Only the owner gets the activation popup.
11. **Guest pass = time-limited trial** (owner, 2026-10-26). A second kind of code, redeemed from a "Have a guest pass?" sub-modal on the lock screen. It unlocks the deck for a limited time (e.g. 7 days), then the deck locks again until a normal activation code is entered. The VPS issues it and binds it the same way (universe + owner). The expiry is a server-side timestamp checked locally too, so the 7-day offline grace can never stretch a trial past its end.
    - **No per-venue trial limit:** each new guest pass code gives a new trial. The owner controls this by choosing who gets codes.
    - **Duration is set per code** in the dashboard, default 7 days.
    - **Licence status lives in the Settings page** (Active / Guest pass with time left / Locked). The owner sees it there, with no badge in the header.
    - **When a trial ends:** the Backstage lock screen returns with "Your guest pass has ended." and only the activation-code field. The guest-pass link is hidden.
12. **Every download is stamped** (owner, 2026-10-26).
    - **Format and stamping:** the buyer downloads a `.rbxm` from their account. The VPS copies the release template and stamps that copy (Lune) with the licence data (licence id, buyer Roblox user id) and a fingerprint unique to that download. Every download is logged.
    - **Fingerprint placement:** spread over many inconspicuous points, so removing one is not enough. It never changes how the UI looks.
    - **Activation stays manual — two layers:** the file carries the licence + fingerprint, and the owner still pastes the code in game. The VPS accepts an activation only when the pasted code and the file's embedded licence belong to the same licence.
    - **On a mismatch or a reused code:** the activation is denied and the beacon names the download it came from.
    - **Venue pre-bound at download** (owner, 2026-10-26):
      - The buyer enters their place link before downloading. The VPS resolves the universe + owner through the Roblox API, pre-binds the licence to them, and stamps `universeId`, `placeId` and `ownerId` into the file next to the licence + fingerprint.
      - In game, djX compares the stamp to `game.GameId` and the place owner. A file running anywhere else stays locked and beacons its download id before any code is pasted.
      - The VPS also refuses an activation whose universe/owner differs from the pre-bind.
      - Moving the place or universe means a new download. A move to a group means an admin rebind, then a re-stamped file.
    - **How stamping works:** the VPS keeps one clean template `.rbxm` per release. On each download, Lune (a Linux binary on the VPS) opens a copy, fills the `Stamp` ModuleScript, spreads the fingerprint, and writes a new file. The template is never edited. `.rbxm` is binary and compressed, so plain text replacement cannot work; `.rbxmx` was rejected as larger and readable.
    - **Order with obfuscation:** `Stamp` stays a separate data module outside the obfuscated set. Obfuscation runs once per release; stamping runs per download.
10. **Own test places use dev codes**: normal codes flagged `dev` in the dashboard (excluded from sales), so the owner's places go through the exact buyer path.

## Proposed flow

1. Sale → the VPS issues a one-time activation code.
2. The owner opens the Setup panel in game and enters the code. The server re-checks `Roles.isOwner(sender)` and never trusts the client.
3. Server → VPS `activate` with code + `universe_id` + `place_id` + `creator_id` + `creator_type` + the activating user id. The VPS checks the code is unused, binds it to that universe + owner, and returns a per-venue secret.
4. The secret is stored server-side in a new, versioned DataStore key. From then on: periodic verify, a cached last-good verdict, and a beacon on mismatch (same shape as ADR 0006).

## Known limits

- A thief who edits the server code and spoofs the universe still gets past this. But they now also need a secret that no longer ships in the file. Rotation + DMCA remain the backstop.
- Studio collaborators with edit access can read DataStore from the command bar. Accepted: these are people the buyer trusts.
- Owner/universe change (place moved to a group) → denial → admin `rebind`.
- Requires HttpService on (a locked deck otherwise, consistent with the ADR 0006 boot gate).

## Build halves

1. **VPS (`clubkit-infra`)**: `djx` product, code table (unused / bound / dev / revoked), `POST activate`, verify for djx, dashboard "create code" button.
2. **DJX (`dj-booth/`)**: `License` server service (activate → store secret → verify loop → 7-day cached verdict → beacon), boot gate that keeps every other service down until licensed, owner-only activation popup (1 Header + 1 Body, kit tokens), hide icon/panel for everyone else.
