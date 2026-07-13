# Upgrade v2.4.18 → v2.4.19

**Tanggal:** 2026-07-13

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- F9 Developer Console shows Hazastudio ASCII banner + kit version + optional contact (`KitProduct.Support`)
- Production: kit Logger hides DEBUG/INFO/WARN; ERROR shows as red without throwing
- Client Main boot `print`/`warn` noise is Studio-only
- Dev tools: Workspace leaderboard setup checker + runtime probe (Command Bar)

## Breaking / behavior changes

- Live F9 is quieter — WARN from Logger no longer appears in production (use Studio to debug WARN/INFO)
- None for buyer config / remotes / DataStore

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `KitProduct.Support` | Discord / Website / Email / Note | Optional — fill vendor contact for F9 banner |
| Buyer `ClubKitConfig` | — | No required merge |
| Buyer `Secrets` | — | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.19** after Update Engine
- [ ] F9 shows Hazastudio ASCII banner once on join
- [ ] Live: no yellow kit WARN flood; Studio still verbose
- [ ] `log:error` appears red in console without killing the script
- [ ] ClubKitConfig + Secrets unchanged
