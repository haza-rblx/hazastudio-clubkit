# Upgrade v2.6.6 → v2.6.7

Luau engine-only update — source sync, no RBXM needed.

## Quick steps
1. Backup `ClubKitConfig` + `Secrets` (standard precaution; this update does not touch them)
2. In Studio: Plugin → **Engine → Update Engine** → Save place

## What's new
- **Text filtering compliance hardening (Roblox ToS)** — all player-supplied and external free-text surfaces now pass through Roblox text filtering before they are stored or shown to other players. Full policy: `docs/adr/0004-text-filtering-policy.md`.
- **New canonical filter module** — `Shared/Utils/TextFilterUtil.luau`. All 8 previously duplicated inline filter implementations now route through one module.

## Specific gaps closed
- **`/status` text above heads was never filtered** — now filtered at write; overhead only renders filtered text.
- **Profile bio/status re-filter used the wrong author** — now filters with the writer's userId per viewer.
- **External donor nicknames on workspace boards** — filtered (memoized per name); on failure shows `####` mask, never raw.
- **Music manage names/creators** — filtered before storing; failed filter rejects the edit.
- **Community board name from the donation worker** — filtered before DataStore write.
- **Robux donation name fallback** — no longer falls back to raw display name on filter failure.

## Config changes
- None required. `ClubKitConfig` fill-forward will not change your existing values; no new keys.

## QA after upgrade
- [ ] `/status testing` — check overhead shows filtered text (not raw input if filter fails)
- [ ] `/setbio testing` — check ACM popup shows filtered text
- [ ] `/announce testing` — check broadcast shows filtered text
- [ ] `/fakecash me 50000 test` — check donation notification shows filtered donor name/message
- [ ] Console: no new TextService quota warnings; existing flows unchanged

## Notes
- **Place-specific config not included**: `Features.VipOnCommunityJoin = true` (VIP-on-join fix from this session) is place-specific and must be set manually per place if desired. Default stays `false` in engine.
- **Emote AnimationId fix** (from this session): place-specific content change (already done manually in KASTA). Not part of engine release.
