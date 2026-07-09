--!nocheck
-- Paste into Studio Command Bar (Edit Mode). Prints stat label paths under 1-DonorProfile.
local StarterGui = game:GetService("StarterGui")
local GUI_NAME = "09-DonationSystemGUI"

local root = StarterGui:FindFirstChild(GUI_NAME)
if not root then
	warn("[PrintDonationDonorProfile] Missing StarterGui." .. GUI_NAME)
	return
end

local donorProfile = root:FindFirstChild("MainWrapper", true)
	and root.MainWrapper:FindFirstChild("02-MainContentWrapper", true)
	and root.MainWrapper["02-MainContentWrapper"]:FindFirstChild("1-DonorProfile", true)
if not donorProfile then
	warn("[PrintDonationDonorProfile] 1-DonorProfile not found")
	return
end

local searchRoot = donorProfile:FindFirstChild("MainContentWrapper") or donorProfile
print("=== Donor profile stat candidates under", searchRoot:GetFullName(), "===")

local function line(gui: Instance)
	local text = ""
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		text = (gui :: TextLabel).Text
	end
	print(
		string.format(
			"%s [%s] Visible=%s Text=%q",
			gui:GetFullName(),
			gui.ClassName,
			tostring((gui :: GuiObject).Visible),
			text
		)
	)
end

for _, inst in ipairs(searchRoot:GetDescendants()) do
	if not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		continue
	end
	local text = (inst :: TextLabel).Text
	local nameLower = inst.Name:lower()
	if text == "#-" or text == "0" or nameLower:find("rank", 1, true) or nameLower:find("value", 1, true) then
		line(inst)
	end
end

for _, inst in ipairs(searchRoot:GetDescendants()) do
	if not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		continue
	end
	local lower = string.lower((inst :: TextLabel).Text)
	if lower == "top donate" or lower == "top spender" or lower == "bagibagi" then
		print("--- section title:", inst:GetFullName(), "---")
	end
end

print("Expected bind paths (NUWA):")
print("  Robux rank:  ...PlayerStats.RobuxDonation.RobuxRank")
print("  Robux value: ...PlayerStats.RobuxDonation.RobuxValue.ValueWrapper.RobuxValueDynamic")
print("  Bagi-Bagi rank: ...PlayerStats (section title 'BagiBagi' / legacy SaweriaDonations)")
print("  Bagi-Bagi value: ...BagiBagi section ValueWrapper (legacy: SaweriaDonations.SaweriaValueDynamic)")
warn("[PrintDonationDonorProfile] Done. Copy Output lines to align DonationSystemGuiRefs.")
