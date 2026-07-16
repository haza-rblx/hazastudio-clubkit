--!strict
-- PATH: ServerScriptService/Server/Repositories/MusicFavoritesRepository.lua
-- Persist track favorites per-player for Music Player.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger
type FavoriteTrackIds = { [string]: boolean }
type OwnerSyncFn = (player: Player, jsonData: string) -> ()

local MusicFavoritesRepository = {}
MusicFavoritesRepository.__index = MusicFavoritesRepository

type MusicFavoritesRepositoryImpl = {
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
	_key: (self: MusicFavoritesRepositoryImpl, userId: number) -> string,
	_encode: (self: MusicFavoritesRepositoryImpl, decoded: FavoriteTrackIds) -> Result<string>,
	_setMemoryJson: (self: MusicFavoritesRepositoryImpl, userId: number, jsonData: string) -> (),
	_notifyOwner: (self: MusicFavoritesRepositoryImpl, player: Player) -> (),
	_scheduleDebouncedSave: (self: MusicFavoritesRepositoryImpl, userId: number) -> (),
	save: (self: MusicFavoritesRepositoryImpl, userId: number, jsonData: string) -> Result<nil>,
	onPlayerAdded: (self: MusicFavoritesRepositoryImpl, player: Player) -> (),
	onPlayerRemoving: (self: MusicFavoritesRepositoryImpl, player: Player) -> (),
	loadDecoded: (self: MusicFavoritesRepositoryImpl, player: Player) -> FavoriteTrackIds,
	addTrack: (self: MusicFavoritesRepositoryImpl, player: Player, trackId: string) -> Result<boolean>,
	removeTrack: (self: MusicFavoritesRepositoryImpl, player: Player, trackId: string) -> Result<boolean>,
	flushAll: (self: MusicFavoritesRepositoryImpl) -> number,
	setOwnerSync: (self: MusicFavoritesRepositoryImpl, fn: OwnerSyncFn) -> (),
}

function MusicFavoritesRepository.new(deps: { config: any, logger: ILogger })
	local self = setmetatable({
		_config = deps.config,
		_logger = deps.logger,
		_store = DataStoreService:GetDataStore(deps.config.FAVORITES_DATASTORE_NAME),
		_budgetGate = BudgetGate.create({ logger = deps.logger, name = "MusicFavoritesRepository" }),
		_dirtyPlayers = {} :: { [number]: boolean },
		_dirtyPayloads = {} :: { [number]: string },
		_memoryJson = {} :: { [number]: string },
		_saveScheduled = {} :: { [number]: boolean },
		_loaded = {} :: { [number]: boolean },
		_ownerSync = nil,
	}, MusicFavoritesRepository) :: any
	return self
end

function MusicFavoritesRepository.setOwnerSync(self: MusicFavoritesRepositoryImpl, fn: OwnerSyncFn)
	self._ownerSync = fn
end

function MusicFavoritesRepository._key(self: MusicFavoritesRepositoryImpl, userId: number): string
	return self._config.FAVORITES_KEY_PREFIX .. tostring(userId)
end

function MusicFavoritesRepository._encode(self: MusicFavoritesRepositoryImpl, decoded: FavoriteTrackIds): Result<string>
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode(decoded)
	end)
	if not encodeOk or type(encoded) ~= "string" then
		return Result.Err("Failed to encode music favorites")
	end
	return Result.Ok(encoded)
end

function MusicFavoritesRepository._setMemoryJson(self: MusicFavoritesRepositoryImpl, userId: number, jsonData: string)
	self._memoryJson[userId] = jsonData
end

function MusicFavoritesRepository._notifyOwner(self: MusicFavoritesRepositoryImpl, player: Player)
	if not self._ownerSync then
		return
	end
	local jsonData = self._memoryJson[player.UserId]
	if type(jsonData) ~= "string" then
		jsonData = HttpService:JSONEncode({})
	end
	self._ownerSync(player, jsonData)
end

function MusicFavoritesRepository._scheduleDebouncedSave(self: MusicFavoritesRepositoryImpl, userId: number)
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

function MusicFavoritesRepository.save(self: MusicFavoritesRepositoryImpl, userId: number, jsonData: string): Result<nil>
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if not decodeOk or type(decoded) ~= "table" then
		return Result.Err("Invalid music favorites json")
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
		self._logger:error("Music favorites save failed", {
			userId = userId,
			error = saveResult.error,
		})
		return Result.Err("Failed to save music favorites")
	end

	self._dirtyPlayers[userId] = nil
	self._dirtyPayloads[userId] = nil
	return Result.Ok(nil)
end

function MusicFavoritesRepository.onPlayerAdded(self: MusicFavoritesRepositoryImpl, player: Player)
	if self._loaded[player.UserId] == true then
		return
	end
	local loadResult = self._budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return self._store:GetAsync(self:_key(player.UserId))
		end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
	end)

	if not loadResult.ok then
		self._logger:warn("Music favorites load failed", {
			userId = player.UserId,
			error = loadResult.error,
		})
		self._loaded[player.UserId] = nil
		return
	end

	self._loaded[player.UserId] = true

	local savedData = loadResult.value
	local jsonData = HttpService:JSONEncode({})
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

function MusicFavoritesRepository.onPlayerRemoving(self: MusicFavoritesRepositoryImpl, player: Player)
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

function MusicFavoritesRepository.loadDecoded(self: MusicFavoritesRepositoryImpl, player: Player): FavoriteTrackIds
	local jsonData = self._memoryJson[player.UserId]
	if type(jsonData) ~= "string" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if ok and type(decoded) == "table" then
		local favorites = {} :: FavoriteTrackIds
		for trackId, isFavorited in pairs(decoded) do
			if type(trackId) == "string" and isFavorited == true then
				favorites[trackId] = true
			end
		end
		return favorites
	end

	return {}
end

function MusicFavoritesRepository.addTrack(self: MusicFavoritesRepositoryImpl, player: Player, trackId: string): Result<boolean>
	if not self._loaded[player.UserId] then
		return Result.Err("favorites_not_loaded")
	end
	local favorites = self:loadDecoded(player)
	if favorites[trackId] then
		return Result.Ok(false)
	end

	favorites[trackId] = true

	local encodedResult = self:_encode(favorites)
	if not encodedResult.ok then
		return Result.Err(encodedResult.error)
	end

	local encoded = encodedResult.value
	self:_setMemoryJson(player.UserId, encoded)
	self._dirtyPlayers[player.UserId] = true
	self._dirtyPayloads[player.UserId] = encoded
	self:_notifyOwner(player)
	self:_scheduleDebouncedSave(player.UserId)

	return Result.Ok(true)
end

function MusicFavoritesRepository.removeTrack(self: MusicFavoritesRepositoryImpl, player: Player, trackId: string): Result<boolean>
	if not self._loaded[player.UserId] then
		return Result.Err("favorites_not_loaded")
	end
	local favorites = self:loadDecoded(player)
	if not favorites[trackId] then
		return Result.Ok(false)
	end

	favorites[trackId] = nil

	local encodedResult = self:_encode(favorites)
	if not encodedResult.ok then
		return Result.Err(encodedResult.error)
	end

	local encoded = encodedResult.value
	self:_setMemoryJson(player.UserId, encoded)
	self._dirtyPlayers[player.UserId] = true
	self._dirtyPayloads[player.UserId] = encoded
	self:_notifyOwner(player)
	self:_scheduleDebouncedSave(player.UserId)

	return Result.Ok(true)
end

function MusicFavoritesRepository.flushAll(self: MusicFavoritesRepositoryImpl): number
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

return MusicFavoritesRepository
