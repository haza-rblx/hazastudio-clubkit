-- ============================================================
-- Running Text Debug — paste ke Command Bar (F9) saat Play Mode
-- ============================================================

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

print("========== Running Text Debug ==========")

-- 1. Cek tagged objects di workspace
local runningRoots = CollectionService:GetTagged("RunningText")
print("[1] Workspace objects tagged 'RunningText':", #runningRoots)

for i, root in ipairs(runningRoots) do
	print(string.format("  #%d: %s (Parent: %s)", i, root:GetFullName(), root.Parent and root.Parent.Name or "nil"))

	-- Cari SurfaceGui
	local gui = root:FindFirstChild("RunningTextGUI", true)
	if gui and gui:IsA("SurfaceGui") then
		print("    RunningTextGUI: ✅ found")
		local wrapper = gui:FindFirstChild("Wrapper", true)
		local content = gui:FindFirstChild("ContentWrapper", true)
		local textLabel = gui:FindFirstChild("CustomizeableText", true)
		local logo = gui:FindFirstChild("LogoImage", true)

		print("    Wrapper:", wrapper and "✅" or "❌ MISSING")
		print("    ContentWrapper:", content and "✅" or "❌ MISSING")
		print("    CustomizeableText:", textLabel and "✅" or "❌ MISSING")
		print("    LogoImage:", logo and "✅" or "❌ MISSING")

		if textLabel and textLabel:IsA("TextLabel") then
			print("    Text:", '"' .. textLabel.Text .. '"')
			print("    TextBounds:", textLabel.TextBounds)
		end
		if wrapper and wrapper:IsA("Frame") then
			print("    Wrapper AbsoluteSize:", wrapper.AbsoluteSize)
		end
		if gui then
			print("    SurfaceGui Enabled:", gui.Enabled)
			print("    SurfaceGui Adornee:", gui.Adornee and gui.Adornee.Name or "nil")
		end
	else
		print("    RunningTextGUI: ❌ NOT FOUND — cari di dalam root:")
		for _, child in ipairs(root:GetDescendants()) do
			if child:IsA("SurfaceGui") then
				print("      SurfaceGui:", child.Name, "| Enabled:", child.Enabled)
			end
		end
	end
end

-- 2. Cek DonationNotificationController
local player = Players.LocalPlayer
if player then
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if playerScripts then
		local controller = playerScripts:FindFirstChild("DonationNotificationController", true)
		if controller then
			print("\n[2] DonationNotificationController script: ✅ found")
		else
			print("\n[2] DonationNotificationController script: ❌ NOT FOUND in PlayerScripts")
		end
	end
end

-- 3. Cek Config
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:FindFirstChild("Shared")
if Config then
	Config = Config:FindFirstChild("Constants")
	if Config then
		Config = require(Config)
		print("\n[3] Config.Donation state:")
		print("    RUNNING_TEXT_DEBUG:", Config.Donation.RUNNING_TEXT_DEBUG)
		print("    WORKSPACE_RESTORE_DELAY:", Config.Donation.WORKSPACE_RESTORE_DELAY)
		print("    NOTIFICATION_DURATION:", Config.Donation.NOTIFICATION_DURATION)
	else
		print("\n[3] Config: ❌ Constants not found")
	end
else
	print("\n[3] Config: ❌ Shared not found")
end

-- 4. Cek LiveChatDonations juga
local liveRoots = CollectionService:GetTagged("LiveChatDonations")
print("\n[4] Workspace objects tagged 'LiveChatDonations':", #liveRoots)
for i, root in ipairs(liveRoots) do
	print(string.format("  #%d: %s", i, root:GetFullName()))
	local gui = root:FindFirstChild("LiveChatGUI", true) or root:FindFirstChild("SurfaceGui", true)
	print("    LiveChatGUI:", gui and "✅" or "❌")
end

print("\n=========================================")
print("Kalau semua ✅ tapi running text ga jalan,")
print("coba cek Client/DonationNotificationController")
print("di log Runtime — cari [WARN] atau [ERROR].")
print("=========================================")
