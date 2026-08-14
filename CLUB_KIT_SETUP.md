# Hazastudio Club Kit v2.5.2 — Setup Guide

This guide is for **buyers / venue owners** installing the kit in their Roblox place.

---

## Summary: which files to edit?

| Path in Explorer (Studio) | Edit? | Purpose |
|------|-------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` | **YES** | Single place config file (group, shop, roles, donations, etc.) |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets` | **YES** | API secrets (server-only, never sent to client) |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitShowcase` | Optional | **Demo switch** — present = showcase; remove = live |
| `ReplicatedStorage/Hazastudio_ClubKit/` (everything else) | **DO NOT** | Shared engine — replace on kit update |
| `ServerScriptService/Hazastudio_ClubKit/Server/` | **DO NOT** | Server engine |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config` | **DO NOT** | Internal engine (advanced) |

> **Single buyer config source:** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` only. Do not edit `ClubKitDefaults`.

---

## Demo vs live mode

| Condition | Mode | Leaderboard |
|---------|------|-------------|
| `ClubKitShowcase.luau` **exists** & `ACTIVE = true` | **Showcase** | Demo data (fake profiles) |
| File **removed** or `ACTIVE = false` | **Live** | DataStore + Bagi-Bagi API |

You do not need to set `Showcase.Enabled` in `ClubKitConfig` — that is inferred from the showcase file.

**Ship to buyer:** remove `ClubKitShowcase.luau` from the package → live mode immediately.

**Runtime toggle (owner):** `/showcase on` · `/showcase off` · `/showcase status`

---

## Setup checklist (recommended order)

### 1. Branding & group

Edit `ClubKitConfig.luau`:

```lua
Branding = {
    GameName = "Your Club Name",
    WelcomeMessage = "Welcome to %s",
    Greeting = "Welcome to %s",
    -- REQUIRED: replace with your community logo (loading / poster / leaderboard / Join Community modal).
    -- Do not leave the kit default ID (79426970537296) on a live place.
    LogoImage = "rbxassetid://YOUR_COMMUNITY_LOGO_ID",
    -- Top Menu → Community Discord chip. Empty = hide link box.
    DiscordInvite = "discord.gg/your-invite",
},

Group = {
    GroupId = 12345678,        -- Roblox group ID (required for live)
    OwnerUserId = 987654321,   -- place owner userId
    OwnerGroupRank = 255,
},

AdminUserIds = {
    -- [111111] = true,  -- backup admin without group rank
},
```

### 2. Shop membership (Developer Products)

Creator Dashboard → Monetization → **Game Passes** (self-buy VIP/VVIP/Supreme) + **Developer Products** (gift versions).

```lua
Shop = {
    Products = {
        -- BuyGamePassId = one-time self-buy; GiftId = gift Dev Product; BuyId = legacy (optional)
        Tier1 = { BuyGamePassId = 123, GiftId = 456, Price = 1 },  -- VIP
        Tier2 = { BuyGamePassId = 789, GiftId = 101, Price = 1 },  -- VVIP
        Tier3 = { BuyGamePassId = 112, GiftId = 131, Price = 1 },  -- Supreme
    },
},
```

Enable passes/products in the dashboard. `Price` = display price in UI.

### 2b. Paid broadcast (Developer Product)

Players pay Robux via the topbar **Broadcast** icon to send a message to the whole server. Staff with `canAnnounce` can still use `/announce` for free.

Creator Dashboard → Monetization → Developer Products → create **one** product (e.g. "Server Broadcast"), set Robux price.

```lua
PaidBroadcast = {
    ProductId = 3503700307, -- replace with Product ID from Creator Dashboard
},
```

Path: `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` → `PaidBroadcast.ProductId`.

**Important:** this is separate from `Shop.Products` — do not reuse membership BuyGamePassId/GiftId.

Verify: Play test → Broadcast icon → Robux prompt appears. If `ProductId` is still `0`, Output: `[ConfigBootstrap] PaidBroadcast.ProductId is not set`.

### 3. Membership & roles (tier names + ranks)

```lua
Membership = {
    Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
    Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
    Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
},
```

Adjust `RoleCategories`, `SpenderRoles`, and `CommandAliases` if you rename roles.

### 4. Cash donations (IDR/PHP — Bagi-Bagi / Saweria / SociaBuzz)

```lua
Donation = {
    Provider = "bagibagi", -- "bagibagi" | "saweria" | "sociabuzz" — donor name & labels auto-set
    ProviderLink = "https://bagibagi.co/your-page", -- or https://sociabuzz.com/username
    ApiUrl = "https://xxx.workers.dev/game/clubkit-key",
    Currency = "IDR", -- "IDR" | "PHP" — display only (symbol/grouping/chip word); amounts are NOT converted
    Cash = { Enabled = true },
    Robux = { Enabled = true },
    MinAmount = 1000, -- notification + leaderboard threshold (in Currency unit)
    -- Character aura (Robux + cash — cash unit follows Currency)
    AuraTiers = {
        { level = 1, min = 10, idrMin = 0, idrMax = 9999, effect = "Level1", sound = "Level1", duration = 4, cameraDuration = 0 },
        -- min = Robux | idrMin/idrMax = cash range (field name kept for compatibility)
    },
    -- Global world VFX (all cash — unit follows Currency)
    WorldEffectTiers = {
        { min = 100000, effect = "Nuke" },
        { min = 250000, effect = "Smite4" },
        { min = 500000, effect = "BlackHole" },
    },
},
```

**Currency (`IDR` | `PHP`):** display-only — it swaps the symbol/grouping/chip word (`Rp 10.000` vs `₱10,000`, "RUPIAH"/"PESO" chip, "Top Rupiah/Peso Spender" role fallback) across notifications, boards, chips, Admin Hub, and join greetings. It does **not** convert amounts. Match it to how your donation platform actually settles:

- **Saweria** — supports both; register/verify your Saweria account in the matching currency, then set `Currency` to match.
- **Bagi-Bagi** — IDR-only; leave `Currency = "IDR"`.
- **SociaBuzz** — settles per creator's registered country; set `Currency` to match that account.

Switching `Currency` is **display-only and instant** — it does not touch stored totals. If you switch on a `game_key` with existing donation history, old totals just get re-labelled with the new symbol (e.g. old `Rp` totals show as `₱` unchanged). Retune `MinAmount`, `AuraTiers` `idrMin`/`idrMax`, and `WorldEffectTiers` thresholds for the new unit yourself (no auto-convert). Prefer switching **before** you go live, or start a fresh `game_key` if you need a clean break on a live game.

For **SociaBuzz**: set `Provider = "sociabuzz"`, paste `sociabuzz_webhook` from the donation admin panel into TRIBE → Integrations (Webhook URL), fill **Webhook Token** from the URL/admin, then Test Notification. Cash tab title/donor label follow `Provider`.

**Aura vs world (behavior matrix):**

| Source | Character aura | World VFX |
|--------|---------------|-----------|
| **Robux** | Yes (`min` Robux) | **No** |
| **Cash** (Bagi-Bagi / Saweria / SociaBuzz) | Yes (`idrMin`..`idrMax`) | Yes (`min`, unit follows `Currency`) |

Legacy keys `RobuxAuraTiers` / `SaweriaWorldTiers` are still read as aliases.

### 5. Secrets (server)

`ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`:

```lua
Secrets.DonationApiSecret = "secret-from-your-worker"
Secrets.GameDataApiSecret = ""  -- optional, social API
```

Must match the secret in your Cloudflare Worker / backend. **Do not share this file publicly.**

### 6. Feature toggles

```lua
Features = {
    MusicPlayer = true,
    -- Bulk seed tracks from MusicCatalog.luau on server boot (additive).
    MusicCatalogSeed = true,
    Shop = true,
    Leaderboards = true,
    DonationCash = true,
    DonationSaweria = true, -- legacy alias for DonationCash
    DonationRobux = true,
    PromptJoinCommunityOnLoad = true, -- after loading: Join Community modal (skipped if already member; needs GroupId > 0)
    JoinGreetings = true, -- toast Owner/Leadership/Content/top-10 joiners
    DonationWorldEffects = true, -- Nuke/Smite/BlackHole on cash donate; false = no world VFX + hide Settings row
    -- disable unused features: false
},
```

**Update Engine = additive config merge:** after Update Engine, the plugin adds missing `Features` keys (and top-level sections) from schema to `ClubKitConfig` Source — **existing values/keys are not changed**. Set `false` only for features you want off. If the panel shows CONFIG MERGE FAILED, check Output; new rows were not written.

**World effects off:** set `Features.DonationWorldEffects = false` in `ClubKitConfig` for maps that should not show world VFX. Donor aura, announce, and highlight still work. Settings “World Effects” row is hidden too.

**Music catalog (bulk script add):** fill `ReplicatedStorage/Hazastudio_ClubKitConfig/MusicCatalog.luau`. Prefer **grouped playlists** (name once, then tracks). Flat `tracks` with optional `playlistName` still works (default playlist **Legacy**). Multi-part: up to 9 IDs in `parts`. After seed, Manage UI can still edit/move playlists. Disable new merges via `Features.MusicCatalogSeed = false` (existing library remains).

```lua
-- MusicCatalog.luau (preferred)
playlists = {
    {
        name = "Chill",
        tracks = {
            { name = "Song A", creator = "Artist", parts = { "1234567890" } },
            { name = "Song B", creator = "Artist", parts = { "111", "222", "333" }, playbackSpeed = 0.85 },
        },
    },
    {
        name = "HIPHOP & RNB",
        tracks = {
            { name = "Song C", creator = "Artist", parts = { "4444444444" } },
        },
    },
},
```

### 7. Verify rbxm contents (after insert)

The kit **`.rbxm`** already includes:

- Kit GUIs (`StarterGui` — folders `01-` … `15-`)
- Workspace leaderboard boards (`RobuxDonationBoard`, `SaweriaDonationBoard`, etc.)
- `ServerStorage/Tools/` per `toolFolder` in config

Confirm all appear in Explorer after insert.

### 8. Test & publish

Studio → Play test → **File → Publish to Roblox**.

No Rojo/Argon required — edit config directly in Explorer (double-click ModuleScript).

---

## Leaderboard: data source per board

| Board | Needs ApiUrl? | Live source |
|-------|---------------|-------------|
| **Robux** | No | DataStore (VIP purchases / Robux donations) |
| **Community** | No | DataStore |
| **Likes** | No | DataStore (in-game avatar likes) |
| **Bagi-Bagi / Saweria** | **Yes** | HTTP worker + cache |

**Live without API:** Saweria board shows *"Donation API not configured yet"*. Empty Robux/Likes = *"No … yet"* (no data yet), not an API error.

### Manual leaderboard seed (one-time)

Third-party script `tools/OneTimeLeaderboardSeeder/` — initial fill for **Cash**, **Robux**, and/or **Likes** without touching kit engine. Copy to `ServerScriptService`, fill `LeaderboardSeedData.luau`, dry_run → commit, then `/refreshleaderboard all`. Disable (`ENABLED = false`) or remove after use.

Full guide: [`docs/index.html#leaderboard-seeder`](docs/index.html#leaderboard-seeder)

---

## Fake donation commands (admin)

| Command | Effect | Persist? |
|---------|--------|----------|
| `/fakecash [player] <idr> [message]` | Notif + **aura + world VFX** (preview) | ❌ no |
| `/fakerobux [player] <robux> [message]` | Notif + **aura only** (preview) | ❌ no |
| `/testcash` / `/testsaweria` / `/testdonate` | Deprecated alias → `/fakecash` | ❌ no |
| `/testrobux` | Deprecated alias → `/fakerobux` | ❌ no |
| `/addcash <user> <idr>` | Leaderboard + overhead sync | ✅ yes |
| `/setrobux <user> <robux>` | Robux leaderboard | ✅ yes |
| `/donatecash <user> <idr>` | Persist + notif + VFX | ✅ yes |

Use `/fakecash` / `/fakerobux` to test notif + VFX without changing the leaderboard. For manual board fill use `/addcash` or `/setrobux`.

**Showcase (`ClubKitShowcase.luau` active):** low tiers — e.g. `/fakerobux 10` → Level4 aura; `/fakecash 2000` → aura + Nuke. Disable showcase for production thresholds (100k+ world VFX).

---

## Deploy checklist

### Live production

- [ ] `GroupId` + `OwnerUserId` filled
- [ ] `Shop.Products` BuyGamePassId + GiftId filled & active in dashboard
- [ ] `PaidBroadcast.ProductId` filled & product active in dashboard
- [ ] `Donation.ApiUrl` + `Secrets.DonationApiSecret` (if cash donations enabled)
- [ ] `ClubKitShowcase.luau` **removed** (or `ACTIVE = false`)
- [ ] `/showcase status` → OFF
- [ ] Tool folders exist in `ServerStorage/Tools/`
- [ ] Test shop, `/setrole`, leaderboards in Studio
- [ ] Publish

### Demo / trailer only

- [ ] Keep `ClubKitShowcase.luau`
- [ ] ApiUrl not required for demo-filled boards
- [ ] Before go-live: remove showcase file + configure API

---

## Quick troubleshooting

| Issue | Fix |
|-------|-----|
| Shop warning BuyGamePassId `0` | Fill IDs in `Shop.Products` |
| `PaidBroadcast.PRODUCT_ID is still 0` | Create broadcast Developer Product → fill `PaidBroadcast.ProductId` |
| Saweria "API not configured" | Fill `ApiUrl` + `DonationApiSecret` |
| Robux/Likes "No … yet" | Normal — no donations/likes in DataStore yet |
| Manual leaderboard fill | `/addcash` or `/setrobux` — not `/fakecash` |
| Board blank with no text | Add `LoadingOverlay` to place SurfaceGui template |
| `Group.GROUP_ID invalid` | Fill `GroupId` or enable showcase |

---

## Important commands

### Preview (non-persist) — admin

| Command | Purpose |
|---------|---------|
| `/fakecash [player] <idr> [message]` | Notif + aura + world VFX; board **unchanged** |
| `/fakerobux [player] <robux> [message]` | Notif + aura only; board **unchanged** |
| `/testcash` / `/testsaweria` / `/testdonate` | Deprecated alias → `/fakecash` |
| `/testrobux` | Deprecated alias → `/fakerobux` |

### Persist — owner (or Studio bypass)

| Command | Purpose |
|---------|---------|
| `/donatecash <player> <idr> [msg]` | Persist + notif + VFX |
| `/addcash <player> <idr>` | Persist cash leaderboard only (no VFX) |
| `/removecash <player> [idr]` | Manual IDR removal (alias: `/removebagibagi`). Studio: `/removecash me` clears self |
| `/setrobux <player> <robux>` | Persist Robux leaderboard (no VFX) |
| `/removerobux <player> [robux]` | Remove Robux LB entry. Studio: `/removerobux me` clears self |

### General

| Command | Access | Purpose |
|---------|--------|---------|
| `/setrole <player> <role>` | canGift | Set role |
| `/gift <player> <tier>` | canGift | Grant membership |
| `/showcase on\|off\|status` | owner | Toggle demo leaderboard |
| `/refreshleaderboard all` | owner | Refresh boards |

---

## Posting this guide to Discord

**Full detail (14 messages):** open **[DISCORD_SETUP_MESSAGES.txt](DISCORD_SETUP_MESSAGES.txt)** — copy each block `MESSAGE 1/14` … `MESSAGE 14/14` → send one at a time in `#setup` → pin MESSAGE 1.

**Short (1 message):** **[DISCORD_SETUP_POST.txt](DISCORD_SETUP_POST.txt)**

**Full file:** attach `CLUB_KIT_SETUP.md` to the first message.

---

## Explorer structure (after rbxm insert)

```
ReplicatedFirst/
└── Hazastudio_ClubKit/
    └── LoadingBootstrap.client

ReplicatedStorage/
├── Hazastudio_ClubKit/              ← engine (do not edit)
│   └── Shared/Config/
│       └── ClubKitShowcase          ← remove for live
├── Hazastudio_ClubKitConfig/        ← EDIT
│   └── ClubKitConfig
└── WorldEffects/                    ← donation VFX models

ServerScriptService/
├── Hazastudio_ClubKit/
│   └── Server/
│       └── Main.server
└── Hazastudio_ClubKitSecrets/       ← EDIT
    └── Secrets

StarterPlayer/StarterPlayerScripts/
└── Hazastudio_ClubKit/
    └── Main.client

StarterGui/                          ← folders 01- … 15- (kit GUIs)
ServerStorage/Tools/                 ← STAFF, VIP, DONOR, …
Workspace/                           ← RobuxDonationBoard, SaweriaDonationBoard, …
```

---

Hazastudio · Club Kit v2.5.2
