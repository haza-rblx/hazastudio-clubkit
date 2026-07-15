# Upgrade v2.4.38 → v2.4.39

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets` (jangan di-overwrite).
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Tidak ada merge config wajib — flag baru ada default di engine `Config.luau`.

## What's new

- **Network / FPS stabilisasi** — DJ effects-only sync + throttle; overhead join proximity-only; deep nested deltas; OverheadUI apply coalesce; donation world VFX concurrent cap; NetworkManager per-frame keep-last coalesce. Kill switches di `Config.NetworkPerf` (A/B).
- **Cinematic dock** — tombol topbar tetap terlihat; non-admin dapat toast deny (tidak buka dock).
- **Music DJ toggles** — tidak lagi ghost-click dari tab lain.
- **Freecam** — setelah keluar Shift+P / mobile stop, kursor tidak lagi terkunci di tengah (`LockCenter`).

## Breaking changes

Tidak ada. Buyer `ClubKitConfig` / `Secrets` tidak diganti.

Defaults engine (bisa di-override lewat buyer merge jika exposure config dipake):

| Flag | Default |
|------|---------|
| `NetworkPerf.DJ_EFFECTS_DELTA_ONLY` | `true` |
| `NetworkPerf.DJ_STATE_SYNC_THROTTLE` | `true` |
| `NetworkPerf.OVERHEAD_JOIN_PROXIMITY_ONLY` | `true` |
| `NetworkPerf.DEEP_DELTA_NESTED` | `true` |
| `NetworkPerf.DONATION_VFX_MAX_CONCURRENT` | `1` |
| `Network.ENABLE_FRAME_COALESCE` | `true` |

## Config changes

Tidak wajib edit buyer config. Opsional A/B: set `ENABLE_COUNTERS = true` atau flip satu kill switch untuk diagnose Recv/FPS.

## QA setelah upgrade

- [ ] Shift+P freecam on/off → kursor bebas, tidak LockCenter
- [ ] Dense floor: nametag nearby ok; join Recv lebih ringan (distant via Snapshot-on-enter)
- [ ] DJ slider: efek sync tanpa full queue resync storm
- [ ] Donation beruntun: world VFX tidak menumpuk tak terbatas (cap 1)
- [ ] Non-admin klik cinematic topbar → toast deny, dock tidak open
- [ ] ClubKitConfig + Secrets tetap nilai buyer
