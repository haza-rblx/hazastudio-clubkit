# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.8.4` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|
| Text filtering compliance (ToS audit fix) | Released in 2.6.7 | |
| VIP-on-join (`VipOnCommunityJoin = true`) | Place-specific, not engine — set manually per place | |
| Emote AnimationId (hash → numeric) | Place-specific content, done manually in KASTA | |

---

## File changes (unreleased)

| Path | Change |
|------|--------|
| **Backdrop blur off + ACM community cover off (this session, on RUST place)** | |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.PanelBlur.ENABLED` true → **false** (kill all panel backdrop blur globally; camera zoom still works). Leftover active `Blur` effect in Lighting also disabled |
| `src/.../Client/UI/AvatarContextUI.luau` | `_setCommunity` hard-sets `communityCover.Visible = false` (community cover background permanently hidden; small community badge/logo still shows). Root cause of "cover keeps reappearing": `_setCommunity` re-showed it on every community payload |
| **AdminPanelv2 CanvasGroup→Frame redesign compat (this session, on RUST place)** | |
| `src/.../Client/UI/AdminPanelUI.luau` | `inputCanvas` accepts `CanvasGroup` OR `Frame` (`FindFirstChild("CanvasGroup") or FindFirstChildWhichIsA("Frame")`) + clear error if neither — fixes infinite `WaitForChild("CanvasGroup")` **hang** after `2-InputTitle.CanvasGroup` was redesigned to a plain Frame. Verified: `new()` constructs + `show()`/`hide()` succeed |
| **Hotbar not restoring after ACM close (this session)** | Root cause: `InventoryChromeAnimator.setupAcmWatcher()` only watched `AvatarContextMenu` (v1); on v2 (`AvatarContextMenuV2`) the watcher observed a GUI that never opened → `notifyShow("acm")` never fired → hotbar stayed hidden |
| `src/.../Client/Services/InventoryChromeAnimator.luau` | `setupAcmWatcher()` now watches BOTH `AvatarContextMenu` (v1) and `AvatarContextMenuV2` (v2) via a shared `watchGui(name)` helper. Verified in playtest: hotbar hides on open (`Visible=false`) and restores on close (`Visible=true`) |
| **Donation text filter: online-player author fallback (2026-08-22, diagnosed on vicenorth)** | Root cause of "pager semua" (`#####` on every provider message): Roblox `FilterStringAsync` errors **"sender must be connected to the current server"** — the filter author MUST be an online player. On group-owned places (vicenorth group `407577344`) where the donor AND the game owner are both offline, the old fallback `userId=1` (later owner) was offline → every filter call failed → `censoredMessageFallback` → all messages censored |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/DonationService.luau` | `resolveTextFilterUserId()` now: donor's own userId when donor is ONLINE → else **any currently-online player** (`Players:GetPlayers()[1].UserId`) as the broadcast author → else `nil`. Returns `number?` (was `number`). Verified in playtest: `filterForBroadcast(onlinePlayer, "halo ini pesan test donasi")` returns clean uncensored text; notif renders message intact instead of `#####` |
| **Reliability v3: two-stage delivery + owner command channel (2026-08-22, on KASTA)** | |
| `Config.luau` | New `Config.Donation.REMOTE_NOTIF_DISPLAY = "DonationNotifDisplay"` remote (stage-2 display confirm, fired when the notif actually renders vs ack-at-enqueue) |
| `Server/Main.server.luau` | Create + wire `DonationNotifDisplayRemote` alongside the existing ack remote |
| `Server/Services/DonationService.luau` | (1) `handleNotifDisplay` + `flushDisplayQueue` → POST `/v3/delivery-display` (stage-2 "sudah tampil"). (2) **Owner command channel**: `_pollCommands()` pulls `GET /v2/commands` on the existing donation poll loop and executes `fake_notif` (testOnly preview), `manual_adjust` / `set_total` (silent cash correction), `retry_donation` (re-broadcast), then acks via `POST /v2/commands/ack`. (3) `fireFakeNotifPresentation` resolves Roblox identity (userId/username/displayName) from the server-resolved command payload — no in-game name lookup, so retry/fake notifs show the real display name + thumbnail, and the text filter runs under a real connected author (fixes `####` pager + blank profpic). |
| `Client/Controllers/DonationNotificationController.luau` | Fire `DonationNotifDisplay` at `showNotif` render start (stage-2 display ack), alongside the existing enqueue ack. |

---

## Backlog (not scheduled)

- **Packager `collect()` bundles installed admin loaders** (`Adonis_Loader` / `Kohl's Admin`) into the main template pack — these are buyer-choice and should be excluded like BHMS. Caused a leftover Kohl's to ship into a buyer place. Consider adding admin loaders to the Packager exclusion list.
- **Overhead cash-rank chip can be assigned to the wrong player** — observed on Atlantis: hazatargz showed `#12 RUPIAH` while having `cash_total=0` in the backend (rank #12 is a different, unlinked donor). Likely in rank-matching/`assignPlayer` name-fallback path in `DonationService`. Separate from the v2.6.5 webhook fix. Needs its own diagnosis.

---

## On release — agent checklist

1. [ ] User confirms version number
2. [ ] Move `[Unreleased]` in `CHANGELOG.md` to new version section + date
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset unreleased table in this file
7. [ ] Git tag: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** from `tools/ClubKitPackagerPlugin` (plugin-build sync alone is not enough if the place Tool still uses an old binary)
