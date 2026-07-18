# Upgrade v2.4.57 → v2.4.58

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Engine-only patch. Config/Secrets tidak diganti. Field config baru punya default di engine (`HEAD_STABLE_DEBOUNCE`, `HEAD_STABLE_TIMEOUT`) — buyer tidak wajib edit `ClubKitConfig`.

## What's new
- **Overhead di map besar / streamed** — attach menunggu Head stabil; client rebind watcher saat Head diganti; loading screen tidak memaksa overhead `Enabled=false`.
- **`/re`** — prefer refresh avatar in-place (`ApplyDescription`, tetap di posisi). Fallback `LoadCharacter` stream-aware + tanpa double overhead attach (tidak lagi hop basecamp lalu race nametag).

## Config changes
| Key | Default | Notes |
|-----|---------|-------|
| `Config.Overhead.HEAD_STABLE_DEBOUNCE` | `0.35` | Detik Head harus stabil sebelum parent BillboardGui |
| `Config.Overhead.HEAD_STABLE_TIMEOUT` | `8` | Cap tunggu Head stabil |

Tidak ada field wajib di `ClubKitConfig` template.

## Breaking
- Tidak ada.

## QA setelah upgrade
- [ ] Join map besar → overhead muncul dari awal (diri sendiri)
- [ ] `/re` → tidak flash/balik SpawnLocation; overhead tetap ada
- [ ] Reset character biasa → overhead balik setelah respawn
- [ ] F9: tidak ada storm `BillboardGui not found (pending queue)` setelah `/re`
