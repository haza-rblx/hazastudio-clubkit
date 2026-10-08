--!strict
-- Foreign GUI detector (ADR 0012), client half. A LEARNING signal: it names what it
-- saw and nothing else happens. There is no kick and no brick path on this signal.
--
-- WHAT IT CAN SEE — read this before trusting a quiet log:
--   PlayerGui, and only PlayerGui. `game:GetService("CoreGui")` returns nil at
--   LocalScript identity (measured live in this place), so an executor UI parented to
--   CoreGui or to a `gethui()` container is INVISIBLE to kit code. Most GUI executors
--   park their window exactly there. A clean log therefore means "nothing foreign
--   landed in PlayerGui", never "this client is clean".
--
-- The report names the GUI and the scripts inside it, because a report that only says
-- "something appeared" is not actionable. Everything is capped and sanitised through
-- Shared/Domain/ForeignGuiPolicy before it is sent, and the server re-applies the same
-- rules to the payload (it is hostile input there).
--
-- False positives are the cost that matters: this place carries non-kit GUIs
-- (1000-01-CT-ADDON, DanceGui, AvatarContextMenu, IconGroup) and other buyer places
-- run Adonis / Kohl's. Three things are therefore never foreign: whatever is in
-- PlayerGui once boot has settled, anything whose name exists in StarterGui (respawn
-- re-clones and the kit's own StarterGui fallbacks land that way), and the kit's own
-- runtime GUIs. Buyers add their own names via Config.AntiTamper.FOREIGN_GUI_ALLOW_NAMES.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ForeignGuiPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ForeignGuiPolicy)

local ForeignGuiGuardService = {}

-- GUIs the kit itself creates at runtime (not clones of a StarterGui child), so they
-- arrive after the boot snapshot and would otherwise look foreign.
local KIT_RUNTIME_GUI_NAMES: { [string]: boolean } = {
	TopbarStandard = true, -- Icon / TopbarPlus container
	TopbarCentered = true,
	CinematicDockBarsGui = true,
	CinematicDualShutter = true,
	ClubKitImageResidency = true,
	MobilePanelOverlay = true,
	ClubKitBootHalted = true,
	EmoteGui = true,
	["99-NotificationCenter"] = true,
	ClubKitIsland = true, -- NotificationIsland fallback host
	ClubKitOnboarding = true, -- OnboardingUI modal (built from the 17-OnboardingGUI sketch)
}

-- An executor builds its window over several frames; sampling the instant it is
-- parented would report "0 descendants, no scripts" and waste the report.
local SETTLE_SECONDS = 1
-- Ceiling on the descendant walk, so a deliberately enormous GUI cannot stall the
-- client that is trying to describe it.
local MAX_DESCENDANTS_SCANNED = 2000

local _started = false

local function fireReport(guiInfo: ForeignGuiPolicy.GuiInfo)
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local sec = kit and kit:FindFirstChild("SecuritySignals")
	local remote = sec and sec:FindFirstChild("ReportTamper")
	if remote and remote:IsA("RemoteEvent") then
		pcall(function()
			(remote :: RemoteEvent):FireServer("foreign_gui", guiInfo)
		end)
	end
end

-- Name + class of the GUI, and the names + classes of the scripts inside it — the
-- "nama gui/script" a Discord report has to carry to be worth reading.
local function describe(gui: Instance): ForeignGuiPolicy.GuiInfo?
	local ok, descendants = pcall(function()
		return gui:GetDescendants()
	end)
	local list: { Instance } = if ok and type(descendants) == "table" then descendants else {}

	local scripts: { { name: string, className: string } } = {}
	local scriptCount = 0
	local scanned = 0
	for _, child in ipairs(list) do
		scanned += 1
		if scanned > MAX_DESCENDANTS_SCANNED then
			break
		end
		if child:IsA("LuaSourceContainer") then
			scriptCount += 1
			if #scripts < ForeignGuiPolicy.MAX_SCRIPTS_PER_GUI then
				table.insert(scripts, { name = child.Name, className = child.ClassName })
			end
		end
	end

	local resetOnSpawn: boolean? = nil
	if gui:IsA("ScreenGui") then
		resetOnSpawn = gui.ResetOnSpawn
	end

	-- Normalise client-side too: the payload that leaves this machine is already
	-- capped and sanitised, so an honest client never sends anything oversized.
	return ForeignGuiPolicy.normalize({
		name = gui.Name,
		className = gui.ClassName,
		resetOnSpawn = resetOnSpawn,
		descendants = #list,
		scriptCount = scriptCount,
		scripts = scripts,
	})
end

function ForeignGuiGuardService.start()
	if _started then
		return
	end
	_started = true

	if RunService:IsStudio() then
		return
	end
	local at = Config.AntiTamper or {}
	if at.FOREIGN_GUI_DETECT_ENABLED ~= true then
		return
	end

	local grace = tonumber(at.FOREIGN_GUI_GRACE_SECONDS) or 20
	if grace < 0 then
		grace = 0
	end
	local maxReports = tonumber(at.FOREIGN_GUI_MAX_REPORTS_PER_PLAYER)
		or ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER
	if maxReports > ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER then
		maxReports = ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER
	end

	local configAllow: { [string]: boolean } = {}
	if type(at.FOREIGN_GUI_ALLOW_NAMES) == "table" then
		for _, name in ipairs(at.FOREIGN_GUI_ALLOW_NAMES) do
			if type(name) == "string" then
				configAllow[name] = true
			end
		end
	end

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui", 60)
		if not (playerGui and playerGui:IsA("PlayerGui")) then
			return
		end

		-- Everything present once boot has settled is the allowlist. A GUI added in the
		-- window between this snapshot and the connection below is missed rather than
		-- reported — the safe direction for a signal whose cost is a false accusation.
		if grace > 0 then
			task.wait(grace)
		end
		local bootNames: { [string]: boolean } = {}
		for _, child in ipairs(playerGui:GetChildren()) do
			bootNames[child.Name] = true
		end

		local reported: { [string]: boolean } = {}
		local reportCount = 0

		local function isAllowed(name: string): boolean
			if bootNames[name] or KIT_RUNTIME_GUI_NAMES[name] or configAllow[name] then
				return true
			end
			-- Respawn re-clones every ResetOnSpawn GUI out of StarterGui, and several kit
			-- paths clone their own StarterGui child on demand. Both arrive post-boot.
			return StarterGui:FindFirstChild(name) ~= nil
		end

		playerGui.ChildAdded:Connect(function(child: Instance)
			if reportCount >= maxReports then
				return
			end
			if not (child:IsA("GuiBase") or child:IsA("LayerCollector")) then
				return
			end
			local name = child.Name
			if reported[name] or isAllowed(name) then
				return
			end
			reported[name] = true
			reportCount += 1

			task.delay(SETTLE_SECONDS, function()
				-- A GUI that flickered in and out is still worth naming, so describe it
				-- whether or not it is still parented here.
				local info = describe(child)
				if info then
					fireReport(info)
				end
			end)
		end)
	end)
end

return ForeignGuiGuardService
