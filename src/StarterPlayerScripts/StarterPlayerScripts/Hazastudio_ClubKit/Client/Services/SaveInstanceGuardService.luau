--!strict
-- Live saveinstance / exploit detector (ADR 0006 Pillar 5), client half.
--
-- UGCValidationService is not part of a normal client DataModel until a
-- saveinstance / exploit environment references it — a well-known, low
-- false-positive signal (unlike name-blacklist scanners). This is a speed bump
-- for lazy exploiters; a determined one bypasses it with hookmetamethod. It is
-- ALWAYS off in Studio, and only bricks when the owner explicitly opts in
-- (`Config.AntiTamper.BRICK_ON_DETECT`) — a false brick on a paying player is
-- worse than missing a thief.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local SaveInstanceGuardService = {}

local _started = false

local function brick()
	-- Non-permanent: freezes the offending client's OWN session only (nothing
	-- reaches the disk or another player). The exploiter restarts to recover.
	pcall(function()
		local char = Players.LocalPlayer.Character
		if char then
			char:Destroy()
		end
	end)
	while true do
		RunService.RenderStepped:Wait()
	end
end

local function fireReport()
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local sec = kit and kit:FindFirstChild("SecuritySignals")
	local remote = sec and sec:FindFirstChild("ReportTamper")
	if remote and remote:IsA("RemoteEvent") then
		pcall(function()
			(remote :: RemoteEvent):FireServer("saveinstance")
		end)
	end
end

function SaveInstanceGuardService.start()
	if _started then
		return
	end
	_started = true

	if RunService:IsStudio() then
		return
	end
	local at = Config.AntiTamper or {}
	if at.SAVEINSTANCE_DETECT_ENABLED ~= true then
		return
	end
	local interval = tonumber(at.DETECT_POLL_INTERVAL) or 2
	local brickOnDetect = at.BRICK_ON_DETECT == true

	task.spawn(function()
		while true do
			local ok, svc = pcall(function()
				return game:FindService("UGCValidationService")
			end)
			if ok and svc then
				fireReport()
				if brickOnDetect then
					brick()
				end
				return
			end
			task.wait(interval)
		end
	end)
end

return SaveInstanceGuardService
