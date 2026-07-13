--!strict
--[[
  F9 Developer Console splash — ASCII Hazastudio + kit version + contact.
  Print sekali per context (client / server). Selalu tampil (termasuk production).
]]

local RunService = game:GetService("RunService")

local BANNER_FLAG = "__Hazastudio_ConsoleBannerPrinted"

-- Monospace-friendly; keep width ~58 cols for F9.
local ASCII_ART = [[
  _   _                     _             _ _
 | | | | __ _ ______ _  ___| |_ _   _  __| (_) ___
 | |_| |/ _` |_  / _` |/ __| __| | | |/ _` | |/ _ \
 |  _  | (_| |/ / (_| |\__ \ |_| |_| | (_| | | (_) |
 |_| |_|\__,_/___\__,_|___/\__|\__,_|\__,_|_|\___/
]]

local ConsoleBanner = {}

local function nonEmpty(value: any): string?
	if type(value) == "string" then
		local trimmed = string.match(value, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			return trimmed
		end
	end
	return nil
end

local function appendLine(lines: { string }, label: string, value: string?)
	if value then
		table.insert(lines, string.format("  %-9s %s", label, value))
	end
end

function ConsoleBanner.printOnce(kitProduct: any?)
	local sharedTable = shared :: any
	if sharedTable[BANNER_FLAG] == true then
		return
	end
	sharedTable[BANNER_FLAG] = true

	local product = if type(kitProduct) == "table" then kitProduct else {}
	local support = if type(product.Support) == "table" then product.Support else {}
	local side = if RunService:IsServer() then "SERVER" else "CLIENT"
	local version = tostring(product.KitVersion or "?")
	local buildId = nonEmpty(product.BuildId)
	local productName = nonEmpty(product.ProductName) or "Hazastudio Clubkit"
	local vendor = nonEmpty(product.Vendor) or "Hazastudio"

	local lines = {
		"",
		ASCII_ART,
		"  ------------------------------------------------------------",
		string.format("  %s  ·  %s", vendor, productName),
		string.format(
			"  Version   v%s%s",
			version,
			if buildId then ("  ·  build " .. buildId) else ""
		),
		string.format("  Context   %s  ·  F9 Developer Console", side),
	}

	appendLine(lines, "Discord", nonEmpty(support.Discord))
	appendLine(lines, "Website", nonEmpty(support.Website))
	appendLine(lines, "Roblox", nonEmpty(support.Roblox))
	appendLine(lines, "Email", nonEmpty(support.Email))
	appendLine(
		lines,
		"Note",
		nonEmpty(support.Note) or "Need help? Contact club staff or Hazastudio support."
	)

	table.insert(lines, "  ------------------------------------------------------------")
	table.insert(lines, "")

	print(table.concat(lines, "\n"))
end

return ConsoleBanner
