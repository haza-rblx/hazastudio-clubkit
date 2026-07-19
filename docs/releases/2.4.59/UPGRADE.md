# Upgrade v2.4.58 → v2.4.59

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only patch. `ClubKitConfig` / `Secrets` tidak diganti. Tidak ada field wajib baru di buyer config.

## What's new
- **CharacterReady** — kontrak bersama Parts / Adorn / Anim; teleport (`/re` `/bring` `/to`) stream-warm hanya jika `StreamingEnabled`.
- **`/re` regression fix** — kembali ke `LoadCharacter` + stream restore (bukan `ApplyDescription`); busy message + lock timeout; dance restore retry Animator.
- **Map besar** — proximity `recomputeNow` setelah PartsReady (nametag tidak blank ~0.5s); Head settle via AppearanceLoaded (debounce fallback); loading hide mengikuti part yang stream-in.
- **Sticker / loading / overhead** — client adornee priority, Head rebind, dead `Avatar:Refreshed` path dihapus.

## Config changes
| Key | Notes |
|-----|-------|
| `Config.Session.REFRESH_LOCK_TIMEOUT` | Default 12 — auto-clear sticky `/re` lock |
| `Config.Session.MSG_REFRESH_BUSY` | Pesan saat `/re` masih in-flight |
| `Config.Overhead.HEAD_STABLE_*` | Tetap engine-only; settle prefer AppearanceLoaded |

Tidak ada merge wajib di `ClubKitConfig`.

## Breaking
- Tidak ada.
- Catatan: perilaku `/re` beda dari 2.4.58 (LoadCharacter lagi, bukan ApplyDescription in-place) — posisi tetap di-restore; tidak hop basecamp lama.

## QA setelah upgrade
- [ ] `/re` berkali-kali (map kecil + dugem) — posisi OK, overhead tetap, dance balik jika sedang dance
- [ ] `/bring` `/to` di StreamingEnabled — tidak nyangkut spawn
- [ ] Join / respawn di kerumunan — nametag self + nearby cepat muncul
- [ ] Loading screen — player lain tidak flash limb; overhead tidak hilang setelah dismiss
- [ ] F9 banner KitVersion **2.4.59**
