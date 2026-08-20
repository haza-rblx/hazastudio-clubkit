import type { Hooks } from "@mimo-ai/plugin"

/**
 * Injects a compact MCP→Studio pointer into the system prompt every session,
 * so the agent does not need the workflow re-explained. The full procedure
 * lives in `.mimocode/skills/mcp-studio/SKILL.md` (read it before a non-trivial
 * MCP→Studio task). This hook only carries the critical path + the hard-won
 * rules that previously had to be re-taught each session.
 */
const hooks: Hooks = {
  "experimental.chat.system.transform": async (_input, output) => {
    output.system.push(
      [
        "## MCP → Roblox Studio (project convention — do NOT ask the user to re-explain)",
        "Server: `@chrrxs/robloxstudio-mcp` (npm). Studio plugin `MCPPlugin.rbxmx` is a CLIENT polling OUT to `http://localhost:58741/mcp`. No `mcp` block in mimocode config — driven ad-hoc (Cursor or standalone).",
        "",
        "Start path — decide by liveness, do NOT guess: `netstat -ano | Select-String 58741` + `Invoke-WebRequest http://localhost:58741/health`. Listener present → just use it. None → standalone spawn: `cmd /c \"powershell -NoProfile -Command \\\"Start-Sleep 7200\\\" | npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin\"` (stdio-mode server dies on stdin EOF → keep stdin open; survives across sessions).",
        "",
        "Auth: token (64 char) at `C:\\Users\\haza\\.robloxstudio-mcp\\auth-token`. Endpoint `http://localhost:58741/mcp` needs headers `X-MCP-Auth: <token>` AND `Accept: application/json, text/event-stream` (missing Accept → 406). SSE response, no `mcp-session-id`. Legacy HTTP also on :3002.",
        "",
        "HARD-WON RULES (violating these burns a session):",
        "- Persistent edit → `set_script_source` / `create_object`, NEVER `execute_luau` set `.Source` (runtime-only, does NOT dirty-flag → Ctrl+S silently drops it).",
        "- `set_script_source` + PowerShell→JSON corrupts a literal `\\n` escape into a real newline → \"Malformed string\"; verify with a loadstring parse check after writing.",
        "- Playtest server clones config from the last-SAVED place, not the live edit DataModel → edit via set_script_source → Ctrl+S → FRESH solo_playtest.",
        "- Multi-instance: pass `instance_id` (target edit ambiguous); get ids via `get_connected_instances`. `datamodel_type` must match mode (Edit vs Server/Client).",
        "- This server has NO save/publish tool; save+publish is manual (Ctrl+S / File→Publish). `create_object` args = className/parent/name (NOT parentPath).",
        "",
        "Full procedure, engine-sync path map, and all 14 rules: read `.mimocode/skills/mcp-studio/SKILL.md` before any non-trivial MCP→Studio task. Deeper history in project MEMORY (`MEMORY-clubkit-tooling.md`, `-mcp-sync-tooling`, `-studio-mcp-delivery`, `-mcp-tooling-history`).",
      ].join("\n"),
    )
  },
}

export default hooks
