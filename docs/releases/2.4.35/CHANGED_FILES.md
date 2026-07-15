# Changed Files — v2.4.34 → v2.4.35

## Summary

- Hotfix: Main.server Luau register overflow
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `src/.../Server/Init/PersistenceFabricHooks.luau` | **New** — single Main surface for session flush + metrics |
| `src/.../Server/Init/MusicBootstrap.luau` | **New** — Music service/controller/zone/favorites boot |
| `src/.../Server/Main.server.luau` | Use hooks + MusicBootstrap; drop top-level Music/Persistence util requires |
| `src/.../KitProduct.luau` | KitVersion 2.4.35 |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| ClubKitConfig / Secrets | No change |

## Tools / docs

| Path | Change |
|------|--------|
| `VERSION` / Manifest / CHANGELOG | 2.4.35 |
| `docs/releases/2.4.35/*` | Upgrade + changed files |
