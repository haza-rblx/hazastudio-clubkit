--!strict
--[[
	Removes kit ScreenGui templates that this server will never bind from StarterGui at boot,
	so they are not cloned into every player's PlayerGui on each spawn. Runtime only: the
	place file is not changed, and a template is only removed when the code that would use
	it is provably off for this server.

	  • 04-AdminHub        — always unused: the Admin Hub surface is the code-built
	                         04-AdminSpotlight (AdminSpotlightUI); nothing binds the shell.
	  • 04-AdminPanel (v1) — unused when 04-AdminPanelv2 exists (AdminController takes the
	                         first of Config.Admin.GUI_NAME_CANDIDATES).
	  • 04-AdminPanelv3    — unused unless FeatureFlags.AdminPanelV3Enabled.

	Measured in Experiment Area: 04-AdminHub alone is ~625 instances per player.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local function deadTemplates(Config: any): { string }
	local names = {}
	local admin = Config.Admin or {}
	if type(admin.HUB_GUI_NAME) == "string" then
		table.insert(names, admin.HUB_GUI_NAME)
	end
	-- Keep the first candidate that is installed; the rest are never bound.
	local candidates = admin.GUI_NAME_CANDIDATES
	if type(candidates) == "table" then
		local kept = false
		for _, name in ipairs(candidates) do
			if StarterGui:FindFirstChild(name) then
				if kept then
					table.insert(names, name)
				end
				kept = true
			end
		end
	end
	local flags = Config.FeatureFlags or {}
	if flags.AdminPanelV3Enabled ~= true and type(admin.GUI_NAME_V3) == "string" then
		table.insert(names, admin.GUI_NAME_V3)
	end
	return names
end

return function(Config: any): { string }
	local removed = {}
	for _, name in ipairs(deadTemplates(Config)) do
		local template = StarterGui:FindFirstChild(name)
		if template and template:IsA("ScreenGui") then
			template:Destroy()
			table.insert(removed, name)
			-- Players that spawned before boot finished already hold a copy.
			for _, player in ipairs(Players:GetPlayers()) do
				local playerGui = player:FindFirstChildOfClass("PlayerGui")
				local copy = playerGui and playerGui:FindFirstChild(name)
				if copy then
					copy:Destroy()
				end
			end
		end
	end
	return removed
end
