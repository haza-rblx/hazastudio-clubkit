# Hazastudio Clubkit v1.3

Roblox club kit dengan config terpisah per place. Role, membership, spender, donation, shop, dan feature toggles — tanpa sentuh core engine.

## Dokumentasi

| Resource | Deskripsi |
|----------|-----------|
| **[docs/index.html](docs/index.html)** | Dokumentasi interaktif (buka di browser) |
| **[CLUB_KIT_SETUP.md](CLUB_KIT_SETUP.md)** | Ringkasan setup + cara kirim ke Discord |
| **[DISCORD_SETUP_MESSAGES.txt](DISCORD_SETUP_MESSAGES.txt)** | **14 pesan Discord** — copy satu per satu (super lengkap) |
| **[DISCORD_SETUP_POST.txt](DISCORD_SETUP_POST.txt)** | Ringkasan singkat 1 pesan |

## Quick start

1. Insert file **`.rbxm`** Club Kit ke place di Roblox Studio
2. Edit `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
3. Edit `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` (jika pakai API)
4. Play test → publish

Field kosong (`GroupId = 0`, `ApiUrl = ""`, shop IDs `0`) **sengaja** di template — isi saat deploy.

## Buyer files (jangan replace saat update kit)

- **Hazastudio_ClubKitConfig/ClubKitConfig.luau** — config venue per place
- **Hazastudio_ClubKitSecrets/Secrets.luau** — API secrets (server-only)

Core engine ada di folder **Hazastudio_ClubKit** (ReplicatedStorage, ServerScriptService, StarterPlayerScripts, ReplicatedFirst) — replaceable saat update rbxm.

Jangan edit `Hazastudio_ClubKit/Shared/Constants/Config.luau` kecuali advanced (Studio DataStore isolation).

## Deploy (rbxm)

Kit dikirim sebagai file **`.rbxm`** — tidak perlu Rojo/Argon.

1. Studio → **Home → Insert from File** → pilih rbxm
2. Edit config buyer di Explorer
3. Play test → **File → Publish to Roblox**

**Update kit:** backup `ClubKitConfig` + `Secrets` dulu, hapus folder `Hazastudio_ClubKit` lama, insert rbxm baru, restore config jika perlu.

## Showcase mode

Untuk screenshot/trailer tanpa data live:

```
/showcase on    # owner only
/showcase off
/showcase status
```

Production: hapus `ClubKitShowcase.luau` untuk live mode (atau set `ACTIVE = false` di dalam file).

---

Hazastudio · Clubkit v1.3
