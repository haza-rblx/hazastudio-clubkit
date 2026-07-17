# Upgrade v2.4.56 → v2.4.57

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only patch. Config/Secrets tidak diganti. Field config baru punya default di engine (`LB_READ_RETRY_ATTEMPTS`, `RANK_RESOLVE_DELAY_SEC`) — buyer tidak wajib edit `ClubKitConfig`.

## What's new
- **DataStore OrderedList** — cold start low-CCU tidak lagi mudah kena throttle: cache/last-good sebelum lockout, `GetSortedAsync` 1 attempt, overhead rank resolve ditunda setelah LB pre-warm.
- **Dance switch** — hard-stop track lama saat ganti dance (hindari blend “tangan patah”).
- **Carry × dance** — carry menghentikan dance Action4; dance ditolak saat digendong.
- **Sync join** — phase snap langsung + pakai anim aktif leader (bukan track fading).
- **Paid Broadcast** — `canAnnounce` (staff/mod) kirim gratis; player biasa tetap bayar Robux.

## Config changes
| Key | Default | Notes |
|-----|---------|-------|
| `Config.DataStore.LB_READ_RETRY_ATTEMPTS` | `1` | Kill switch: set `3` untuk perilaku lama |
| `Config.Overhead.RANK_RESOLVE_DELAY_SEC` | `30` | Kill switch: set `2` untuk rank resolve cepat (lama) |
| `Config.Overhead.RANK_RESOLVE_JITTER_SEC` | `5` | Jitter di atas delay |

Tidak ada field wajib di `ClubKitConfig` template.

## Breaking
- Tidak ada. Dance saat digendong sekarang ditolak (sebelumnya blend rusak).

## QA setelah upgrade
- [ ] Server baru, 2 player → tidak ada storm `OrderedList` / `ds_throttled` di menit pertama
- [ ] Spam ganti dance → tidak ada pose lengan patah sebentar
- [ ] Digendong sambil dance → dance stop / refuse; pose carry bersih
- [ ] Sync pertama ke leader yang sudah dance → phase langsung nyambung (mirip setelah ganti dance)
- [ ] Staff/mod buka Paid Broadcast → "Send broadcast" gratis; player biasa tetap prompt Robux
