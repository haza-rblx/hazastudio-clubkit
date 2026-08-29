--!nocheck
--[[
  PlaceSecurityScan — static backdoor / abuse-surface scan for a buyer place (ADR 0008, Layer 1).

  Run in Studio (Edit mode): paste into the Command Bar, or via MCP `execute_luau`, or
  `loadstring(HttpService:GetAsync("http://127.0.0.1:8798/repo/tools/security/PlaceSecurityScan.luau"))()`
  with dev-serve running. Prints a severity-sorted report and returns it as a string.

  It reads Source of every script it can reach (needs Studio; runtime Source access is
  restricted). Nothing is modified.
]]

local KIT_ROOT_NAMES = {
	Hazastudio_ClubKit = true,
	Hazastudio_ClubKitConfig = true,
	Hazastudio_ClubKitSecrets = true,
	Icon = true, -- vendored TopbarPlus
}

-- Known-legitimate remote modules a buyer may knowingly ship. Everything else numeric is CRITICAL.
local KNOWN_REQUIRE_IDS = {
	["1868400649"] = "Kohl's Admin MainModule",
}

local ODD_SCRIPT_SERVICES = {
	Lighting = true,
	SoundService = true,
	TextChatService = true,
	Chat = true,
	Teams = true,
	StarterPack = true,
	LocalizationService = true,
	MaterialService = true,
	Players = true,
}

local SEVERITY_ORDER = { CRITICAL = 1, HIGH = 2, MEDIUM = 3, INFO = 4 }

local findings = {}
local inventory = { remotes = {}, soundMakers = {}, requires = {} }
local scanned, unreadable = 0, 0

local function isKitOwned(inst)
	local cur = inst
	while cur and cur ~= game do
		if KIT_ROOT_NAMES[cur.Name] then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function add(severity, inst, what, detail)
	table.insert(findings, {
		severity = severity,
		path = inst:GetFullName(),
		what = what,
		detail = detail,
	})
end

local function topService(inst)
	local cur = inst
	while cur and cur.Parent and cur.Parent ~= game do
		cur = cur.Parent
	end
	return cur
end

local function countMatches(src, pattern)
	local n = 0
	for _ in string.gmatch(src, pattern) do
		n += 1
	end
	return n
end

local function stripComments(src)
	src = string.gsub(src, "%-%-%[%[.-%]%]", "")
	src = string.gsub(src, "%-%-[^\n]*", "")
	return src
end

local function scanScript(inst)
	local ok, src = pcall(function()
		return inst.Source
	end)
	if not ok or type(src) ~= "string" then
		unreadable += 1
		return
	end
	scanned += 1
	local kit = isKitOwned(inst)
	local code = stripComments(src)
	local isServer = inst:IsA("Script") or (inst:IsA("ModuleScript") and not inst:FindFirstAncestorOfClass("PlayerScripts"))

	-- CRITICAL: require by asset id
	for id in string.gmatch(code, "require%s*%(%s*(%d+)") do
		table.insert(inventory.requires, inst:GetFullName() .. " → " .. id)
		if KNOWN_REQUIRE_IDS[id] then
			add("INFO", inst, "require(" .. id .. ")", "known: " .. KNOWN_REQUIRE_IDS[id])
		else
			add("CRITICAL", inst, "require(" .. id .. ")", "remote module = remote code execution on your server; vendor a copy or remove")
		end
	end
	-- require of something computed (string concat / variable) — cannot be reviewed statically
	if string.find(code, "require%s*%(%s*[^%d%s\"'%)]") and not string.find(code, "require%s*%(%s*script") and not string.find(code, "require%s*%(%s*game") and not string.find(code, "require%s*%(%s*[%w_]+%.") then
		if not kit then
			add("HIGH", inst, "require(<computed>)", "require target is not a literal path; check what it resolves to")
		end
	end

	if not kit then
		if string.find(code, "getfenv") or string.find(code, "setfenv") then
			add("HIGH", inst, "getfenv/setfenv", "environment tampering — classic backdoor marker")
		end
		if string.find(code, "loadstring") then
			add("HIGH", inst, "loadstring", "runs code from a string; combined with HttpService = remote shell")
		end
		if (string.find(code, "string%.reverse") or string.find(code, ":reverse%(")) and string.find(code, "require") then
			add("HIGH", inst, "string.reverse + require", "obfuscated require target")
		end
		local escapes = countMatches(code, "\\%d%d%d")
		if escapes >= 12 then
			add("HIGH", inst, "obfuscated strings", escapes .. " \\ddd escape sequences")
		end
		if string.find(string.lower(code), "discord%.com/api/webhooks") or string.find(string.lower(code), "discordapp%.com/api/webhooks") then
			add("HIGH", inst, "Discord webhook in source", "token is copyable by anyone who copies the place; move to the VPS forwarder")
		end
		if string.find(code, "HttpService") and (string.find(code, "PostAsync") or string.find(code, "RequestAsync") or string.find(code, "GetAsync")) then
			add("MEDIUM", inst, "HttpService call", "third-party script talks to the internet — know where")
		end
		if string.find(code, "OnServerEvent") or string.find(code, "OnServerInvoke") then
			local hasCheck = string.find(code, "UserId") or string.find(code, "GetRankInGroup") or string.find(code, "rate") or string.find(code, "Rate") or string.find(code, "cooldown")
			add(if hasCheck then "INFO" else "MEDIUM", inst, "remote handler", if hasCheck then "has some permission/rate check — still review" else "no visible permission or rate-limit check")
		end
		if isServer and string.find(code, "Instance%.new%s*%(%s*[\"']Sound[\"']") then
			table.insert(inventory.soundMakers, inst:GetFullName())
			add("INFO", inst, "creates Sound on server", "audit what id it plays and who can trigger it")
		end
		for line in string.gmatch(code, "[^\n]+") do
			if #line > 2000 then
				add("MEDIUM", inst, "minified line", #line .. " chars on one line — unreadable code")
				break
			end
		end
		if string.find(code, "_G%.") or string.find(code, "shared%.") then
			add("INFO", inst, "_G / shared", "global state — common in backdoor droppers")
		end
		local svc = topService(inst)
		if svc and ODD_SCRIPT_SERVICES[svc.Name] then
			add("MEDIUM", inst, "script in " .. svc.Name, "scripts rarely belong here; droppers hide in unusual services")
		end
	end
end

local function scanRemote(inst)
	if isKitOwned(inst) then
		return
	end
	table.insert(inventory.remotes, inst.ClassName .. " " .. inst:GetFullName())
end

for _, service in ipairs(game:GetChildren()) do
	local ok, descendants = pcall(function()
		return service:GetDescendants()
	end)
	if ok then
		for _, inst in ipairs(descendants) do
			if inst:IsA("LuaSourceContainer") then
				scanScript(inst)
			elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
				scanRemote(inst)
			end
		end
	end
end

table.sort(findings, function(a, b)
	if a.severity ~= b.severity then
		return SEVERITY_ORDER[a.severity] < SEVERITY_ORDER[b.severity]
	end
	return a.path < b.path
end)

local counts = { CRITICAL = 0, HIGH = 0, MEDIUM = 0, INFO = 0 }
for _, f in ipairs(findings) do
	counts[f.severity] += 1
end

local out = {}
table.insert(out, string.format("PlaceSecurityScan — %s (place %d)", game.Name, game.PlaceId))
table.insert(out, string.format("scripts scanned=%d unreadable=%d | CRITICAL=%d HIGH=%d MEDIUM=%d INFO=%d", scanned, unreadable, counts.CRITICAL, counts.HIGH, counts.MEDIUM, counts.INFO))
table.insert(out, "")
local shown = 0
for _, f in ipairs(findings) do
	if f.severity ~= "INFO" or shown < 40 then
		table.insert(out, string.format("[%s] %s — %s: %s", f.severity, f.path, f.what, f.detail))
		shown += 1
	end
end
table.insert(out, "")
table.insert(out, string.format("Non-kit remotes (%d):", #inventory.remotes))
for i = 1, math.min(60, #inventory.remotes) do
	table.insert(out, "  " .. inventory.remotes[i])
end
table.insert(out, string.format("require-by-id sites (%d):", #inventory.requires))
for _, r in ipairs(inventory.requires) do
	table.insert(out, "  " .. r)
end

local report = table.concat(out, "\n")
print(report)
return report
