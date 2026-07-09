--!strict
-- Roblox subscription detection + Plus icon (BuilderSans unicode glyph).

local RobloxPlatformIcons = {}

local BUILDER_SANS_FONT = "rbxasset://fonts/families/BuilderSans.json"
local PLUS_UNICODE = utf8.char(0xE003)

RobloxPlatformIcons.PLUS_ICON = PLUS_UNICODE

function RobloxPlatformIcons.getPlusBadgeFont(): Font
	return Font.new(BUILDER_SANS_FONT, Enum.FontWeight.Heavy)
end

function RobloxPlatformIcons.getPlusBadgeText(): string
	return PLUS_UNICODE
end

-- Visual weight boost for the platform glyph (unicode has no filled variant).
function RobloxPlatformIcons.getPlusBadgeTextSize(referenceTextSize: number): number
	return math.max(12, math.ceil(referenceTextSize * 1.22))
end

-- HasRobloxSubscription (Plus) and legacy Premium membership both get the Plus icon.
function RobloxPlatformIcons.playerHasPaidRobloxSubscription(player: Player): boolean
	if player.MembershipType == Enum.MembershipType.Premium then
		return true
	end
	local ok, hasSubscription = pcall(function()
		return player.HasRobloxSubscription
	end)
	return ok and hasSubscription == true
end

return RobloxPlatformIcons
