# Upgrade v2.4.17 → v2.4.18

**Tanggal:** 2026-07-13

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- Fix music topbar `setMenu` crash (`Menu:169` / `noticeChanged` nil) when showing Music Player + Load Track menu

## Breaking / behavior changes

- None.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | — | No required merge |
| Buyer `Secrets` | — | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.18** after Update Engine
- [ ] Music icon → horizontal menu (Music Player / Load Track) without `Menu:169` / `noticeChanged` spam
- [ ] ClubKitConfig + Secrets unchanged
