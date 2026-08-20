---
name: mcp-studio
description: Use whenever a task needs MCP→Studio (Roblox Studio via the `@chrrxs/robloxstudio-mcp` bridge) — start/verify the server, execute Luau, edit script sources, playtest, sync the engine, or debug Studio state. Trigger on mentions of "mcp", "execute_luau", "playtest", "sync engine", "set_script_source", "Studio bridge", "push ke place", "update engine di place", or any request that mutates/inspects a live Studio place. Consolidates the project MCP memory so the agent does NOT need the workflow re-explained each session.
---

# MCP → Studio (Roblox) — runnable workflow

Server: **`@chrrxs/robloxstudio-mcp`** (npm). Studio plugin `MCPPlugin.rbxmx` is a **CLIENT that polls OUT** to `http://localhost:58741/mcp` — nothing listens on 58741 unless the server is started. There is **no `mcp` block** in project `.mimocode/` or global `mimocode.jsonc`; MCP is driven ad-hoc (Cursor or standalone).

**Choose the start path by liveness (do NOT guess):** if port 58741 already has a listener → just use it (Cursor or a prior standalone spawn is running). If no listener → Cursor not running → spawn standalone (below). Do not start a second server on an occupied port.

---

## 1. Liveness check (always first)

```powershell
netstat -ano | Select-String "58741"
Invoke-WebRequest http://localhost:58741/health -UseBasicParsing -TimeoutSec 3
```

Listener present → server UP, go to §3. No listener → start it (§2).

## 2. Start the server

**Path A — via Cursor (normal):** Cursor spawns it from `C:\Users\haza\.cursor\mcp.json`:
`cmd /c npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin` (a second server `Roblox_Studio` runs via `%USERPROFILE%\.cursor\roblox-studio-mcp.bat`).

**Path B — standalone (no Cursor):** the server is stdio-mode and **dies on stdin EOF**, so keep stdin open:
```powershell
cmd /c "powershell -NoProfile -Command \"Start-Sleep 7200\" | npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin"
```
Log: `$env:TEMP\robloxstudio-mcp.log`. The bridge survives across mimocode sessions — always liveness-check before restarting.

## 3. Auth + endpoint

- Token (64 char) at `C:\Users\haza\.robloxstudio-mcp\auth-token`.
- Endpoint `http://localhost:58741/mcp` **requires** header `X-MCP-Auth: <token>` AND `Accept: application/json, text/event-stream` (missing Accept → **406**).
- Response is SSE (`event: message` / `data:`), **no `mcp-session-id`** — `tools/list` / `tools/call` work directly. Legacy HTTP also listens on `:3002`.

## 4. Key tools

`execute_luau` (args: `code`, `target` = `edit` | `server` | `client-N`, `instance_id`), `get_connected_instances`, `get_runtime_logs`, `eval_server_runtime` / `eval_client_runtime`, `set_script_source`, `get_script_source`, `create_object`, `delete_object`, `manage_instance`, `import_rbxm`, `multi_edit`, `start_stop_play`, `get_console_output`, `search_game_tree`, `inspect_instance`, `get_studio_state`, `script_read`, `script_grep`.

Helper pattern used across sessions: `$env:TEMP\mcp-call.ps1 -Tool <name> -ArgsFile <json> [-InstanceId <id>]` (see memory for the script body).

## 5. Hard-won rules (violating these burns a session)

1. **Persistent edit → `set_script_source` / `create_object`, NEVER `execute_luau` set `.Source`.** `execute_luau` mutating `.Source` is runtime-only and does NOT dirty-flag the Studio document → Ctrl+S silently DROPS it. `set_script_source` (UpdateSourceAsync, "editor-safe") and `create_object` DO dirty-flag → saved. Diagnose a "my edit vanished after save" bug by comparing `get_script_source` (real doc) vs `execute_luau` require/`.Source` (runtime view).
2. **`set_script_source` + PowerShell→JSON corrupts `\n` escapes.** A literal backslash-n in a Luau string (`"...song.\nRank..."`) becomes a REAL newline in transit → "Malformed string". After writing, verify with a `loadstring` parse check; if corrupted, re-write with multi-line strings joined into single lines using escaped `\n`, and confirm via `get_script_source`.
3. **Playtest server clones config from the last-SAVED place, NOT the live edit DataModel.** Workflow: edit via `set_script_source` → **Ctrl+S** → FRESH `solo_playtest` → verify resolved `Config.*`. A running playtest never refreshes its config snapshot.
4. **Multi-instance:** if >1 place is connected, `execute_luau` target `edit` is ambiguous — pass `instance_id`. Get ids via `get_connected_instances`.
5. **`datamodel_type` must match mode** — `"Edit"` in Edit, `"Server"`/`"Client"` in Play (check `get_studio_state`).
6. **`manage_instance` needs explicit `studio_executable`** when Studio is not under `%LOCALAPPDATA%\Roblox\Versions` — on this machine `C:\Program Files (x86)\Roblox\Versions\version-<hash>\RobloxStudioBeta.exe` (find via `Get-Process RobloxStudioBeta | Select -First 1 -ExpandProperty Path`).
7. **`create_object` args** are `className`, `parent`, `name` (NOT `parentPath`).
8. **Studio caches a module-load FAILURE in `require`** — after fixing a syntax-erroring module's `.Source`, `require` still fails until you Destroy+recreate the instance.
9. **This server has NO save/publish tool** — `game:SaveToRoblox`/`SaveToFile` are invalid in the edit DM; save+publish is MANUAL (Ctrl+S / File→Publish).
10. **`get_console_output` returns a truncated tail** — a single pull is not exhaustive; use small `limit` windows / filter. `DonationLeaderboardRepository` budget-defer DEBUG spam dominates it.
11. **Long multi-statement Luau often returns "timeout waiting for tools/call" yet still executes** — always re-poll `get_studio_state` / `get_console_output` after a timeout.
12. **`execute_luau` cannot `InsertService:LoadLocalAsset`** (capability) — to verify an `.rbxm`, `manage_instance` launch baseplate → `import_rbxm` → inspect → `manage_instance close`. Also no `plugin` global.
13. **`.Source` verify gotchas** — use plain find `Source:find(s, 1, true)` (Lua pattern magic chars break `:find()`); client runtime VM can't read `.Source` (check via edit target).
14. **PowerShell argv to a python client** — JSON args must be escaped `'{\"k\": v}'`; plain `'{"k": v}'` gets quotes stripped → JSONDecodeError.

## 6. Engine sync (Rojo off)

`.tmp/sync_engine.py` walks `src/`, maps repo→Studio dot-paths, ensures Folder chain, creates/updates scripts via `execute_luau` Edit, pushes only diffs. Path map: `src/ReplicatedStorage/X`→`ReplicatedStorage.X`; `src/ServerScriptService/X`→`ServerScriptService.X`; `src/StarterPlayerScripts/StarterPlayerScripts/X`→`StarterPlayer.StarterPlayerScripts.X` (doubled folder collapses). `.server.luau`→Script, `.client.luau`→LocalScript, else ModuleScript. Helpers: `.tmp/exec.py` (run Luau), `.tmp/push_exec.py` (one file). `multi_edit` takes `old_string`/`new_string`, can't create new paths. `start_stop_play` needs `{datamodel_type, is_start:bool}`. **Play-mode `.Source` mutations do NOT persist to Edit (snapshot)** — patch buyer config in Edit mode before Play.

## 7. Full reference (project memory)

Detailed / historical facts live in global project memory — read these when a task goes deeper than this card:
- `MEMORY-clubkit-tooling.md` — topology + server lifecycle + hot-reload (`_G.reload_clubkit_panel()` via `dev-serve.ps1` :8798), typecheck.
- `MEMORY-clubkit-mcp-sync-tooling.md` — full-engine sync + D1-injection load-test rig.
- `MEMORY-clubkit-studio-mcp-delivery.md` — rbxm export/verify, Update Engine require-cache gotcha, `_ImportedClubKitPackages` admin, Adonis.
- `MEMORY-clubkit-mcp-tooling-history.md` + `MEMORY-brm-legacy-tooling.md` — legacy `.tmp/mcp_bridge.py` precursors (superseded).
- `MEMORY.md` — the live entries (save-persistence root cause, ReliabilityV2, RateLimits, Update Engine boundary, SyncBhms/addon bridge pattern).
