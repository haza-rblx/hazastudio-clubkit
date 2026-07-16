--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

type Result<T> = Types.Result<T>
type FavoriteAnimations = Types.FavoriteAnimations
type ILogger = Types.ILogger
type OwnerSyncFn = (player: Player, jsonData: string) -> ()

local FavoritesRepository = {}
FavoritesRepository.__index = FavoritesRepository

type FavoritesRepositoryImpl = {
	_config: any,
	_logger: ILogger,
	_store: GlobalDataStore,
	_budgetGate: any,
	_dirtyPlayers: { [number]: boolean },
	_dirtyPayloads: { [number]: string },
	_memoryJson: { [number]: string },
	_saveScheduled: { [number]: boolean },
	_loaded: { [number]: boolean },
	_ownerSync: OwnerSyncFn?,
	_key: (self: FavoritesRepositoryImpl, userId: number) -> string,
	_setMemoryJson: (self: FavoritesRepositoryImpl, userId: number, jsonData: string) -> (),
	_notifyOwner: (self: FavoritesRepositoryImpl, player: Player) -> (),
	_scheduleDebouncedSave: (self: FavoritesRepositoryImpl, userId: number) -> (),
	onPlayerAdded: (self: FavoritesRepositoryImpl, player: Player) -> (),
	onPlayerRemoving: (self: FavoritesRepositoryImpl, player: Player) -> (),
	save: (self: FavoritesRepositoryImpl, userId: number, jsonData: string) -> Result<nil>,
	loadDecoded: (self: FavoritesRepositoryImpl, player: Player) -> FavoriteAnimations,
	storeOwnerJson: (self: FavoritesRepositoryImpl, player: Player, jsonData: string) -> Result<nil>,
	flushAll: (self: FavoritesRepositoryImpl) -> number,
	setOwnerSync: (self: FavoritesRepositoryImpl, fn: OwnerSyncFn) -> (),
}

function FavoritesRepository.new(deps: { config: any, logger: ILogger })
	local self = setmetatable({
		_config = deps.config,
		_logger = deps.logger,
		_store = DataStoreService:GetDataStore(deps.config.DATASTORE_NAME),
		_budgetGate = BudgetGate.create({ logger = deps.logger, name = "FavoritesRepository" }),
		_dirtyPlayers = {} :: { [number]: boolean },
		_dirtyPayloads = {} :: { [number]: string },
		_memoryJson = {} :: { [number]: string },
		_saveScheduled = {} :: { [number]: boolean },
		_loaded = {} :: { [number]: boolean },
		_ownerSync = nil,
	}, FavoritesRepository) :: any
	return self
end

function FavoritesRepository.setOwnerSync(self: FavoritesRepositoryImpl, fn: OwnerSyncFn)
	self._ownerSync = fn
end

function FavoritesRepository._key(self: FavoritesRepositoryImpl, userId: number): string
	return self._config.KEY_PREFIX .. tostring(userId)
end

function FavoritesRepository._setMemoryJson(self: FavoritesRepositoryImpl, userId: number, jsonData: string)
	self._memoryJson[userId] = jsonData
end

function FavoritesRepository._notifyOwner(self: FavoritesRepositoryImpl, player: Player)
	if not self._ownerSync then
		return
	end
	local jsonData = self._memoryJson[player.UserId]
	if type(jsonData) ~= "string" then
		jsonData = HttpService:JSONEncode({})
	end
	self._ownerSync(player, jsonData)
end

function FavoritesRepository._scheduleDebouncedSave(self: FavoritesRepositoryImpl, userId: number)
	if self._saveScheduled[userId] then
		return
	end
	self._saveScheduled[userId] = true
	local debounce = Config.DataStore.FAVORITES_SAVE_DEBOUNCE_SEC or 8
	task.delay(debounce, function()
		self._saveScheduled[userId] = nil
		if not self._dirtyPlayers[userId] then
			return
		end
		local jsonData = self._dirtyPayloads[userId]
		if type(jsonData) ~= "string" then
			return
		end
		self:save(userId, jsonData)
	end)
end

function FavoritesRepository.onPlayerAdded(self: FavoritesRepositoryImpl, player: Player)
	if self._loaded[player.UserId] == true then
		return
	end
	local loadResult = self._budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return self._store:GetAsync(self:_key(player.UserId))
		end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
	end)

	if not loadResult.ok then
		self._logger:warn("Favorites load failed", {
			userId = player.UserId,
			error = loadResult.error,
		})
		self._loaded[player.UserId] = nil
		return
	end

	self._loaded[player.UserId] = true

	local jsonData = HttpService:JSONEncode({})
	local savedData = loadResult.value
	if type(savedData) == "string" then
		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(savedData)
		end)
		if decodeOk and type(decoded) == "table" then
			jsonData = savedData
		end
	end

	self:_setMemoryJson(player.UserId, jsonData)
	self:_notifyOwner(player)
end

function FavoritesRepository.onPlayerRemoving(self: FavoritesRepositoryImpl, player: Player)
	local userId = player.UserId
	if self._dirtyPlayers[userId] and self._loaded[userId] then
		local jsonData = self._dirtyPayloads[userId] or self._memoryJson[userId]
		if type(jsonData) == "string" then
			local result = self:save(userId, jsonData)
			if not result.ok then
				self._dirtyPlayers[userId] = true
				self._dirtyPayloads[userId] = jsonData
			end
		end
	end
	self._loaded[userId] = nil
	self._memoryJson[userId] = nil
	self._saveScheduled[userId] = nil
end

function FavoritesRepository.save(self: FavoritesRepositoryImpl, userId: number, jsonData: string): Result<nil>
	if not self._loaded[userId] then
		return Result.Err("favorites_not_loaded")
	end
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if not decodeOk or type(decoded) ~= "table" then
		return Result.Err("Invalid favorites json")
	end

	local saveResult = self._budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
		return Result.withRetry(function()
			self._store:UpdateAsync(self:_key(userId), function(_current)
				return jsonData
			end)
			return nil
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not saveResult.ok then
		self._dirtyPlayers[userId] = true
		self._dirtyPayloads[userId] = jsonData
		self._logger:error("Favorites save failed", {
			userId = userId,
			error = saveResult.error,
		})
		return Result.Err("Failed to save favorites")
	end

	self._dirtyPlayers[userId] = nil
	self._dirtyPayloads[userId] = nil
	return Result.Ok(nil)
end

function FavoritesRepository.loadDecoded(self: FavoritesRepositoryImpl, player: Player): FavoriteAnimations
	local jsonData = self._memoryJson[player.UserId]
	if type(jsonData) ~= "string" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if ok and type(decoded) == "table" then
		return decoded :: FavoriteAnimations
	end

	return {}
end

function FavoritesRepository.storeOwnerJson(self: FavoritesRepositoryImpl, player: Player, jsonData: string): Result<nil>
	if not self._loaded[player.UserId] then
		return Result.Err("favorites_not_loaded")
	end
	self:_setMemoryJson(player.UserId, jsonData)
	self._dirtyPlayers[player.UserId] = true
	self._dirtyPayloads[player.UserId] = jsonData
	self:_notifyOwner(player)
	self:_scheduleDebouncedSave(player.UserId)
	return Result.Ok(nil)
end

function FavoritesRepository.flushAll(self: FavoritesRepositoryImpl): number
	local remaining = 0
	for userId in pairs(self._dirtyPlayers) do
		if not self._loaded[userId] then
			self._dirtyPlayers[userId] = nil
			self._dirtyPayloads[userId] = nil
			continue
		end
		local jsonData = self._dirtyPayloads[userId] or self._memoryJson[userId]
		if type(jsonData) == "string" then
			local result = self:save(userId, jsonData)
			if not result.ok then
				self._dirtyPlayers[userId] = true
				self._dirtyPayloads[userId] = jsonData
				remaining += 1
			end
		else
			self._dirtyPlayers[userId] = nil
			self._dirtyPayloads[userId] = nil
		end
	end
	return remaining
end

return FavoritesRepository
