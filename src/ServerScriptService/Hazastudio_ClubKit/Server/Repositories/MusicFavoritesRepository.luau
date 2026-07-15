--!strict
-- PATH: ServerScriptService/Server/Repositories/MusicFavoritesRepository.lua
-- Persist track favorites per-player for Music Player.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger
type FavoriteTrackIds = { [string]: boolean }

local MusicFavoritesRepository = {}
MusicFavoritesRepository.__index = MusicFavoritesRepository

type MusicFavoritesRepositoryImpl = {
	_config: any,
	_logger: ILogger,
	_store: GlobalDataStore,
	_budgetGate: any,
	_dirtyPlayers: { [number]: boolean },
	_dirtyPayloads: { [number]: string },
	_loaded: { [number]: boolean },
	_key: (self: MusicFavoritesRepositoryImpl, userId: number) -> string,
	_attributeKey: (self: MusicFavoritesRepositoryImpl) -> string,
	_encode: (self: MusicFavoritesRepositoryImpl, decoded: FavoriteTrackIds) -> Result<string>,
	save: (self: MusicFavoritesRepositoryImpl, userId: number, jsonData: string) -> Result<nil>,
	onPlayerAdded: (self: MusicFavoritesRepositoryImpl, player: Player) -> (),
	onPlayerRemoving: (self: MusicFavoritesRepositoryImpl, player: Player) -> (),
	loadDecoded: (self: MusicFavoritesRepositoryImpl, player: Player) -> FavoriteTrackIds,
	addTrack: (self: MusicFavoritesRepositoryImpl, player: Player, trackId: string) -> Result<boolean>,
	removeTrack: (self: MusicFavoritesRepositoryImpl, player: Player, trackId: string) -> Result<boolean>,
	flushAll: (self: MusicFavoritesRepositoryImpl) -> number,
}

function MusicFavoritesRepository.new(deps: { config: any, logger: ILogger })
	local self = setmetatable({
		_config = deps.config,
		_logger = deps.logger,
		_store = DataStoreService:GetDataStore(deps.config.FAVORITES_DATASTORE_NAME),
		_budgetGate = BudgetGate.create({ logger = deps.logger, name = "MusicFavoritesRepository" }),
		_dirtyPlayers = {} :: { [number]: boolean },
		_dirtyPayloads = {} :: { [number]: string },
		_loaded = {} :: { [number]: boolean },
	}, MusicFavoritesRepository) :: any
	return self
end

function MusicFavoritesRepository._key(self: MusicFavoritesRepositoryImpl, userId: number): string
	return self._config.FAVORITES_KEY_PREFIX .. tostring(userId)
end

function MusicFavoritesRepository._attributeKey(self: MusicFavoritesRepositoryImpl): string
	return self._config.FAVORITES_ATTRIBUTE_KEY
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
	-- Idempotent: SharedProfileLoader may call this; MusicService.onPlayerAdded
	-- must not re-GetAsync if already loaded for this session.
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
		-- Do NOT set _loaded; addTrack/removeTrack will refuse to write so a
		-- failed load can never seed an empty snapshot that clobbers the real
		-- stored favorites on the next save.
		self._loaded[player.UserId] = nil
		return
	end

	-- Load succeeded (including the empty/new-player case). Mark loaded so
	-- writes are allowed.
	self._loaded[player.UserId] = true

	local savedData = loadResult.value
	if type(savedData) ~= "string" then
		player:SetAttribute(self:_attributeKey(), HttpService:JSONEncode({}))
		return
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(savedData)
	end)
	if decodeOk and type(decoded) == "table" then
		player:SetAttribute(self:_attributeKey(), savedData)
		return
	end

	player:SetAttribute(self:_attributeKey(), HttpService:JSONEncode({}))
end

function MusicFavoritesRepository.onPlayerRemoving(self: MusicFavoritesRepositoryImpl, player: Player)
	-- Dirty-only leave: skip UpdateAsync when nothing failed/changed since last save.
	local userId = player.UserId
	if self._dirtyPlayers[userId] and self._loaded[userId] then
		local jsonData = self._dirtyPayloads[userId]
		if type(jsonData) ~= "string" then
			local attributeData = player:GetAttribute(self:_attributeKey())
			if type(attributeData) == "string" then
				jsonData = attributeData
			end
		end
		if type(jsonData) == "string" then
			local result = self:save(userId, jsonData)
			if not result.ok then
				self._dirtyPlayers[userId] = true
				self._dirtyPayloads[userId] = jsonData
			end
		end
	end
	-- Clear the loaded flag so a later flushAll can't write a stale snapshot
	-- for a player whose load had failed.
	self._loaded[userId] = nil
end

function MusicFavoritesRepository.loadDecoded(self: MusicFavoritesRepositoryImpl, player: Player): FavoriteTrackIds
	local jsonData = player:GetAttribute(self:_attributeKey())
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
	-- Refuse writes until the player's stored favorites have loaded. Without
	-- this gate, a failed load leaves an empty attribute; addTrack would build
	-- a single-entry map and save() would clobber the player's real favorites.
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
	player:SetAttribute(self:_attributeKey(), encoded)
	self._dirtyPlayers[player.UserId] = true

	local saveResult = self:save(player.UserId, encoded)
	if not saveResult.ok then
		return Result.Err(saveResult.error)
	end

	return Result.Ok(true)
end

function MusicFavoritesRepository.removeTrack(self: MusicFavoritesRepositoryImpl, player: Player, trackId: string): Result<boolean>
	-- Refuse writes until loaded; see addTrack.
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
	player:SetAttribute(self:_attributeKey(), encoded)
	self._dirtyPlayers[player.UserId] = true

	local saveResult = self:save(player.UserId, encoded)
	if not saveResult.ok then
		return Result.Err(saveResult.error)
	end

	return Result.Ok(true)
end

function MusicFavoritesRepository.flushAll(self: MusicFavoritesRepositoryImpl): number
	local remaining = 0
	local players = game:GetService("Players")
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
			local player = players:GetPlayerByUserId(userId)
			if player then
				local attributeData = player:GetAttribute(self:_attributeKey())
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

return MusicFavoritesRepository
