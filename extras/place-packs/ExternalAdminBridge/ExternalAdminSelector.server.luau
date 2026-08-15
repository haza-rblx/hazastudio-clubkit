--!strict
--[[
	External Admin selector (External Admin Bridge pack).

	Install: Script in ServerScriptService (any name; suggested
	"ExternalAdminSelector"). Recommended: leave BOTH admin loader Scripts at
	Disabled = true in Edit (the template place ships this way):
	  - ServerScriptService.Adonis_Loader.Loader.Loader
	  - ServerScriptService."Kohl's Admin".Loader
	If a loader is found Enabled (fresh insert), the selector disables it
	itself and warns — the only cost is that the unwanted admin may still
	boot for that one session.

	At server start this script reads ClubKitConfig.ExternalAdmin.Provider and
	enables ONLY the chosen admin's loader. The other admin never boots:
	no UI (topbar/dashboard), no chat commands, no network — while its module
	stays in the place (nothing deleted). Provider = "None" boots neither.

	At server start this script reads ClubKitConfig.ExternalAdmin.Provider and
	enables ONLY the chosen admin's loader. The other admin never boots:
	no UI (topbar/dashboard), no chat commands, no network — while its module
	stays in the place (nothing deleted). Provider = "None" boots neither.

	Switching providers takes effect on the NEXT server start (it gates boot).
	Requires no Club Kit engine version — standalone by design.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOADER_PATHS: { [string]: { string } } = {
	Adonis = { "Adonis_Loader", "Loader", "Loader" },
	Kohls = { "Kohl's Admin", "Loader" },
}

local function readProvider(): string
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	local mod = folder and folder:FindFirstChild("ClubKitConfig")
	if not (mod and mod:IsA("ModuleScript")) then
		return "None"
	end
	local ok, cfg = pcall(require, mod)
	if not ok or type(cfg) ~= "table" then
		return "None"
	end
	local section = (cfg :: any).ExternalAdmin
	local raw = if type(section) == "table" then tostring(section.Provider or "None") else "None"
	local key = string.lower((string.gsub(raw, "%s+", "")))
	if key == "adonis" then
		return "Adonis"
	end
	if key == "kohls" or key == "kohl" or key == "kohl's" then
		return "Kohls"
	end
	return "None"
end

local function findLoaderScript(path: { string }): Script?
	local inst: Instance = ServerScriptService
	for _, name in ipairs(path) do
		local child = inst:FindFirstChild(name)
		if not child then
			return nil
		end
		inst = child
	end
	if inst:IsA("Script") then
		return inst
	end
	return nil
end

local provider = readProvider()

for name, path in LOADER_PATHS do
	local loader = findLoaderScript(path)
	if not loader then
		if provider == name then
			warn(`[ExternalAdminSelector] Provider = "{name}" but its loader was not found in ServerScriptService`)
		end
		continue
	end
	local enable = provider == name
	if not enable and not loader.Disabled then
		-- Fresh insert (loaders ship Enabled by default): disable at runtime.
		-- Honest semantics: if this script ran after the loader started, the
		-- unwanted admin still boots for THIS session. Runtime disable is not
		-- persistent — for a guaranteed-clean boot, set the loader Script
		-- Disabled = true once in Edit (the template place ships this way).
		loader.Disabled = true
		warn(`[ExternalAdminSelector] {name} loader was Enabled and Provider = "{provider}" — disabled at runtime. If {name} still appeared this session, it booted before the selector ran; set its loader Script Disabled = true in Edit for a guaranteed-clean boot.`)
	else
		loader.Disabled = not enable
	end
	print(`[ExternalAdminSelector] {name} loader {if enable then "ENABLED" else "disabled"} (Provider = {provider})`)
end
