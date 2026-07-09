--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local PaidBroadcastTitleCopy = {}

local function displayNameFor(player: Player): string
	local name = player.DisplayName
	if type(name) == "string" and name ~= "" then
		return name
	end
	return player.Name
end

local function applyPlaceholders(template: string, player: Player): string
	local displayName = displayNameFor(player)
	local text = template
	text = string.gsub(text, "{name}", displayName)
	text = string.gsub(text, "{username}", player.Name)
	return text
end

local function clampTitle(text: string): string
	local maxLen = Config.PaidBroadcast.MODAL_TITLE_MAX_LENGTH
	if #text <= maxLen then
		return text
	end
	return string.sub(text, 1, maxLen - 1) .. "…"
end

function PaidBroadcastTitleCopy.pickModalTitle(player: Player): string
	local variants = Config.PaidBroadcast.MODAL_TITLE_VARIANTS
	if type(variants) ~= "table" or #variants == 0 then
		return Config.PaidBroadcast.MODAL_TITLE_FALLBACK
	end
	local index = math.random(1, #variants)
	local template = variants[index]
	if type(template) ~= "string" or template == "" then
		return Config.PaidBroadcast.MODAL_TITLE_FALLBACK
	end
	return clampTitle(applyPlaceholders(template, player))
end

return PaidBroadcastTitleCopy
