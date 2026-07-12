# Upgrade v2.4.12 -> v2.4.13

**Tanggal:** 2026-07-12

## Langkah cepat

1. Studio -> Club Kit Packager -> **Check Update** -> **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets` (source sync tidak menyentuh keduanya)

## What's new

- **Join greeting: entered the space** - second line is `{Gelar} {DisplayName} has entered the space!` (not Welcome back).
- **Gelar from role display** - Owner / Leadership / Content (and roles in those categories) use the role **display title** from Roles config.
- **Top Spender / Top Donor gelar** - Top Robux / Top Cash greetings use `Top Spender #N` / `Top Donor #N`.
- **Spender chip amount** - spender toasts include `amount` / `amountText` / `amountKind` and show the total on the Universal chip.

## Breaking / behavior changes

- **Copy/UI:** join greeting second line and gelar labels changed; Universal chip may show amount for spender greetings.
- DataStore / remotes: payload may include amount fields (additive); no required buyer migration.

`Secrets` tidak diganti. `ClubKitConfig` tidak diganti oleh source sync.

## Config / Secrets notes

| Path | Field | Notes |
|------|--------|-------|
| Engine `Config.JoinGreeting.ENTERED_SPACE_TEMPLATE` | string | New second-line template |
| Engine `Config.JoinGreeting.GELAR_TITLES` | templates | Spender/donor rank titles |
| Buyer `ClubKitConfig` Roles display titles | labels | Used as gelar for role greetings |
| Buyer `Secrets` | - | No required merge |

## QA setelah upgrade

- [ ] Plugin shows kit **2.4.13** after Update Engine
- [ ] Role greeting: `{RoleDisplayTitle} {Name} has entered the space!` (not Welcome back)
- [ ] Top Robux / Top Cash: `Top Spender #N` / `Top Donor #N` gelar
- [ ] Spender toast Universal chip shows amount when totals exist
- [ ] ClubKitConfig + Secrets unchanged after Update Engine
