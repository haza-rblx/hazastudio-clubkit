# Upgrade v2.4.13 -> v2.4.14

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio -> Club Kit Packager -> **Check Update** -> **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- **Join Community CTA label** - button text writes to nested `JoinCommunityButton > TextLabel` (Studio layout), not only `TextButton.Text`.
- **Join greeting CountDownBar** - no longer recolors with role accent or overwrites Studio `UIGradient`; designer gradient/colors stay.

## Breaking / behavior changes

- **UI only:** CTA nested label + CountDownBar keep Studio styling. No DataStore / remote / config schema changes.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Buyer `ClubKitConfig` | - | No required merge |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.14** after Update Engine
- [ ] Join Community / Already joined text visible on nested TextLabel
- [ ] CountDownBar keeps Studio gradient (not role-colored)
- [ ] ClubKitConfig + Secrets unchanged after Update Engine
