# AGENTS — Hazastudio Club Kit

Guide for AI agents (Cursor) working in this repository.

## Product

- **Name:** Hazastudio Club Kit (Basic Club Kit)
- **Active version:** read [`VERSION`](VERSION)
- **Source:** `src/` (Rojo) → deploy to buyers via **Studio plugin source sync** (git tag) or manual `.rbxm` (Packager)
- **Buyer config (do not replace on update):**
  - `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
  - `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`
- **Engine (replace on update):** `Hazastudio_ClubKit` folders in ReplicatedFirst, ReplicatedStorage, ServerScriptService, StarterPlayerScripts, and related StarterGui

## Git (version control)

Portable Git lives in `.tools/git/` (no system-wide install required).

```powershell
# From project root:
.\git.ps1 status
.\git.ps1 log --oneline -10
.\git.ps1 diff
.\git.ps1 diff v1.3.0..HEAD --name-only   # after tags exist
```

On release, agents can use `git diff` / `git log` to generate `CHANGED_FILES.md` automatically.

**Default branch:** `main`  
**Do not commit** production `Secrets.luau` contents — `.gitignore` patterns cover `.local` only; empty Secrets templates may live in the repo.

---

| File | Purpose |
|------|---------|
| [`CHANGELOG.md`](CHANGELOG.md) | User-facing changelog (Keep a Changelog) |
| [`UPGRADE_PROGRESS.md`](UPGRADE_PROGRESS.md) | Pre-release development progress |
| [`HANDOVER.md`](HANDOVER.md) | v1.3 audit history |
| [`CLUB_KIT_SETUP.md`](CLUB_KIT_SETUP.md) | Buyer setup (Markdown) |
| [`docs/index.html`](docs/index.html) | **Central docs hub** (Home → Setup / Updates) |
| [`docs/releases/`](docs/releases/) | Per-version upgrade guides |
| [`CONTEXT.md`](CONTEXT.md) | Domain glossary — use its vocabulary in code names and conversation |
| [`docs/adr/`](docs/adr/) | Architecture Decision Records (0001 buyer config, 0002 Init bags) |

## Domain docs & agent skills

- Read `CONTEXT.md` when a term is unfamiliar; update it (and offer an ADR) when a decision crystallizes — don't let jargon drift.
- Project skills live in `.mimocode/skills/`: `grill-with-docs` (plan before non-trivial changes), `diagnosing-bugs` (feedback-loop-first debugging), `code-review` (two-axis gate before release), `tdd-luau` (red-green for pure Luau logic), `mcp-studio` (MCP→Studio bridge workflow: start/verify server, execute_luau, persistent edits, playtest, engine sync — read before touching a live Studio place via MCP).

---

## Workflow: user says "okay this is update X.Y"

Example triggers: *"okay this is update 2.1"*, *"release version 1.3.1"*, *"create changelog for this update"*.

### Required agent steps

1. **Read the old version** from `VERSION` (and `ClubKitManifest.KIT_VERSION` if present).
2. **Collect changes** from:
   - [`UPGRADE_PROGRESS.md`](UPGRADE_PROGRESS.md)
   - Recent conversation / tasks
   - Scan session-modified files (if git is unavailable, rely on UPGRADE_PROGRESS table + exploration)
3. **Write changelog** — move `[Unreleased]` content in `CHANGELOG.md` to section `[X.Y.Z]` + today's date.
4. **Create release folder:** `docs/releases/<X.Y.Z>/`
   - `UPGRADE.md` — buyer guide: what to replace, what to keep, deploy steps
   - `CHANGED_FILES.md` — changed files vs previous version, grouped as:
     - **Replace** (core kit)
     - **Buyer-owned** (config/secrets — do not overwrite)
     - **Optional** (StarterGui, tools, docs)
5. **Update version** in:
   - `VERSION`
   - `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` → `KitVersion`
   - `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` → `KIT_VERSION`
6. **Reset** `UPGRADE_PROGRESS.md` (clear unreleased entries; keep template checklist).
7. **Summarize for user:** new version, highlight breaking changes, buyer files to review manually.

### Daily release — source sync (no RBXM)

For Luau engine-only updates (primary workflow):

```powershell
# From project root — validate + tag + push:
.\tools\release.ps1              # dry-run: check VERSION / KitProduct / Manifest sync
.\tools\release.ps1 -Execute     # commit (if dirty), tag vX.Y.Z, push main + tag
.\tools\release.ps1 -Execute -GhRelease   # optional: gh release create (notes-only, no assets)
```

Or manually:

```powershell
.\git.ps1 add -A
.\git.ps1 commit -m "release: v2.1.0"
.\git.ps1 tag v2.1.0
.\git.ps1 push origin main
.\git.ps1 push origin v2.1.0
```

**Buyer / dev in Studio:** Plugin → **Settings → Update plugin** (if outdated) → **Engine → Update Engine** → Save place.

The plugin fetches from the **public GitHub repo** (`ClubKitManifest.UPDATER.githubOwner` / `githubRepo`). `ClubKitConfig` and `Secrets` are never fully replaced. After a successful Update Engine, the plugin **fill-forwards** missing config keys (additive Sources patch) from `ClubKitConfigSchema`; existing buyer values are preserved. Runtime also fill-forwards in memory via `ConfigBootstrap`. New config fields → update **schema + template** `ClubKitConfig`. `ClubKitShowcase` = **dev-only** (`tools/dev/`); not included in engine sync / default Rojo; inject manually for demo places.

StarterGui, Workspace boards, and ServerStorage assets **do not** participate in source sync — deploy manually / via RBXM if changed.

Set `UPDATER.githubOwner` / `githubRepo` in `tools/ClubKitPackagerPlugin/ClubKitManifest.luau` before publishing the repo.

### Full release — RBXM (rare)

For fresh installs or sending GUI/board/models to buyers without Rojo: Studio → **Export RBXM** → send file to buyer → **Unpack RBXM**.

---

### `CHANGED_FILES.md` format

```markdown
# Changed Files — v1.3.0 → vX.Y.Z

## Summary
- X files changed
- Breaking: yes/no

## Core — replace via RBXM
| Path | Change |
|------|--------|

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|

## Tools / docs only
| Path | Change |
|------|--------|
```

### `UPGRADE.md` format (buyer)

```markdown
# Upgrade vOLD → vNEW

## Quick steps
1. Backup ClubKitConfig + Secrets
2. Remove old Hazastudio_ClubKit folders
3. Insert new RBXM
4. Restore / merge config if needed

## What's new
(bullets from changelog)

## Config changes
(new/changed Config fields — if any)

## QA after upgrade
(short checklist)
```

### During development (not a release)

- Add entries under `[Unreleased]` in `CHANGELOG.md` (Fixed/Added/Changed)
- Update the file table in `UPGRADE_PROGRESS.md`
- **Do not** bump `VERSION` until the user confirms release

---

## Code conventions

- Luau `--!strict` on new files
- Minimize scope — do not refactor unless requested
- Match surrounding file style
- Do not commit unless the user asks

### Luau local-register budget (~200)

Luau crashes with `Out of local registers` if a function/chunk exceeds ~200 locals. **Main.server / Main.client** and fat UI binders are hottest.

- Prefer `Client/Init/*` or `Server/Init/*` bags (one `require` → table of modules) over adding more top-level `local X = require(...)` to Main.
- Do **not** unpack bag fields back into many top-level `local`s — that defeats the point.
- Treat ≥170 top-level `^local` as freeze; ≥185 as treat-as-blocker before merge.
- Check: `.\tools\count-locals.ps1` (optional `-FailAt 185`).

### Live audio instances — mutate, never rebuild

Destroying/recreating DSP nodes (`SoundEffect` children) or swapping `Sound` instances while they play causes audible clicks/crackle, especially on low-end clients (user-reported: DJ effect sliders + toggles, v-unreleased fix). Rules:

- `SoundEffect` on a live `Sound`: create once, toggle via `Enabled`, change values via property writes guarded to actual changes.
- Setters driven by server state syncs: return early when the value is unchanged — server echoes replay full state, not deltas (see `MusicPlayerController` DJ guards).
- One-shot sounds (UI clicks, soundboard) are fine to create/destroy per event — the ban is on churning nodes of *playing* audio.

## Sensitive areas

- `Config.luau` — shared constants; buyers usually use `ClubKitConfig.luau`
- `Secrets.luau` — do not expose to client
- DataStore keys are versioned — watch for breaking migrations
