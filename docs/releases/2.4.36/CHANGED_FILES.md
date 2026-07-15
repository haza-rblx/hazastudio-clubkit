# Changed Files — v2.4.35 → v2.4.36

## Summary

- Preventive Luau register headroom (Main client/server + Music UIBinder)
- Breaking: no

## Core — replace via Update Engine

| Path | Change |
|------|--------|
| `src/.../Client/Init/ClientModuleBag.luau` | **New** — late-boot client require bag |
| `src/.../Main.client.luau` | Use `ClientMods.*` (~127 top-level locals) |
| `src/.../Server/Init/ServerModuleBag.luau` | **New** — services/controllers/repos bag |
| `src/.../Server/Main.server.luau` | Use `ServerMods.*` (~115 top-level locals) |
| `src/.../Client/UI/MusicPlayerCoverHelpers.luau` | **New** — cover/title helpers |
| `src/.../Client/UI/MusicPlayerUIBinder.luau` | Delegate to CoverHelpers (~158 locals) |
| `src/.../KitProduct.luau` | KitVersion 2.4.36 |

## Buyer-owned — jangan replace

| Path | Action |
|------|--------|
| ClubKitConfig / Secrets | No change |

## Tools / docs

| Path | Change |
|------|--------|
| `tools/count-locals.ps1` | **New** — register budget checker |
| `AGENTS.md` | Register-budget guardrail |
| `VERSION` / Manifest / CHANGELOG | 2.4.36 |
| `docs/releases/2.4.36/*` | Upgrade + changed files |
