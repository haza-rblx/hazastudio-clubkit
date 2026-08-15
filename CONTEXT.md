# CONTEXT — Hazastudio Club Kit

Domain glossary for agents. Terms only — no implementation details, no workflow steps (those live in `AGENTS.md`). When a term here conflicts with how someone uses it, the glossary wins or gets updated in the same conversation.

## The product

- **Kit** — the Hazastudio Club Kit as a whole: the product buyers install into their Roblox place.
- **Engine** — the replaceable core of the Kit: the `Hazastudio_ClubKit` folders under ReplicatedFirst, ReplicatedStorage, ServerScriptService, StarterPlayerScripts, plus related StarterGui. Updated wholesale on release.
- **Showcase** — `ClubKitShowcase`, a dev-only demo assembly. Not part of the Engine; never shipped via source sync.

## Ownership boundary

- **Buyer-owned files** — `ClubKitConfig.luau` (ReplicatedStorage) and `Secrets.luau` (ServerScriptService). The buyer's data lives here; the Kit never overwrites them (see `docs/adr/0001`).
- **Fill-forward** — the additive merge that brings new config keys to an existing buyer config: missing keys are added from the schema, existing buyer values are preserved. Happens at runtime (`ConfigBootstrap`, in-memory) and after plugin engine updates (source patch from `ClubKitConfigSchema`).
- **Schema** — `ClubKitConfigSchema`: the canonical list of config keys, source of truth for fill-forward and for the template `ClubKitConfig.luau`.

## Release

- **Version triad** — the three places the kit version must agree: `VERSION` (repo root), `KitProduct.KitVersion` (engine), `ClubKitManifest.KIT_VERSION` (packager plugin).
- **Source sync** — the primary release channel: git tag on the public repo, fetched by the Studio plugin's Update Engine action. Engine-only; config is fill-forwarded, never replaced.
- **RBXM release** — the rare full-fidelity channel: a `.rbxm` export for fresh installs or non-engine assets (StarterGui, Workspace boards, ServerStorage).
- **Release folder** — `docs/releases/<X.Y.Z>/` holding `UPGRADE.md` (buyer guide) and `CHANGED_FILES.md` (grouped Replace / Buyer-owned / Optional).

## Code structure

- **Init bag** — a module under `Client/Init/*` or `Server/Init/*` that returns a table of related modules from one `require`, keeping top-level `local` counts low in Main scripts.
- **Register budget** — Luau's ~200 local-registers-per-chunk limit; the structural pressure behind Init bags (see `docs/adr/0002`). Frozen at ≥170 top-level locals in a file, blocker at ≥185.
- **Versioned DataStore keys** — player-data keys carry a version; bumping one is a breaking migration for existing buyers' live data.

## External admin bridge

- **External admin** — a third-party moderation system (Adonis or Kohl's Admin) installed by the buyer. The Kit does not own it and does not fork it.
- **Facade** — the engine-side `ExternalAdminFacade` singleton: a stable API surface that external admin plugins/addons call to run Club Kit actions (`setRole`, `announce`, etc.).
- **Provider** — `ClubKitConfig.ExternalAdmin.Provider` value (`"Adonis"`, `"Kohls"`, `"None"`); runtime gate only.
- **Rank sync** — one-way mirroring of Club Kit staff role changes into the chosen external admin's ranks, driven by the `Gift:RoleChanged` event.
