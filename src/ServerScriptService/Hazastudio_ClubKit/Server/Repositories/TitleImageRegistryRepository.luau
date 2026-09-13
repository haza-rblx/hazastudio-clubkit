--!strict
-- Place-global list of image asset ids that have been assigned as an overhead
-- image title, newest first, so an admin can re-pick one without retyping it.
--
-- One document under its own DataStore key. It is read every time the admin panel
-- opens and written only when an image is actually assigned, so reads are cached
-- and writes go through UpdateAsync.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local TitleImageDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleImageDomain)

export type TitleImageRegistryRepository = {
	list: (self: TitleImageRegistryRepository) -> any,
	remember: (self: TitleImageRegistryRepository, assetId: string) -> any,
}

local TitleImageRegistryRepository = {}

local function createRepository(deps: { logger: any? }?): TitleImageRegistryRepository
	local log = if deps and deps.logger then deps.logger else Logger.new("TitleImageRegistryRepository")
	local store = DataStoreService:GetDataStore(Config.DataStore.TITLE_IMAGE_REGISTRY_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "TitleImageRegistryRepository" })
	local documentKey = Config.DataStore.TITLE_IMAGE_REGISTRY_DOC
	local maxEntries = Config.TitleImage.REGISTRY_MAX

	-- The list changes only when an admin assigns an image, so serving a slightly
	-- stale list beats a DataStore read every time a panel opens.
	local cached: { string }? = nil
	local cachedAt = 0

	local self = {} :: TitleImageRegistryRepository

	function self:list(): any
		if cached and (os.clock() - cachedAt) < Config.DataStore.CACHE_TTL then
			return Result.Ok(cached)
		end

		local readResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(documentKey)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not readResult.ok then
			-- A registry we cannot read is an inconvenience, not a failure: the panel
			-- still lets the admin paste an id. Serve the last good list if we have one.
			log:warn("Registry read failed", { error = readResult.error })
			if cached then
				return Result.Ok(cached)
			end
			return Result.Err(readResult.error)
		end

		local list = TitleImageDomain.sanitizeList(readResult.value, maxEntries)
		cached = list
		cachedAt = os.clock()
		return Result.Ok(list)
	end

	function self:remember(assetId: string): any
		local id = TitleImageDomain.normalizeAssetId(assetId)
		if id == "" then
			return Result.Err("invalid_image")
		end

		local saved: { string }? = nil
		local writeResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(documentKey, function(current: any)
					-- Recompute from `current` so two servers assigning images at the
					-- same time cannot drop each other's entry.
					local next_ = TitleImageDomain.remember(current, id, maxEntries)
					saved = next_
					return next_
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not writeResult.ok then
			log:warn("Registry write failed", { error = writeResult.error, assetId = id })
			return Result.Err(writeResult.error)
		end

		cached = saved
		cachedAt = os.clock()
		return Result.Ok(saved or { id })
	end

	return self
end

TitleImageRegistryRepository.create = createRepository

return TitleImageRegistryRepository
