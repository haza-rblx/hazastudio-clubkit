--!strict
-- tools/SyncFromDevServe.editmode.luau
--
-- Push repo files into the open place over the dev-serve bridge (Edit mode, run through the
-- Studio MCP `execute_luau` or the Command Bar). Used for every engine sync to THE BASIC TEST
-- during production hardening (2026-09-24); no Rojo session needed.
--
-- Prerequisites:
--   1. `tools/ClubKitPackagerPlugin/dev-serve.ps1 -Port 8798` running (serves the repo at /repo/).
--   2. HttpService enabled in the place (it is on every kit place).
--
-- Usage: edit FILES (repo paths from the repo root) and MODE, then run the whole script.
--   MODE = "check"  → compare place `.Source` with `/repo/.tmp/head-sync/<path>` (git HEAD copies
--                     exported with `git show HEAD:<path>`) and report SAME / DIFF / MISSING.
--                     Run this FIRST: a DIFF that is not "place lags HEAD" means a hand edit in
--                     the place that a sync would destroy.
--   MODE = "sync"   → write the working-tree version (`/repo/<path>`) into the place, creating
--                     Folders / ModuleScripts / Scripts / LocalScripts as needed, and verify.
--
-- Path mapping: src/ReplicatedStorage/X → game.ReplicatedStorage.X, src/ServerScriptService/X →
-- game.ServerScriptService.X, src/StarterPlayerScripts/StarterPlayerScripts/X →
-- game.StarterPlayer.StarterPlayerScripts.X. `.server.luau` → Script, `.client.luau` → LocalScript,
-- otherwise ModuleScript. Afterwards the OWNER must Ctrl+S (nothing here saves the place).

local HttpService = game:GetService("HttpService")

local MODE: "check" | "sync" = "check"
local PORT = 8798
local FILES = {
	-- "src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau",
}

local function relOf(path: string): (string, string)
	local rel = path:gsub("^src/", "")
	rel = rel:gsub("^StarterPlayerScripts/StarterPlayerScripts/", "StarterPlayer/StarterPlayerScripts/")
	local class = "ModuleScript"
	if rel:match("%.server%.luau$") then
		class = "Script"
	elseif rel:match("%.client%.luau$") then
		class = "LocalScript"
	end
	rel = rel:gsub("%.luau$", ""):gsub("%.server$", ""):gsub("%.client$", "")
	return rel, class
end

local function find(rel: string): Instance?
	local node: Instance? = game
	for seg in rel:gmatch("[^/]+") do
		node = node and node:FindFirstChild(seg)
	end
	return node
end

local function ensure(rel: string, class: string): Instance
	local segs = {}
	for seg in rel:gmatch("[^/]+") do
		table.insert(segs, seg)
	end
	local node: Instance = game
	for i, seg in ipairs(segs) do
		local child = node:FindFirstChild(seg)
		if not child then
			child = Instance.new(if i == #segs then class else "Folder")
			child.Name = seg
			child.Parent = node
		end
		node = child
	end
	return node
end

local function norm(s: string): string
	return (s:gsub("\r\n", "\n"))
end

local function fetch(url: string): (boolean, string)
	local ok, body = pcall(HttpService.GetAsync, HttpService, url)
	return ok, tostring(body)
end

local out = {}
local created, written, same = 0, 0, 0
for _, f in ipairs(FILES) do
	local rel, class = relOf(f)
	if MODE == "check" then
		local inst = find(rel)
		if not inst then
			table.insert(out, "MISSING " .. rel)
			continue
		end
		local ok, head = fetch(string.format("http://127.0.0.1:%d/repo/.tmp/head-sync/%s", PORT, f))
		if not ok then
			table.insert(out, "HTTPFAIL " .. rel .. " " .. head)
			continue
		end
		local cur = norm((inst :: any).Source)
		if cur == norm(head) then
			table.insert(out, "SAME " .. inst.Name)
		else
			table.insert(out, string.format("DIFF %s place=%d head=%d", rel, #cur, #norm(head)))
		end
	else
		local ok, src = fetch(string.format("http://127.0.0.1:%d/repo/%s", PORT, f))
		if not ok then
			table.insert(out, "HTTPFAIL " .. rel .. " " .. src)
			continue
		end
		src = norm(src)
		local existed = find(rel) ~= nil
		local inst = ensure(rel, class)
		if not existed then
			created += 1
		end
		if norm((inst :: any).Source) ~= src then
			(inst :: any).Source = src
			written += 1
		else
			same += 1
		end
		if norm((inst :: any).Source) ~= src then
			table.insert(out, "VERIFYFAIL " .. rel)
		end
		if inst.ClassName ~= class then
			table.insert(out, "CLASS " .. rel .. " " .. inst.ClassName)
		end
	end
end
if MODE == "sync" then
	table.insert(out, string.format("created=%d written=%d same=%d", created, written, same))
end
print(table.concat(out, "\n"))
return table.concat(out, "\n")
