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

## UI motion

- **Rasterized group** — a `CanvasGroup`: Roblox flattens its subtree into a GPU texture sized by its `AbsoluteSize`. Resizing re-creates the texture; exceeding the client's texture budget renders it blank (Roblox docs).
- **Size-stable motion** — the rule that nothing may change a rasterized group's `AbsoluteSize` while it is visible (see `docs/adr/0005`). Scale pops on groups become fades/travel; plain Frame trees keep the pop.
- **Group motion policy** — `Shared/UI/GroupMotionPolicy` (pure) + `Client/Utils/GroupMotion` (Instance adapter): the single decision point for "scale or stable?" that every animation site consults via `GroupMotion.scaleTarget`. Opt-out knob: `Config.UIMotion.CANVAS_GROUP_SIZE_STABLE`.
- **Texture-budget guard** — `Client/Services/CanvasGroupBudgetService`: distance-culls Workspace `SurfaceGui`s that contain a rasterized group so their textures are released while nobody is near, keeping the budget free for ScreenGui panels (`Config.CanvasGroupBudget`; per-GUI opt-out attribute `ClubKitKeepSurfaceGui`).

## External admin bridge

- **External admin** — a third-party moderation system (Adonis or Kohl's Admin) installed by the buyer. The Kit does not own it and does not fork it.
- **Facade** — the engine-side `ExternalAdminFacade` singleton: a stable API surface that external admin plugins/addons call to run Club Kit actions (`setRole`, `announce`, etc.).
- **Provider** — `ClubKitConfig.ExternalAdmin.Provider` value (`"Adonis"`, `"Kohls"`, `"None"`); runtime gate only.
- **Rank sync** — one-way mirroring of Club Kit staff role changes into the chosen external admin's ranks, driven by the `Gift:RoleChanged` event.

## Music library modes

- **Music library mode** — buyer choice of how the shared music library relates to DataStore, via `ClubKitConfig.Features.MusicReadOnlyLibrary` (boolean). Two values:
- **Editable** — the legacy behavior and default (`false`): DataStore read at boot + writes persist, catalog seed, sync poll, Manage tab shown for permitted ranks.
- **ReadOnly** — (`true`) no DataStore at all: library comes from the MusicCatalog script + in-game requests held in memory (lost on restart); legacy stored data is untouched but not shown; Manage tab hidden (DJ tab hides too, same manage gate).
