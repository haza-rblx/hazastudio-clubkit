# Hazastudio Club Kit v2.4.73

Roblox club kit with per-place configuration. Roles, membership, spenders, donations, shop, and feature toggles — without touching the core engine.

## Documentation

| Resource | Description |
|----------|-------------|
| **[docs/index.html](docs/index.html)** | Interactive documentation (open in browser) |
| **[CLUB_KIT_SETUP.md](CLUB_KIT_SETUP.md)** | Setup summary + how to post to Discord |
| **[DISCORD_SETUP_MESSAGES.txt](DISCORD_SETUP_MESSAGES.txt)** | **14 Discord messages** — copy one at a time (full detail) |
| **[DISCORD_SETUP_POST.txt](DISCORD_SETUP_POST.txt)** | Short single-message summary |

## Quick start

1. Insert the Club Kit **`.rbxm`** file into your place in Roblox Studio
2. Edit `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
3. Edit `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` (if using API)
4. Play test → publish

Empty template fields (`GroupId = 0`, `ApiUrl = ""`, shop IDs `0`) are **intentional** — fill them at deploy time.

## Buyer files (do not replace when updating the kit)

- **Hazastudio_ClubKitConfig/ClubKitConfig.luau** — per-place venue config
- **Hazastudio_ClubKitSecrets/Secrets.luau** — API secrets (server-only)

The core engine lives in **Hazastudio_ClubKit** (ReplicatedStorage, ServerScriptService, StarterPlayerScripts, ReplicatedFirst) — replaceable on rbxm update.

Do not edit `Hazastudio_ClubKit/Shared/Constants/Config.luau` unless advanced (Studio DataStore isolation).

## Deploy (rbxm)

The kit is shipped as an **`.rbxm`** file — Rojo/Argon not required.

1. Studio → **Home → Insert from File** → select rbxm
2. Edit buyer config in Explorer
3. Play test → **File → Publish to Roblox**

**Kit update:** back up `ClubKitConfig` + `Secrets` first, remove old `Hazastudio_ClubKit` folders, insert new rbxm, restore config if needed.

## Showcase mode

For screenshots/trailers without live data:

```
/showcase on    # owner only
/showcase off
/showcase status
```

Production: remove `ClubKitShowcase.luau` for live mode (or set `ACTIVE = false` inside the file).

---

Hazastudio · Club Kit v2.4.73
