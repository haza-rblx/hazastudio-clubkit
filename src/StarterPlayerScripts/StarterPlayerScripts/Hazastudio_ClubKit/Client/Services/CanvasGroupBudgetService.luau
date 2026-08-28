--!strict
-- CanvasGroupBudgetService — releases far-away workspace CanvasGroup textures (ADR 0005).
--
-- Every SurfaceGui in Workspace that contains a CanvasGroup holds a GPU texture sized by the
-- group's AbsoluteSize (a 63 px/stud poster ≈ 5 MB each; RUST carries 20 such GUIs, ~48 MB,
-- allocated at spawn even 200+ studs away). Roblox docs: once the client's texture budget is
-- exceeded a CanvasGroup renders BLANK — and, measured on RUST, a ScreenGui panel that failed
-- to allocate stays blank until those big textures are released. This service keeps the
-- budget free for the UI the player is actually looking at: a tracked SurfaceGui is disabled
-- (texture released) while its anchor part is farther than SURFACE_CULL_DISTANCE studs from
-- the camera, and re-enabled once it comes back within DISTANCE - HYSTERESIS.
--
-- Ownership rules (so this never fights another system):
--   * Only GUIs that were Enabled=true when observed far away are culled, and only GUIs this
--     service culled are re-enabled. A GUI another script disables stays disabled.
--   * Opt-out per GUI: set attribute `ClubKitKeepSurfaceGui = true` on the SurfaceGui.
--   * No kit code writes SurfaceGui.Enabled elsewhere (verified 2026-08-27).
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("CanvasGroupBudgetService")

local OPT_OUT_ATTRIBUTE = "ClubKitKeepSurfaceGui"
local DEFAULTS = {
	ENABLED = true,
	SURFACE_CULL_DISTANCE = 250,
	SURFACE_CULL_HYSTERESIS = 20,
	POLL_INTERVAL = 0.5,
}

local CanvasGroupBudgetService = {}

local tracked: { [SurfaceGui]: boolean } = {}
local culled: { [SurfaceGui]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local accumulator = 0
local started = false

local function cfg(): typeof(DEFAULTS)
	local raw = (Config :: any).CanvasGroupBudget
	if type(raw) ~= "table" then
		return DEFAULTS
	end
	return {
		ENABLED = if raw.ENABLED == false then false else true,
		SURFACE_CULL_DISTANCE = math.max(tonumber(raw.SURFACE_CULL_DISTANCE) or DEFAULTS.SURFACE_CULL_DISTANCE, 10),
		SURFACE_CULL_HYSTERESIS = math.max(tonumber(raw.SURFACE_CULL_HYSTERESIS) or DEFAULTS.SURFACE_CULL_HYSTERESIS, 0),
		POLL_INTERVAL = math.max(tonumber(raw.POLL_INTERVAL) or DEFAULTS.POLL_INTERVAL, 0.1),
	}
end

local function anchorOf(gui: SurfaceGui): BasePart?
	local adornee = gui.Adornee
	if adornee and adornee:IsA("BasePart") then
		return adornee
	end
	local parent = gui.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	return nil
end

local function hasGroup(gui: SurfaceGui): boolean
	return gui:FindFirstChildWhichIsA("CanvasGroup", true) ~= nil
end

local function distanceTo(part: BasePart): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	-- Edge distance, so a wide board is not culled while its centre is far but its edge is near.
	return math.max((part.Position - camera.CFrame.Position).Magnitude - part.Size.Magnitude * 0.5, 0)
end

local function consider(inst: Instance)
	if not inst:IsA("SurfaceGui") then
		return
	end
	-- Rojo/packager may parent the SurfaceGui before its CanvasGroup children arrive.
	task.defer(function()
		if inst.Parent and hasGroup(inst) then
			tracked[inst] = true
		end
	end)
end

local function forget(inst: Instance)
	if not inst:IsA("SurfaceGui") then
		return
	end
	if culled[inst] then
		culled[inst] = nil
		inst.Enabled = true
	end
	tracked[inst] = nil
end

local function step()
	local c = cfg()
	local cullAt = c.SURFACE_CULL_DISTANCE
	local restoreAt = math.max(cullAt - c.SURFACE_CULL_HYSTERESIS, 0)
	for gui in pairs(tracked) do
		if not gui.Parent then
			tracked[gui] = nil
			culled[gui] = nil
			continue
		end
		if gui:GetAttribute(OPT_OUT_ATTRIBUTE) == true then
			if culled[gui] then
				culled[gui] = nil
				gui.Enabled = true
			end
			continue
		end
		local part = anchorOf(gui)
		if not part then
			continue
		end
		local distance = distanceTo(part)
		if culled[gui] then
			if distance <= restoreAt then
				culled[gui] = nil
				gui.Enabled = true
			end
		elseif gui.Enabled and distance > cullAt then
			gui.Enabled = false
			culled[gui] = true
		end
	end
end

function CanvasGroupBudgetService.getStats(): { tracked: number, culled: number }
	local t, k = 0, 0
	for _ in pairs(tracked) do
		t += 1
	end
	for _ in pairs(culled) do
		k += 1
	end
	return { tracked = t, culled = k }
end

function CanvasGroupBudgetService.start()
	if started then
		return
	end
	local c = cfg()
	if not c.ENABLED then
		log:info("disabled by Config.CanvasGroupBudget.ENABLED")
		return
	end
	started = true
	for _, inst in ipairs(Workspace:GetDescendants()) do
		consider(inst)
	end
	table.insert(connections, Workspace.DescendantAdded:Connect(consider))
	table.insert(connections, Workspace.DescendantRemoving:Connect(forget))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < cfg().POLL_INTERVAL then
			return
		end
		accumulator = 0
		step()
	end))
	-- First pass right away so spawn-distance posters release before the first panel opens.
	task.defer(step)
	log:info("started", { cullDistance = c.SURFACE_CULL_DISTANCE })
end

function CanvasGroupBudgetService.destroy()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	for gui in pairs(culled) do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(culled)
	table.clear(tracked)
	started = false
end

return CanvasGroupBudgetService
