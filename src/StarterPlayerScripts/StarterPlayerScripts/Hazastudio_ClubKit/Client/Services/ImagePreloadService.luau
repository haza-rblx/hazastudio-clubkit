--!strict
-- Warms UI image assets before the panels that use them are ever opened.
--
-- WHY THIS EXISTS (measured 2026-08-25, in-playtest):
--   * a cold image costs ~0.53-0.56s between "Image assigned" and IsLoaded --
--     that half second IS the blank-then-pop players notice when a panel opens.
--   * ContentProvider:PreloadAsync({"rbxassetid://..."}) -- the STRING form --
--     is a no-op for images. It returns in ~0.1s and the asset is still cold
--     (2s later, IsLoaded == false). Measured twice on different assets.
--   * PreloadAsync({someImageLabel}) -- the INSTANCE form -- genuinely warms it:
--     subsequent display drops to ~0.05-0.06s. The instance does NOT need to be
--     parented or visible, so warming costs no render work and no residency.
--
-- Hence the single rule this service enforces: every id is wrapped in a throwaway
-- ImageLabel before it is handed to PreloadAsync. Callers may pass plain ids.
--
-- NOT assumed here: that Roblox evicts textures which are loaded but not
-- currently rendered. That claim is community lore, not documented, and could
-- not be verified (see Config.ImagePreload.KEEP_RESIDENT, default off).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("ImagePreloadService")

export type Tier = "immediate" | "firstOpen" | "background"

local TIER_ORDER: { Tier } = { "immediate", "firstOpen", "background" }

local ImagePreloadService = {}

local pending: { [Tier]: { [string]: boolean } } = {
	immediate = {},
	firstOpen = {},
	background = {},
}
-- Attempted at least once (success or not) -- prevents infinite re-queueing of
-- an asset the backend simply will not serve.
local attempted: { [string]: boolean } = {}
-- Confirmed decoded and ready.
local warm: { [string]: boolean } = {}

local started = false
local residentHolder: ScreenGui? = nil

local stats = {
	queued = 0,
	warmed = 0,
	unresolved = 0,
	batches = 0,
}

local function cfg(): any
	return Config.ImagePreload or {}
end

local function num(value: any, fallback: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n <= 0 then
		return fallback
	end
	return n
end

-- Only content strings the engine can actually fetch as an image. `rbxassetid://0`
-- is used across the kit as an explicit "no image" placeholder and must not be
-- queued, or every batch drags a guaranteed failure along.
function ImagePreloadService.isPreloadableId(id: any): boolean
	if type(id) ~= "string" or id == "" then
		return false
	end
	if id == "rbxassetid://0" then
		return false
	end
	return string.match(id, "^rbxassetid://%d+$") ~= nil
		or string.match(id, "^rbxthumb://") ~= nil
		or string.match(id, "^rbxasset://") ~= nil
end

function ImagePreloadService.isWarm(id: string): boolean
	return warm[id] == true
end

function ImagePreloadService.markWarm(id: string)
	if ImagePreloadService.isPreloadableId(id) then
		warm[id] = true
		attempted[id] = true
	end
end

function ImagePreloadService.getStats(): { [string]: number }
	return {
		queued = stats.queued,
		warmed = stats.warmed,
		unresolved = stats.unresolved,
		batches = stats.batches,
	}
end

local function enqueue(tier: Tier, id: any): boolean
	if not ImagePreloadService.isPreloadableId(id) then
		return false
	end
	local key = id :: string
	if warm[key] or attempted[key] then
		return false
	end
	local bucket = pending[tier] or pending.background
	if bucket[key] then
		return false
	end
	bucket[key] = true
	stats.queued += 1
	return true
end

-- Accepts a flat array, a map, or arbitrarily nested tables of id strings, so
-- config tables (Config.Icons.Topbar, ROLE_BADGE_IMAGE, benefit icon arrays)
-- can be registered as-is without the caller flattening them first.
function ImagePreloadService.register(tier: Tier, source: any, _depth: number?)
	local depth = _depth or 0
	if depth > 6 then
		return
	end
	if type(source) == "string" then
		enqueue(tier, source)
		return
	end
	if type(source) ~= "table" then
		return
	end
	for _, value in pairs(source) do
		if type(value) == "string" then
			enqueue(tier, value)
		elseif type(value) == "table" then
			ImagePreloadService.register(tier, value, depth + 1)
		end
	end
end

-- Walks an existing GUI subtree and queues whatever is authored on it. This is
-- how StarterGui-authored artwork gets covered: it lives outside the Rojo tree,
-- so there is no code-side manifest to register -- but the instances themselves
-- are right there in PlayerGui.
function ImagePreloadService.collectFrom(root: Instance?, tier: Tier): number
	if root == nil then
		return 0
	end
	local found = 0
	local ok = pcall(function()
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				if enqueue(tier, descendant.Image) then
					found += 1
				end
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				if enqueue(tier, descendant.Texture) then
					found += 1
				end
			end
		end
	end)
	if not ok then
		log:warn("collectFrom failed", { root = root:GetFullName() })
	end
	return found
end

local function getResidentHolder(): ScreenGui?
	if residentHolder and residentHolder.Parent then
		return residentHolder
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local holder = Instance.new("ScreenGui")
	holder.Name = "ClubKitImageResidency"
	holder.ResetOnSpawn = false
	holder.IgnoreGuiInset = true
	holder.DisplayOrder = -1000
	holder.Enabled = true
	holder.Parent = playerGui
	residentHolder = holder
	return holder
end

-- PreloadAsync yields until every asset in the batch resolves. Assets that the
-- backend never serves therefore hang it indefinitely (observed live: an id that
-- sat at IsLoaded == false for 6s with no error raised). The call is pushed onto
-- its own thread and abandoned on timeout so one bad asset can never stall the
-- whole warmup pipeline.
local function preloadWithTimeout(instances: { Instance }, timeoutSec: number): boolean
	local finished = false
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(instances)
		end)
		finished = true
		if not ok then
			log:warn("preload batch threw", { error = tostring(err), size = #instances })
		end
	end)

	local deadline = os.clock() + timeoutSec
	while not finished and os.clock() < deadline do
		task.wait(0.05)
	end
	return finished
end

local function waitForQueue()
	local highWatermark = num(cfg().QUEUE_HIGH_WATERMARK, 32)
	local pause = num(cfg().QUEUE_PAUSE_SEC, 0.16)
	local deadline = os.clock() + 10
	while ContentProvider.RequestQueueSize > highWatermark and os.clock() < deadline do
		task.wait(pause)
	end
end

local function preloadBatch(ids: { string })
	if #ids == 0 then
		return
	end
	waitForQueue()

	local keepResident = cfg().KEEP_RESIDENT == true
	local holder = if keepResident then getResidentHolder() else nil

	local probes: { Instance } = {}
	for _, id in ipairs(ids) do
		local probe = Instance.new("ImageLabel")
		probe.Name = "warm"
		probe.BackgroundTransparency = 1
		probe.Image = id
		if holder then
			-- Residency mode: stay parented and *technically* rendered, which is
			-- the community remedy for texture eviction. Unverified, hence opt-in.
			probe.Size = UDim2.fromOffset(1, 1)
			probe.ImageTransparency = 0.99
			probe.Parent = holder
		end
		table.insert(probes, probe)
	end

	stats.batches += 1
	preloadWithTimeout(probes, num(cfg().BATCH_TIMEOUT_SEC, 15))

	for index, probe in ipairs(probes) do
		local id = ids[index]
		attempted[id] = true
		local loaded = false
		pcall(function()
			loaded = (probe :: ImageLabel).IsLoaded
		end)
		if loaded then
			warm[id] = true
			stats.warmed += 1
		else
			stats.unresolved += 1
		end
		if not holder then
			probe:Destroy()
		end
	end
end

local function drainTier(tier: Tier)
	local bucket = pending[tier]
	if not bucket then
		return
	end
	local batchSize = math.floor(num(cfg().BATCH_SIZE, 12))

	local batch: { string } = {}
	for id in pairs(bucket) do
		bucket[id] = nil
		table.insert(batch, id)
		if #batch >= batchSize then
			preloadBatch(batch)
			batch = {}
		end
	end
	if #batch > 0 then
		preloadBatch(batch)
	end
end

-- Warm a set of ids right now, ahead of the tier schedule. For panels that are
-- about to open with content the registry could not know in advance.
function ImagePreloadService.warmNow(source: any)
	if cfg().ENABLED == false then
		return
	end
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	local function gather(value: any, depth: number)
		if depth > 6 then
			return
		end
		if type(value) == "string" then
			if ImagePreloadService.isPreloadableId(value) and not warm[value] and not seen[value] then
				seen[value] = true
				table.insert(ids, value)
			end
			return
		end
		if type(value) ~= "table" then
			return
		end
		for _, inner in pairs(value) do
			gather(inner, depth + 1)
		end
	end
	gather(source, 0)

	if #ids == 0 then
		return
	end
	task.spawn(function()
		preloadBatch(ids)
	end)
end

-- Runs the tiers in order on a background thread. Never yields the caller and
-- never throws: a warmup failure must not be able to hold up boot.
function ImagePreloadService.start()
	if started then
		return
	end
	started = true
	if cfg().ENABLED == false then
		log:info("image preload disabled by config")
		return
	end

	task.spawn(function()
		local tierDelay = num(cfg().TIER_DELAY_SEC, 0.25)
		local t0 = os.clock()
		for _, tier in ipairs(TIER_ORDER) do
			local ok, err = pcall(drainTier, tier)
			if not ok then
				log:warn("tier drain failed", { tier = tier, error = tostring(err) })
			end
			task.wait(tierDelay)
		end
		log:info("image preload finished", {
			elapsedSec = string.format("%.2f", os.clock() - t0),
			queued = stats.queued,
			warmed = stats.warmed,
			unresolved = stats.unresolved,
			batches = stats.batches,
		})
	end)
end

function ImagePreloadService.destroy()
	started = false
	if residentHolder then
		residentHolder:Destroy()
		residentHolder = nil
	end
	for _, tier in ipairs(TIER_ORDER) do
		pending[tier] = {}
	end
end

return ImagePreloadService
