# Upgrade v2.4.1 → v2.4.2

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- **Join community copy** — modal copy no longer uses VIP framing; uses community-join wording (`Join our community.` / `…already joined this community`)
- **Join greetings after loading** — greeting toasts wait until `enterGameplay` (loading dismiss + camera reveal), then play the full ~15s sequence

## Breaking / behavior changes

- None (DataStore / remotes unchanged). Greetings may appear slightly later (after loading finishes) instead of during the loading click wait.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinCommunityPrompt` | `TITLE` / `SUBHEADLINE` / `BODY_*` | Community (non-VIP) copy applied on modal open |
| Engine `Config.JoinGreeting` | `WAIT_FOR_GAMEPLAY` | Hold toasts until client `enterGameplay` |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.2** after Update Engine
- [ ] Join Commun modal: no VIP wording; community join copy visible
- [ ] Join greeting: toast does **not** start during loading click wait; starts after camera reveal; still ~15s
- [ ] Already-in-group: Join Commun still skipped as before
