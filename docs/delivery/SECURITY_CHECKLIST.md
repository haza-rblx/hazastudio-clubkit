# Venue security checklist (buyer + Hazastudio, per place)

Run at delivery and after every free-model / admin-system change. Background: `docs/adr/0008-runtime-integrity-abuse-defense.md`.

## Before publish

- [ ] Run `tools/security/PlaceSecurityScan.luau` in Studio. **Zero CRITICAL** (`require(<id>)` to anything but a named, known module). Every HIGH explained or removed.
- [ ] **One admin system.** Kohl's *or* Adonis, never both. Delete the other loader (Workspace **and** ServerScriptService — loaders hide in both).
- [ ] Admin rank thresholds: no command tier reachable by group rank ≤ 1 / "Member". `:music`, `:sound`, `:kick`, `:ban` are Admin+ only. Admin user-id lists contain only current staff.
- [ ] No `Discord` / webhook scripts in the place. Kit beacons and donation alerts go through the VPS forwarder instead (Discord blocks Roblox server IPs anyway).
- [ ] Free models: scan **before** inserting; prefer vendored copies (the model's code lives in the place, not behind a `require(id)`).
- [ ] Non-kit `RemoteEvent`s from the scan's inventory: each has a server-side permission check *and* a rate limit, or is removed.
- [ ] HttpService: on (kit needs it — ADR 0006), but the scan's `HttpService call` list is understood.
- [ ] Game Settings → **Avatar**: scale ranges pinned (height 0.9–1.05, width 0.7–1.0, head 0.95–1.0) so oversized bodies cannot come from the avatar editor; `LoadCharacterAppearance` stays on (AvatarGuard needs the real description).
- [ ] Venue-owned audio assets set to **private + granted to this experience only** (Creator Dashboard → asset privacy), so copies of the place lose the music.

## Accounts

- [ ] Every collaborator with Edit access on the place is current staff; 2-step verification on all of them.
- [ ] Group: rank audit — who holds Dev/Admin/Owner ranks, and does any external admin map those ranks to commands?
- [ ] Kit `AdminUserIds` and `SystemRoles.Owner`/`OwnerUserId` reviewed.

## When something happens

1. `/purgesounds` (Staff+, when RuntimeGuard ships) — or, today, Owner runs in the server console: stop every `Sound` not in the kit/venue folders.
2. Note the player name + time; the kit beacon (if RuntimeGuard is on) has the sound id and path.
3. Re-run the scan; a backdoor that *drops* scripts shows up as new `Script` instances outside the kit.
4. Rotate the game secret on the dashboard if the place was copied (`POST /admin/games/{key}/rotate-secret`).
