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

local FavoritesRepository = {}
FavoritesRepository.__index = FavoritesRepository

type FavoritesRepositoryImpl = {
	_config: any,
	_logger: ILogger,
	_store: GlobalDataStore,
	_budgetGate: any,
	_dirtyPlayers: { [number]: boolean },
	_dirtyPayloads: { [number]: string },
	_loaded: { [number]: boolean },
	_key: (self: FavoritesRepositoryImpl, userId: number) -> string,
	onPlayerAdded: (self: FavoritesRepositoryImpl, player: Player) -> (),
	onPlayerRemoving: (self: FavoritesRepositoryImpl, player: Player) -> (),
	save: (self: FavoritesRepositoryImpl, userId: number, jsonData: string) -> Result<nil>,
	loadDecoded: (self: FavoritesRepositoryImpl, player: Player) -> FavoriteAnimations,
	flushAll: (self: FavoritesRepositoryImpl) -> number,
}

function FavoritesRepository.new(deps: { config: any, logger: ILogger })
	local self = setmetatable({
		_config = deps.config,
		_logger = deps.logger,
		_store = DataStoreService:GetDataStore(deps.config.DATASTORE_NAME),
		_budgetGate = BudgetGate.create({ logger = deps.logger, name = "FavoritesRepository" }),
		_dirtyPlayers = {} :: { [number]: boolean },
		_dirtyPayloads = {} :: { [number]: string },
		_loaded = {} :: { [number]: boolean },
	}, FavoritesRepository) :: any
	return self
end

function FavoritesRepository._key(self: FavoritesRepositoryImpl, userId: number): string
	return self._config.KEY_PREFIX .. tostring(userId)
end

function FavoritesRepository.onPlayerAdded(self: FavoritesRepositoryImpl, player: Player)
	local loadResult = self._budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return self._store:GetAsync(self:_key(player.UserId))
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not loadResult.ok then
		self._logger:warn("Favorites load failed", {
			userId = player.UserId,
			error = loadResult.error,
		})
		-- Do NOT set _loaded; save() will refuse to write so a failed load can
		-- never seed an empty snapshot that clobbers the real stored favorites.
		self._loaded[player.UserId] = nil
		return
	end

	-- Load succeeded (including the empty/new-player case).
	self._loaded[player.UserId] = true

	local savedData = loadResult.value
	if type(savedData) ~= "string" then
		return
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(savedData)
	end)
	if decodeOk and type(decoded) == "table" then
		player:SetAttribute(self._config.ATTRIBUTE_KEY, savedData)
	end
end

function FavoritesRepository.onPlayerRemoving(self: FavoritesRepositoryImpl, player: Player)
	local jsonData = player:GetAttribute(self._config.ATTRIBUTE_KEY)
	if type(jsonData) == "string" and self._loaded[player.UserId] then
		local result = self:save(player.UserId, jsonData)
		if not result.ok then
			self._dirtyPlayers[player.UserId] = true
			self._dirtyPayloads[player.UserId] = jsonData
		end
	end
	self._loaded[player.UserId] = nil
end

function FavoritesRepository.save(self: FavoritesRepositoryImpl, userId: number, jsonData: string): Result<nil>
	-- Refuse to write until the player's stored favorites have loaded. Without
	-- this gate, a failed load leaves an empty attribute; the caller would build
	-- a partial map and save() would clobber the player's real favorites.
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
	local jsonData = player:GetAttribute(self._config.ATTRIBUTE_KEY)
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

function FavoritesRepository.flushAll(self: FavoritesRepositoryImpl): number
	local remaining = 0
	for userId in pairs(self._dirtyPlayers) do
		-- Skip players that never loaded successfully; we have no trustworthy
		-- snapshot to persist and writing would risk clobbering real data.
		if not self._loaded[userId] then
			self._dirtyPlayers[userId] = nil
			self._dirtyPayloads[userId] = nil
			continue
		end
		local jsonData = self._dirtyPayloads[userId]
		if type(jsonData) ~= "string" then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				local attributeData = player:GetAttribute(self._config.ATTRIBUTE_KEY)
				if type(attributeData) == "string" then
					jsonData = attributeData
				end
			end
		end
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
