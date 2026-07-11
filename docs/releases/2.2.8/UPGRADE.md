# Upgrade v2.2.7 → v2.2.8

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. (Opsional) Review `ClubKitConfig`:
   - **Carry** — template repo sudah 6 style kit + anim baru; place kamu **tidak** auto-replace. Paste manual kalau mau sync.
   - **Roles colors** — engine auto-remap duplikat; boleh rapikan `teamColor` / `roleColor` di config biar log bersih.

## What's new

- Donation panel rank lebih stabil (`#-` tidak hilang-muncul saat total > 0)
- Role team/chat color duplikat di-remap otomatis
- Default music volume 100% (save lama yang masih 50% default ikut migrate)
- Icon cinematic/freecam topbar HP diganti
- Template Carry: nama kit 6 style + anim ID buyer

## Breaking

Tidak. `ClubKitConfig` / `Secrets` tidak diganti Update Engine.

## Config notes

| Area | Action |
|------|--------|
| Music volume | Default baru 100%; user yang pernah set manual tetap |
| Carry styles | Buyer paste sendiri jika masih legacy names |
| Role colors | Auto-fix at boot; optional manual unique colors |

## QA

- [ ] Donate Robux → panel total + rank nempel (tidak bolak-balik `#-` selama 30–60s)
- [ ] `/removerobux me` → total 0 dan rank `#-`
- [ ] Boot tanpa warn duplicate teamColor (atau hanya log Remapped sekali)
- [ ] Settings music slider default 100% untuk player baru
- [ ] HP: icon cinematic/freecam topbar = asset baru
