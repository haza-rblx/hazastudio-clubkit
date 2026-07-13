# Upgrade v2.4.23 → v2.4.24

**Tanggal:** 2026-07-14

## Langkah cepat

1. Studio → **Check Update** → **Update Engine**
2. Save place
3. Jangan replace ClubKitConfig / Secrets

## What's new

- TitleColorPreset (special title animations): shared ~30Hz tick for Gradient/Stroke/Dropshadow
- Hidden titles (Visible/Enabled off) skip animation work
- Kill switch: `Config.TitleColorPreset.USE_LEGACY_PER_INSTANCE_HEARTBEAT = true`

## QA

- [ ] Kit 2.4.24
- [ ] Animated special titles still look smooth near you
- [ ] Hide title / walk out of interest: CPU quieter (no flap / freeze)
- [ ] Admin title preset card still animates
