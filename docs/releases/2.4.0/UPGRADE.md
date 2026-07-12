# Upgrade v2.3.1 → v2.4.0

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Place GUI (required for new features):**
   - Join community modal: `16-JoinCommunPrompt` (StarterGui / kit GUI)
   - Join greetings toast: `GreetingNotifications` / `GeneralGreetings` (CanvasGroup template)
4. **Optional config merge** in buyer `ClubKitConfig` (source sync does **not** replace it):
   - `Features.JoinGreetings = true` (or `false` to disable)
   - Confirm `Features.PromptJoinCommunityOnLoad` still set as desired
5. **Tidak** replace `Secrets`

## What's new

- **Join greetings** — toast when Owner / Leadership / Content / top-10 Robux or cash spender joins (once per session); motion matches GenericBroadcast
- **Join community modal** — custom `16-JoinCommunPrompt` with Shop/Gift center-panel animation instead of immediate CoreGui prompt

## Breaking / behavior changes

- **Join community on load (behavior change vs v2.3.1):**
  - No longer auto-opens Roblox CoreGui `PromptJoinAsync` after ~0.75s
  - After load / `enterGameplay`, waits **2s**, then shows `16-JoinCommunPrompt` **only if the player is not already in the group**
  - Already a member → **skip entirely** (no modal, no CoreGui)
  - Join CTA → dismiss modal first → then `GroupService:PromptJoinAsync`; Close → dismiss only
  - Missing `16-JoinCommunPrompt` GUI → warn + skip (**no** CoreGui fallback)
- **Join greetings** need place GUI `GreetingNotifications` / `GeneralGreetings`; without them, greetings will not show

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync — merge Feature flags manually.

## Config notes

| Path | Field | Default |
|------|--------|---------|
| `ClubKitConfig.Features` | `JoinGreetings` | `true` (kit template) |
| `ClubKitConfig.Features` | `PromptJoinCommunityOnLoad` | `true` (unchanged gate; UX changed) |
| Engine `Config.FeatureFlags` | `JoinGreetingsEnabled` | `true` |
| Engine `Config.FeatureFlags` | `PromptJoinCommunityOnLoadEnabled` | `true` |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.0** after Update Engine
- [ ] Not in group + Feature on: after ~2s, `16-JoinCommunPrompt` appears; Join opens CoreGui after dismiss; Close dismisses only
- [ ] Already in group: no modal / no CoreGui prompt
- [ ] Missing JoinCommun GUI: warn in output, no CoreGui fallback
- [ ] Eligible joiner (Owner/Leadership/Content/top-10): all clients see greeting toast once
- [ ] `Features.JoinGreetings = false` or `PromptJoinCommunityOnLoad = false`: respective feature off
- [ ] `GroupId = 0`: join community prompt skipped
