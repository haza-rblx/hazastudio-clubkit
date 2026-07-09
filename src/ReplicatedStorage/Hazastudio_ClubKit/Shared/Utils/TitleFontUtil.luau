--!strict
-- Safe Enum.Font resolution for admin custom title fonts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local TitleFontUtil = {}

local cachedValidFonts: { string }? = nil

local function isCustomFontPath(fontName: string): boolean
	return string.find(fontName, "rbxasset", 1, true) ~= nil
end

local FONT_WEIGHT_PRIORITY: { Enum.FontWeight } = {
	Enum.FontWeight.ExtraBold,
	Enum.FontWeight.Bold,
	Enum.FontWeight.SemiBold,
	Enum.FontWeight.Medium,
	Enum.FontWeight.Regular,
}

-- Heaviest-first preference among configured admin title fonts.
local BOLDEST_FONT_PRIORITY: { string } = {
	"GothamBlack",
	"ArimoBold",
	"SourceSansBold",
	"GothamBold",
	"Bangers",
	"LuckiestGuy",
	"DenkOne",
	"PermanentMarker",
	"Creepster",
	"FredokaOne",
	"SpecialElite",
	"Michroma",
	"RobotoCondensed",
	"TitilliumWeb",
	"Ubuntu",
}

function TitleFontUtil.resolveEnum(fontName: string?): Enum.Font?
	if type(fontName) ~= "string" or fontName == "" then
		return nil
	end

	local ok, fontEnum = pcall(function()
		return (Enum.Font :: any)[fontName]
	end)
	if ok and typeof(fontEnum) == "EnumItem" then
		return fontEnum
	end
	return nil
end

function TitleFontUtil.isValidName(fontName: string?): boolean
	if type(fontName) ~= "string" or fontName == "" then
		return false
	end
	if isCustomFontPath(fontName) then
		local ok = pcall(function()
			Font.new(fontName, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
		end)
		return ok
	end
	return TitleFontUtil.resolveEnum(fontName) ~= nil
end

function TitleFontUtil.applyToTextLabel(label: TextLabel, fontName: string?): boolean
	if type(fontName) ~= "string" or fontName == "" then
		return false
	end

	if isCustomFontPath(fontName) then
		for _, weight in ipairs(FONT_WEIGHT_PRIORITY) do
			local ok = pcall(function()
				label.FontFace = Font.new(fontName, weight, Enum.FontStyle.Normal)
			end)
			if ok then
				return true
			end
		end
		return false
	end

	local fontEnum = TitleFontUtil.resolveEnum(fontName)
	if not fontEnum then
		return false
	end

	label.Font = fontEnum
	local ok = pcall(function()
		label.FontFace = Font.fromEnum(fontEnum)
	end)
	return ok
end

function TitleFontUtil.getConfiguredFonts(): { string }
	if cachedValidFonts then
		return cachedValidFonts
	end

	local valid: { string } = {}
	local configured = Config.Admin and Config.Admin.TITLE_FONTS
	if type(configured) == "table" then
		for _, fontName in ipairs(configured) do
			if type(fontName) == "string" and TitleFontUtil.isValidName(fontName) then
				table.insert(valid, fontName)
			end
		end
	end

	if #valid == 0 then
		valid = { "GothamBold" }
	end

	cachedValidFonts = valid
	return valid
end

function TitleFontUtil.getBoldestConfiguredFont(): string
	local fonts = TitleFontUtil.getConfiguredFonts()
	local lookup = {} :: { [string]: true }
	for _, fontName in ipairs(fonts) do
		lookup[fontName] = true
	end

	for _, candidate in ipairs(BOLDEST_FONT_PRIORITY) do
		if lookup[candidate] then
			return candidate
		end
	end

	for _, fontName in ipairs(fonts) do
		if string.find(fontName, "Black", 1, true) then
			return fontName
		end
	end
	for _, fontName in ipairs(fonts) do
		if string.find(fontName, "Bold", 1, true) then
			return fontName
		end
	end

	return fonts[1]
end

function TitleFontUtil.resolveName(fontName: string?): string
	local fonts = TitleFontUtil.getConfiguredFonts()
	if type(fontName) == "string" and fontName ~= "" then
		for _, candidate in ipairs(fonts) do
			if candidate == fontName then
				return fontName
			end
		end
	end
	return TitleFontUtil.getBoldestConfiguredFont()
end

return TitleFontUtil
