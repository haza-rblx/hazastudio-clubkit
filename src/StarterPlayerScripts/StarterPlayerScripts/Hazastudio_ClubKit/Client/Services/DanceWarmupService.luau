--!strict

local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)
local SharedConfig = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local createDanceWarmupService = {} :: any
createDanceWarmupService.__index = createDanceWarmupService

export type WarmupTier = "tier1" | "tier2" | "full"

local function buildCacheKey(animation: Animation): string
	return animation.AnimationId ~= "" and animation.AnimationId or animation.Name
end

local function collectAnimations(animationLoader: any): { Animation }
	local collected = {}
	local seen = {}

	local function appendAll(list: { Animation })
		for _, animation in ipairs(list) do
			local key = buildCacheKey(animation)
			if not seen[key] then
				seen[key] = true
				table.insert(collected, animation)
			end
		end
	end

	appendAll(animationLoader.getAnimationsByCategory("Dance"))
	appendAll(animationLoader.getAnimationsByCategory("Pose"))

	return collected
end

local function readFavoriteNames(): { [string]: boolean }
	local favorites: { [string]: boolean } = {}
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return favorites
	end

	local attributeKey = SharedConfig.Favorites and SharedConfig.Favorites.ATTRIBUTE_KEY
	if type(attributeKey) ~= "string" then
		return favorites
	end

	local raw = localPlayer:GetAttribute(attributeKey)
	if type(raw) ~= "string" or raw == "" then
		return favorites
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and type(decoded) == "table" then
		for animationName, isFavorite in pairs(decoded) do
			if isFavorite == true and type(animationName) == "string" then
				favorites[animationName] = true
			end
		end
	end

	return favorites
end

function createDanceWarmupService.create(deps: {
	store: any,
	config: any,
	logger: any,
	animationLoader: any,
	autoStart: boolean?,
})
	local self = setmetatable({}, createDanceWarmupService) :: any
	self.store = deps.store
	self.config = deps.config.Sync
	self.logger = deps.logger
	self.assetReporter = AssetHealthReporter.new(self.logger)
	self.animationLoader = deps.animationLoader
	self.animations = collectAnimations(deps.animationLoader)
	self.catalogPreloaded = false
	self.preloadedAnimations = {} :: { [string]: boolean }
	self.readyCallbacks = {} :: { () -> () }
	self.warmGeneration = 0
	self.connections = {} :: { RBXScriptConnection }
	self.destroyed = false
	self.autoStart = deps.autoStart ~= false
	self.tier1Started = false
	self.tier2Started = false
	self.tier1Complete = false

	local localPlayer = Players.LocalPlayer
	table.insert(
		self.connections,
		localPlayer.CharacterAdded:Connect(function(character)
			if not self.autoStart then
				return
			end
			if self.tier1Complete then
				self:_setReadyState(false, true)
				return
			end
			self:_startWarmup(character, "full")
		end)
	)

	if self.autoStart then
		local currentCharacter = localPlayer.Character
		if currentCharacter then
			self:_startWarmup(currentCharacter, "full")
		else
			self.store:set({
				isDancePreparing = true,
				isDanceReady = false,
			})
		end
	else
		self.store:set({
			isDancePreparing = false,
			isDanceReady = false,
		})
	end

	return self
end

function createDanceWarmupService:_getPreloadMaxAssets(): number
	local maxAssets = math.floor(tonumber(self.config.DANCE_PRELOAD_MAX_ASSETS) or 32)
	return math.max(1, maxAssets)
end

function createDanceWarmupService:_useLegacyFlatBudget(): boolean
	return self.config.USE_LEGACY_FLAT_PRELOAD_BUDGET == true
end

function createDanceWarmupService:_getTier1Budget(): number
	local maxAssets = self:_getPreloadMaxAssets()
	if self:_useLegacyFlatBudget() then
		return maxAssets
	end
	local tier1 = math.floor(tonumber(self.config.DANCE_PRELOAD_TIER1_BUDGET) or 12)
	return math.max(1, math.min(tier1, maxAssets))
end

function createDanceWarmupService:_getTier2Budget(): number
	local maxAssets = self:_getPreloadMaxAssets()
	if self:_useLegacyFlatBudget() then
		return maxAssets
	end
	local tier1 = self:_getTier1Budget()
	local tier2 = math.floor(tonumber(self.config.DANCE_PRELOAD_TIER2_BUDGET) or 20)
	local remainingEnvelope = math.max(0, maxAssets - tier1)
	return math.max(0, math.min(tier2, remainingEnvelope))
end

function createDanceWarmupService:_collectTier1Animations(): { Animation }
	local tier1Budget = self:_getTier1Budget()
	local readyAfter = math.max(1, math.floor(tonumber(self.config.DANCE_PRELOAD_READY_AFTER)
		or tonumber(self.config.DANCE_LEGACY_PRELOAD_READY_AFTER)
		or tier1Budget))
	readyAfter = math.min(readyAfter, tier1Budget)
	local favoriteNames = readFavoriteNames()
	local selected = {} :: { Animation }
	local seen = {} :: { [string]: boolean }

	local function tryAdd(animation: Animation)
		local key = buildCacheKey(animation)
		if seen[key] or self.preloadedAnimations[key] then
			return
		end
		seen[key] = true
		table.insert(selected, animation)
	end

	for _, animation in ipairs(self.animations) do
		if favoriteNames[animation.Name] then
			tryAdd(animation)
			if #selected >= tier1Budget then
				return selected
			end
		end
	end

	for _, animation in ipairs(self.animations) do
		if #selected >= readyAfter then
			break
		end
		tryAdd(animation)
	end

	-- Fill remaining tier1 budget (readyAfter may be lower than budget).
	for _, animation in ipairs(self.animations) do
		if #selected >= tier1Budget then
			break
		end
		tryAdd(animation)
	end

	return selected
end

function createDanceWarmupService:_collectTier2Animations(): { Animation }
	local tier2 = {} :: { Animation }
	local already = 0
	for _ in pairs(self.preloadedAnimations) do
		already += 1
	end
	local maxAssets = self:_getPreloadMaxAssets()
	local envelopeLeft = math.max(0, maxAssets - already)
	local tier2Budget = self:_getTier2Budget()
	local remainingBudget = math.min(envelopeLeft, tier2Budget)
	if remainingBudget == 0 then
		return tier2
	end
	for _, animation in ipairs(self.animations) do
		local key = buildCacheKey(animation)
		if not self.preloadedAnimations[key] then
			table.insert(tier2, animation)
			if #tier2 >= remainingBudget then
				break
			end
		end
	end
	return tier2
end

function createDanceWarmupService:beginWarmup(character: Model?, tier: WarmupTier?)
	if self.destroyed then
		return
	end

	local warmupTier: WarmupTier = tier or "tier1"
	if warmupTier == "tier1" then
		if self.tier1Started then
			return
		end
		self.tier1Started = true
	elseif warmupTier == "tier2" then
		if self.tier2Started or not self.tier1Complete then
			if not self.tier1Complete then
				self:beginWarmup(character, "tier1")
			end
			if self.tier2Started then
				return
			end
		end
		self.tier2Started = true
	else
		if self.tier1Started or self.tier2Started then
			return
		end
		self.tier1Started = true
		self.tier2Started = true
		warmupTier = "full"
	end

	self.autoStart = true

	local localPlayer = Players.LocalPlayer
	local targetCharacter = character or (localPlayer and localPlayer.Character)
	if targetCharacter then
		self:_startWarmup(targetCharacter, warmupTier)
		return
	end

	self.store:set({
		isDancePreparing = true,
		isDanceReady = false,
	})
end

function createDanceWarmupService:_setReadyState(isPreparing: boolean, isReady: boolean)
	if self.destroyed then
		return
	end

	self.store:set({
		isDancePreparing = isPreparing,
		isDanceReady = isReady,
	})
end

function createDanceWarmupService:_getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

function createDanceWarmupService:_resolveAnimator(character: Model, generation: number): Animator?
	for _ = 1, 40 do
		if self.destroyed or generation ~= self.warmGeneration then
			return nil
		end

		local animator = self:_getAnimator(character)
		if animator then
			return animator
		end

		task.wait(0.1)
	end

	return nil
end

function createDanceWarmupService:_flushReadyCallbacks()
	if self.destroyed then
		self.readyCallbacks = {}
		return
	end

	local callbacks = self.readyCallbacks
	self.readyCallbacks = {}

	local currentGeneration = self.warmGeneration
	for _, callback in ipairs(callbacks) do
		if currentGeneration == self.warmGeneration then
			task.spawn(callback)
		end
	end
end

function createDanceWarmupService:_getWarmupProfile(): string
	if self.config.DANCE_PRELOAD_DEVICE_AWARE ~= true then
		return "balanced"
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local isSmallViewport = viewport.X <= 900 or viewport.Y <= 600
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	if isTouchOnly or isSmallViewport then
		return "conservative"
	end

	if #self.animations <= 80 then
		return "aggressive"
	end

	return "balanced"
end

function createDanceWarmupService:_getProfileNumber(profile: string, suffix: string, fallback: number): number
	local upperProfile = string.upper(profile)
	local key = "DANCE_PRELOAD_" .. suffix .. "_" .. upperProfile
	local value = tonumber(self.config[key])
	if value and value > 0 then
		return value
	end
	return fallback
end

function createDanceWarmupService:_waitForNetworkQueue(generation: number)
	local highWatermark = tonumber(self.config.DANCE_PRELOAD_QUEUE_HIGH_WATERMARK) or 30
	local pause = tonumber(self.config.DANCE_PRELOAD_QUEUE_PAUSE) or 0.16
	while
		not self.destroyed
		and generation == self.warmGeneration
		and ContentProvider.RequestQueueSize > highWatermark
	do
		task.wait(pause)
	end
end

function createDanceWarmupService:_preloadAnimationBatch(batch: { Animation }, generation: number): boolean
	self:_waitForNetworkQueue(generation)
	if self.destroyed or generation ~= self.warmGeneration then
		return false
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	if not ok then
		self.logger:warn("DanceWarmup preload batch failed", {
			error = tostring(err),
			batchSize = #batch,
		})
		return false
	end

	for _, animation in ipairs(batch) do
		self.preloadedAnimations[buildCacheKey(animation)] = true
	end
	return true
end

function createDanceWarmupService:_legacyStyleAssetWarmup(
	animator: Animator,
	generation: number,
	animations: { Animation },
	markReadyAfter: number
): boolean
	local yieldEvery = math.max(1, math.floor(tonumber(self.config.DANCE_LEGACY_PRELOAD_YIELD_EVERY) or 5))
	local readyAfter = math.max(1, math.floor(markReadyAfter))
	local loadedCount = 0
	local markedReady = false

	for _, sourceAnimation in ipairs(animations) do
		if self.destroyed or generation ~= self.warmGeneration then
			return markedReady
		end

		local cacheKey = buildCacheKey(sourceAnimation)
		if self.preloadedAnimations[cacheKey] then
			continue
		end

		local animationId = sourceAnimation.AnimationId
		if animationId == "" then
			continue
		end

		local ephemeral = Instance.new("Animation")
		ephemeral.AnimationId = animationId

		local ok, _track = pcall(function()
			return animator:LoadAnimation(ephemeral)
		end)

		ephemeral:Destroy()

		if ok then
			self.preloadedAnimations[cacheKey] = true
			loadedCount += 1
		else
			self.assetReporter:recordInstanceFailure(sourceAnimation, "DanceWarmupService._legacyStyleAssetWarmup", _track, {
				generation = generation,
			})
		end

		if loadedCount % yieldEvery == 0 then
			task.wait()
		end

		if not markedReady and loadedCount >= readyAfter then
			markedReady = true
			self:_setReadyState(false, true)
			self:_flushReadyCallbacks()
		end
	end

	return markedReady
end

function createDanceWarmupService:_preloadAnimationList(
	animator: Animator,
	generation: number,
	animations: { Animation },
	readyAfter: number,
	profileLabel: string
): boolean
	if #animations == 0 then
		return false
	end

	local profile = self:_getWarmupProfile()
	local useLegacyPreload = self.config.DANCE_CLIENT_LEGACY_STYLE_PRELOAD == true
	local markedReady = false
	local preloadedCount = 0

	local function maybeMarkProgressiveReady()
		if markedReady or preloadedCount < readyAfter then
			return
		end
		markedReady = true
		self:_setReadyState(false, true)
		self:_flushReadyCallbacks()
	end

	if self.config.DANCE_PRELOAD_ENABLED == false then
		return markedReady
	end

	if useLegacyPreload then
		self.logger:info("DanceWarmup legacy-style preload started", {
			profile = profileLabel,
			animationCount = #animations,
			readyAfter = readyAfter,
		})
		return self:_legacyStyleAssetWarmup(animator, generation, animations, readyAfter)
	end

	local batchSize = math.max(1, math.floor(self:_getProfileNumber(profile, "BATCH_SIZE", 6)))
	local batchDelay = math.max(0, self:_getProfileNumber(profile, "BATCH_DELAY", 0.06))

	self.logger:info("DanceWarmup ContentProvider preload started", {
		profile = profileLabel,
		deviceProfile = profile,
		animationCount = #animations,
		batchSize = batchSize,
		readyAfter = readyAfter,
	})

	for batchStart = 1, #animations, batchSize do
		if self.destroyed or generation ~= self.warmGeneration then
			return markedReady
		end
		local batch = {}
		for j = batchStart, math.min(batchStart + batchSize - 1, #animations) do
			table.insert(batch, animations[j])
		end
		if self:_preloadAnimationBatch(batch, generation) then
			preloadedCount += #batch
			maybeMarkProgressiveReady()
		end
		if batchStart + batchSize <= #animations then
			task.wait(batchDelay)
		end
	end

	return markedReady
end

function createDanceWarmupService:_startWarmup(character: Model, tier: WarmupTier)
	if self.destroyed then
		return
	end

	if tier == "tier2" and self.catalogPreloaded then
		return
	end

	if tier == "full" and self.catalogPreloaded then
		self:_setReadyState(false, true)
		self:_flushReadyCallbacks()
		return
	end

	self.warmGeneration += 1
	local generation = self.warmGeneration
	if tier == "tier1" or tier == "full" then
		self:_setReadyState(true, false)
	end

	task.spawn(function()
		if self.destroyed then
			return
		end

		local animator = self:_resolveAnimator(character, generation)
		if self.destroyed or generation ~= self.warmGeneration then
			return
		end
		if not animator then
			self.logger:warn("DanceWarmup animator not ready")
			self:_setReadyState(false, false)
			return
		end

		local readyAfter = math.max(1, math.floor(tonumber(self.config.DANCE_PRELOAD_READY_AFTER)
			or tonumber(self.config.DANCE_LEGACY_PRELOAD_READY_AFTER)
			or self:_getTier1Budget()))
		readyAfter = math.min(readyAfter, self:_getTier1Budget())
		local markedReady = false

		if tier == "tier1" or tier == "full" then
			local tier1Animations = self:_collectTier1Animations()
			markedReady = self:_preloadAnimationList(animator, generation, tier1Animations, readyAfter, "tier1")
			self.tier1Complete = true
			if not markedReady then
				self:_setReadyState(false, true)
				self:_flushReadyCallbacks()
			end
			if tier == "tier1" then
				return
			end
			-- Phase 4: full path continues into tier2 budget (not one flat dump).
			if self.destroyed or generation ~= self.warmGeneration then
				return
			end
			local tier2Animations = self:_collectTier2Animations()
			self:_preloadAnimationList(animator, generation, tier2Animations, readyAfter, "tier2")
			self.catalogPreloaded = true
			if not self.store:get().isDanceReady then
				self:_setReadyState(false, true)
				self:_flushReadyCallbacks()
			end
			return
		end

		local tier2Animations = self:_collectTier2Animations()
		self:_preloadAnimationList(animator, generation, tier2Animations, readyAfter, "tier2")
		self.catalogPreloaded = true
		if not self.store:get().isDanceReady then
			self:_setReadyState(false, true)
			self:_flushReadyCallbacks()
		end
	end)
end

function createDanceWarmupService:isReady(): boolean
	return self.store:get().isDanceReady == true
end

function createDanceWarmupService:whenReady(callback: () -> ())
	if self.destroyed then
		return
	end

	if self:isReady() then
		task.spawn(callback)
		return
	end

	table.insert(self.readyCallbacks, callback)
end

function createDanceWarmupService:clearCache()
	if self.destroyed then
		return
	end

	self.warmGeneration += 1
	self.tier1Complete = false
	self.tier1Started = false
	self.tier2Started = false
	self.catalogPreloaded = false
	self:_setReadyState(false, false)
end

function createDanceWarmupService:destroy()
	self.destroyed = true
	self.warmGeneration += 1

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	self.readyCallbacks = {}
end

return createDanceWarmupService
