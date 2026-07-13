# Upgrade v2.4.21 → v2.4.22

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place
3. **Tidak** replace `ClubKitConfig` atau `Secrets`

## What's new

- Settings save works again (8KB limit) — hide world effect / overhead toggles persist
- HTTP API admission + negative-cache on failures (reduces UserService/GroupService retry storms)
- Leaderboard identity: no double-API after UserService fail
- Overhead getGroups: negative-cache, no wait-then-retry

## Breaking / behavior changes

- Brief windows after a failed Roblox API call may show fallback names / empty groups until negative TTL expires (~30s) — intentional backpressure
- Kill switches: `Config.HttpApi.ADMISSION_ENABLED`, `Config.HttpApi.ENABLED`
- None for ClubKitConfig / Secrets / DataStore keys

## QA setelah upgrade

- [ ] Kit **2.4.22** after Update Engine
- [ ] Settings: toggle hide donation world effect → rejoin → still hidden
- [ ] Server Network: UserService/GroupService do not ramp after join wave + 1 donation
- [ ] Leaderboard top 20 still paints
- [ ] Overhead ranks still appear (may lag ~30s after a throttle window)
- [ ] ClubKitConfig + Secrets unchanged
