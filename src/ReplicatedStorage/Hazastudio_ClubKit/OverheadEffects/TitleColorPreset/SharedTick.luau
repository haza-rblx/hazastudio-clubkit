--!strict
-- Shared ~30Hz tick for TitleColorPreset Gradient / Stroke / Dropshadow.
-- Replaces one RunService.Heartbeat per animated instance (N CCU titles → 1 loop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type TickFn = (dt: number) -> ()

type TickEntry = {
	tick: TickFn,
	uiInstance: Instance?,
}

local SharedTick = {}

local entries: { [any]: TickEntry } = {}
local conn: RBXScriptConnection? = nil
local accum = 0

local cachedOpts: {
	sharedEnabled: boolean,
	legacyPerInstance: boolean,
	skipHidden: boolean,
	interval: number,
}? =
	nil

local function readOpts()
	if cachedOpts then
		return cachedOpts
	end
	local sharedEnabled = true
	local legacyPerInstance = false
	local skipHidden = true
	local hz = 30
	local ok, Config = pcall(function()
		return require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
	end)
	if ok and type(Config) == "table" then
		local tcp = (Config :: any).TitleColorPreset
		if type(tcp) == "table" then
			if tcp.SHARED_TICK_ENABLED == false then
				sharedEnabled = false
			end
			if tcp.USE_LEGACY_PER_INSTANCE_HEARTBEAT == true then
				legacyPerInstance = true
			end
			if tcp.SKIP_HIDDEN == false then
				skipHidden = false
			end
			local configuredHz = tonumber(tcp.TICK_HZ)
			if configuredHz and configuredHz > 0 then
				hz = math.clamp(configuredHz, 10, 60)
			end
		end
	end
	cachedOpts = {
		sharedEnabled = sharedEnabled and not legacyPerInstance,
		legacyPerInstance = legacyPerInstance or not sharedEnabled,
		skipHidden = skipHidden,
		interval = 1 / hz,
	}
	return cachedOpts
end

local function isGuiTreeVisible(inst: Instance?): boolean
	local cur: Instance? = inst
	while cur do
		if cur:IsA("GuiObject") and not (cur :: GuiObject).Visible then
			return false
		end
		if cur:IsA("LayerCollector") and not (cur :: LayerCollector).Enabled then
			return false
		end
		if cur:IsA("PlayerGui") or cur:IsA("Workspace") or cur:IsA("StarterGui") then
			break
		end
		cur = cur.Parent
	end
	return true
end

local function ensureConn()
	if conn then
		return
	end
	local opts = readOpts()
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if next(entries) == nil then
			return
		end
		if opts.legacyPerInstance then
			-- Should not happen when shared is used; keep safe fallback.
			for _, entry in pairs(entries) do
				entry.tick(dt)
			end
			return
		end
		accum += dt
		if accum < opts.interval then
			return
		end
		local step = accum
		accum = 0
		-- Snapshot owners so Destroy()->unregister mid-tick cannot skip siblings.
		local owners = table.create(16)
		for owner in pairs(entries) do
			table.insert(owners, owner)
		end
		for _, owner in ipairs(owners) do
			local entry = entries[owner]
			if entry then
				if opts.skipHidden and entry.uiInstance and not isGuiTreeVisible(entry.uiInstance) then
					continue
				end
				entry.tick(step)
			end
		end
	end)
end

--- True when callers should use SharedTick instead of their own Heartbeat.
function SharedTick.shouldUseShared(): boolean
	return readOpts().sharedEnabled
end

function SharedTick.register(owner: any, tickFn: TickFn, uiInstance: Instance?)
	entries[owner] = {
		tick = tickFn,
		uiInstance = uiInstance,
	}
	ensureConn()
end

function SharedTick.unregister(owner: any)
	entries[owner] = nil
	if next(entries) == nil and conn then
		conn:Disconnect()
		conn = nil
		accum = 0
	end
end

--- Test/hotfix: clear options cache after Config.TitleColorPreset changes in Studio.
function SharedTick.invalidateConfigCache()
	cachedOpts = nil
end

return SharedTick
