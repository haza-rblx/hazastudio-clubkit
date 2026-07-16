# Upgrade v2.4.44 → v2.4.45

**Tanggal:** 2026-07-16

## Quick steps (source sync)

1. Backup `ClubKitConfig` + `Secrets`.
2. Plugin → **Check Update** → **Update Engine** → Save place.
3. Rejoin → F9 banner **2.4.45**.

## What's new

- **Carry** — carried fully massless + no collide (including HRP); carrier can jump/walk normally and dance over carry pose; carried stays limp/stuck on weld.

## Breaking changes

Tidak ada. Soft: carrier no longer forced to dance walk-speed / JumpPower 0 while carrying.

## Config

Engine `Carry.PHYSICS` comment only — no buyer config change.

## QA setelah upgrade

- [ ] Banner **2.4.45**
- [ ] Carry: carrier jalan + lompat ringan; dance panel tetap bisa
- [ ] Carried tetap nempel (tidak jatuh lepas / tidak nambah mass)
- [ ] End carry restore collision/mass/humanoid OK
- [ ] ClubKitConfig + Secrets utuh
