--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Cache  = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

export type StickerStoredData = {
	stickers: { string },
	selectedSticker: string,
}

local log = Logger.new("StickerRepository")
local store = DataStoreService:GetDataStore(Config.Sticker.DATASTORE_NAME)
local budgetGate = BudgetGate.create({ logger = log, name = "StickerRepository" })

local StickerRepository = {}

local function normalizeImage(value: any): string
	if type(value) ~= "string" then
		return ""
	end

	local trimmed = value:match("^%s*(.-)%s*$") or ""
	local numericId = trimmed:match("^%d+$")
	if numericId and numericId ~= "0" then
		return "rbxassetid://" .. numericId
	end

	local assetId = trimmed:match("^rbxassetid://(%d+)$")
	if assetId and assetId ~= "0" then
		return "rbxassetid://" .. assetId
	end

	return ""
end

local function contains(list: { string }, image: string): boolean
	for _, existing in ipairs(list) do
		if existing == image then
			return true
		end
	end
	return false
end

local function defaultData(): StickerStoredData
	local stickers = {}
	for _, image in ipairs(Config.Sticker.DEFAULT_COLLECTION) do
		local normalized = normalizeImage(image)
		if normalized ~= "" and not contains(stickers, normalized) then
			table.insert(stickers, normalized)
		end
	end

	return {
		stickers = stickers,
		selectedSticker = "",
	}
end

local function sanitize(raw: any): StickerStoredData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end

	local stickers = {}
	if type(raw.stickers) == "table" then
		for _, image in ipairs(raw.stickers) do
			local normalized = normalizeImage(image)
			if normalized ~= "" and not contains(stickers, normalized) then
				table.insert(stickers, normalized)
				if #stickers >= Config.Sticker.MAX_COLLECTION_SIZE then
					break
				end
			end
		end
	end

	for _, image in ipairs(Config.Sticker.DEFAULT_COLLECTION) do
		local normalized = normalizeImage(image)
		if
			normalized ~= ""
			and not contains(stickers, normalized)
			and #stickers < Config.Sticker.MAX_COLLECTION_SIZE
		then
			table.insert(stickers, normalized)
		end
	end

	local selectedSticker = ""
	if type(raw.selectedSticker) == "string" then
		local rawSelected = raw.selectedSticker:match("^%s*(.-)%s*$") or ""
		selectedSticker = normalizeImage(rawSelected)
		if rawSelected ~= "" and selectedSticker == "" then
			selectedSticker = ""
		end
	else
		selectedSticker = ""
	end

	if selectedSticker ~= "" and not contains(stickers, selectedSticker) then
		selectedSticker = ""
	end

	return {
		stickers = stickers,
		selectedSticker = selectedSticker,
	}
end

local function key(userId: number): string
	return Config.Sticker.KEY_PREFIX .. tostring(userId)
end

local GLOBAL_CACHE_KEY = "GlobalPool"

local function sanitizeGlobalPool(raw: any): { stickers: { string } }
	local stickers = {}
	if type(raw) == "table" and type(raw.stickers) == "table" then
		for _, image in ipairs(raw.stickers) do
			local normalized = normalizeImage(image)
			if normalized ~= "" and not contains(stickers, normalized) then
				table.insert(stickers, normalized)
				if #stickers >= Config.Sticker.MAX_COLLECTION_SIZE then
					break
				end
			end
		end
	end

	for _, image in ipairs(Config.Sticker.DEFAULT_COLLECTION) do
		local normalized = normalizeImage(image)
		if
			normalized ~= ""
			and not contains(stickers, normalized)
			and #stickers < Config.Sticker.MAX_COLLECTION_SIZE
		then
			table.insert(stickers, normalized)
		end
	end

	return { stickers = stickers }
end

function StickerRepository.loadGlobalPool(): any
	if Cache.getNegative(GLOBAL_CACHE_KEY) then
		return Result.Ok(sanitizeGlobalPool(nil) :: { stickers: { string } })
	end

	local cached = Cache.get(GLOBAL_CACHE_KEY)
	if cached then
		return Result.Ok(cached :: { stickers: { string } })
	end

	local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return store:GetAsync(Config.Sticker.GLOBAL_POOL_KEY)
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not result.ok then
		log:warn("Sticker global pool load failed", { error = result.error })
		if result.error == "budget_exhausted" then
			Cache.setNegative(GLOBAL_CACHE_KEY, Config.Budget.NEGATIVE_CACHE_TTL or 10)
		end
		local fallback = sanitizeGlobalPool(nil)
		return Result.Ok(fallback)
	end

	local data = sanitizeGlobalPool(result.value)
	Cache.set(GLOBAL_CACHE_KEY, data, Config.DataStore.CACHE_TTL)
	return Result.Ok(data)
end

function StickerRepository.addToGlobalPool(image: string): any
	local normalized = normalizeImage(image)
	if normalized == "" then
		return Result.Err("invalid_image")
	end

	local updated: { stickers: { string } }? = nil
	local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
		return Result.withRetry(function()
			return store:UpdateAsync(Config.Sticker.GLOBAL_POOL_KEY, function(current)
				local nextPool = sanitizeGlobalPool(current)
				if not contains(nextPool.stickers, normalized) then
					if #nextPool.stickers < Config.Sticker.MAX_COLLECTION_SIZE then
						table.insert(nextPool.stickers, normalized)
					end
				end
				updated = nextPool
				return nextPool
			end)
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not result.ok then
		log:warn("Sticker global pool update failed", { error = result.error })
		return Result.Err("global_pool_save_failed")
	end

	local finalPool = updated or sanitizeGlobalPool(nil)
	Cache.set(GLOBAL_CACHE_KEY, finalPool, Config.DataStore.CACHE_TTL)
	return Result.Ok(finalPool)
end

function StickerRepository.load(userId: number): any
	local cacheKey = Config.Sticker.KEY_PREFIX .. tostring(userId)

	if Cache.getNegative(cacheKey) then
		return Result.Ok(defaultData())
	end

	local cached = Cache.get(cacheKey)
	if cached then
		return Result.Ok(cached :: StickerStoredData)
	end

	local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return store:GetAsync(key(userId))
		end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
	end)

	if not result.ok then
		log:warn("Sticker collection load failed", {
			userId = userId,
			error = result.error,
		})
		if result.error == "budget_exhausted" then
			Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
		end
		return Result.Ok(defaultData())
	end

	local data = sanitize(result.value)
	Cache.set(cacheKey, data, Config.DataStore.CACHE_TTL)
	return Result.Ok(data)
end

function StickerRepository.update(userId: number, mutator: (StickerStoredData) -> StickerStoredData): any
	local updated = nil :: StickerStoredData?
	local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
		return Result.withRetry(function()
			return store:UpdateAsync(key(userId), function(current)
				local nextData = sanitize(mutator(sanitize(current)))
				updated = nextData
				return nextData
			end)
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not result.ok then
		log:warn("Sticker collection update failed", {
			userId = userId,
			error = result.error,
		})
		return Result.Err("Failed to save sticker collection")
	end

	local finalData = updated or defaultData()
	Cache.set(Config.Sticker.KEY_PREFIX .. tostring(userId), finalData, Config.DataStore.CACHE_TTL)
	return Result.Ok(finalData)
end

function StickerRepository.sanitizeImage(value: any): string
	return normalizeImage(value)
end

return StickerRepository
