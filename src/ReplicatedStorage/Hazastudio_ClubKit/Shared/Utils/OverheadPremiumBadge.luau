--!strict
-- Server-only: premium/plus overhead badge disabled (hide template + destroy runtime badge).

local RunService = game:GetService("RunService")

local HIDDEN_BADGE_NAMES = {
	"RobloxPlusBadge",
	"RobloxPremiumBadge",
}

local OverheadPremiumBadge = {}

local function hidePremiumBadgeNode(descendant: Instance, badgeName: string)
	if descendant.Name ~= badgeName then
		return
	end
	if badgeName == "RobloxPlusBadge" and descendant:IsA("TextLabel") then
		descendant:Destroy()
	elseif descendant:IsA("GuiObject") then
		(descendant :: GuiObject).Visible = false
	end
end

function OverheadPremiumBadge.apply(gui: BillboardGui, _payload: { [string]: any }?)
	if not RunService:IsServer() or not gui.Parent then
		return
	end

	for _, descendant in ipairs(gui:GetDescendants()) do
		for _, badgeName in ipairs(HIDDEN_BADGE_NAMES) do
			hidePremiumBadgeNode(descendant, badgeName)
		end
	end
end

return OverheadPremiumBadge
