# Upgrade v2.4.16 → v2.4.17

**Tanggal:** 2026-07-13

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- Music topbar: horizontal menu with **Music Player** + **Load Track** (hard audio resync without rejoin)
- TopbarPlus labels use **Inter**; Menu button shows **"Menu"** text
- VIP on community join mid-session recovery; overhead respawn placeholder fixes

## Breaking / behavior changes

- Music topbar: one extra click to open the player (icon → Music Player). Parent click opens menu only.
- Load Track is local engine repair only — does not skip tracks for other players.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | — | No required merge (new Music toast/label strings live in kit `Config.luau`) |
| Buyer `Secrets` | — | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.17** after Update Engine
- [ ] Music icon → horizontal menu → Music Player opens panel; Load Track restores silent audio (or honest muted/loading toast)
- [ ] Topbar Menu button shows **Menu** label (Inter)
- [ ] VIP on community join applies mid-session when `VipOnCommunityJoin` enabled
- [ ] Respawning does not flash full OverheadGui placeholders
- [ ] ClubKitConfig + Secrets unchanged by Update Engine
