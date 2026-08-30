--!nocheck
--[[
  Hierapolis add-on — REVERT (toggle OFF). Run in Studio Edit:
    loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/revert.luau"))()

  Puts the buyer config back on the kit's STOCK catalog (from ClubKitConfigSchema.defaults):
  RoleCategories, SystemRoles, LegacyAliases, CommandAliases; Features.LoadingScreen = true;
  disables ReplicatedFirst.CinematicLoading (kit loading screen takes over).
  Tool folders, Branding, Group, Donation, Shop etc. are left untouched. Idempotent.
]]
local RS = game:GetService("ReplicatedStorage")
local Schema = require(RS.Hazastudio_ClubKit.Shared.Config.ClubKitConfigSchema)
local defaults = Schema.defaults
local mod = RS.Hazastudio_ClubKitConfig.ClubKitConfig
local src = mod.Source

-- Luau literal serializer (same shape ConfigPatchCore writes: tabs, sorted keys, arrays inline).
local function serialize(value, indent)
	local pad = string.rep("\t", indent)
	local t = typeof(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" then
		return if value == math.huge then "math.huge" else tostring(value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "Vector3" then
		return ("Vector3.new(%s, %s, %s)"):format(value.X, value.Y, value.Z)
	elseif t == "table" then
		local isArray, n = true, 0
		for k in pairs(value) do n += 1 if type(k) ~= "number" then isArray = false end end
		if n == 0 then return "{}" end
		local parts = {}
		if isArray then
			local inlineOk = true
			for i = 1, #value do if type(value[i]) == "table" then inlineOk = false end end
			if inlineOk then
				for i = 1, #value do table.insert(parts, serialize(value[i], indent + 1)) end
				return "{ " .. table.concat(parts, ", ") .. " }"
			end
			for i = 1, #value do table.insert(parts, pad .. "\t" .. serialize(value[i], indent + 1) .. ",") end
			return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
		end
		local keys = {}
		for k in pairs(value) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			local keyLit = if type(k) == "string" and k:match("^[%a_][%w_]*$") then k else ("[%s]"):format(serialize(k, 0))
			table.insert(parts, ("%s\t%s = %s,"):format(pad, keyLit, serialize(value[k], indent + 1)))
		end
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
	end
	return "nil"
end

local function spanReplace(startAnchor, endAnchor, replacement, keepEnd)
	local s = string.find(src, startAnchor, 1, true); assert(s, "anchor: " .. startAnchor)
	local e1, e2 = string.find(src, endAnchor, s, true); assert(e1, "end anchor: " .. endAnchor)
	local cutEnd = if keepEnd then e1 - 1 else e2
	src = string.sub(src, 1, s - 1) .. replacement .. string.sub(src, cutEnd + 1)
end

spanReplace("ClubKitConfig.RoleCategories = {", "} :: { any }", "ClubKitConfig.RoleCategories = " .. serialize(defaults.RoleCategories, 0) .. " :: { any }")
spanReplace("ClubKitConfig.SystemRoles = {", "\n}\n", "ClubKitConfig.SystemRoles = " .. serialize(defaults.SystemRoles, 0) .. "\n")
spanReplace("ClubKitConfig.LegacyAliases = {", "-- =============================================================================\n-- JOIN COMMUNITY",
	"ClubKitConfig.LegacyAliases = " .. serialize(defaults.LegacyAliases, 0) .. "\n\nClubKitConfig.CommandAliases = " .. serialize(defaults.CommandAliases, 0) .. "\n\n", true)
src = string.gsub(src, "\tLoadingScreen = false,[^\n]*", "\tLoadingScreen = true,", 1)

local fn, err = loadstring(src, "=ClubKitConfig"); assert(fn, err)
setfenv(fn, setmetatable({ script = mod }, { __index = getfenv() }))
local cfg = fn()
assert(cfg.RoleCategories[1].roles[1].key == "CoOwner" and cfg.Features.LoadingScreen == true, "sanity")
mod.Source = src

local cl = game:GetService("ReplicatedFirst"):FindFirstChild("CinematicLoading")
if cl then cl.Disabled = true end
print("[Hierapolis add-on] REVERTED to stock catalog; kit loading screen on; CinematicLoading disabled")
return "reverted"
