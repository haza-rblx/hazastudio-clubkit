--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)

local log = Logger.new("Server.StickerController")

local StickerController = {}
StickerController.__index = StickerController

type RateLimiter = {
	check: (self: RateLimiter, userId: number) -> (boolean, string?)
}

function StickerController.new(deps: {
	remotes: Folder,
	service: any,
	logger: any?,
	rateLimiters: {
		SET:     RateLimiter,
		CLEAR:   RateLimiter,
		ADD:     RateLimiter,
		REQUEST: RateLimiter,
	},
}): any
	local self = setmetatable({}, StickerController)
	self._remotes      = deps.remotes
	self._service      = deps.service
	self._log          = deps.logger or log
	self._rateLimiters = deps.rateLimiters
	self._connections  = {} :: { RBXScriptConnection }
	self._setRemote     = nil :: RemoteEvent?
	self._clearRemote   = nil :: RemoteEvent?
	self._addRemote     = nil :: RemoteEvent?
	self._requestRemote = nil :: RemoteEvent?
	self._syncRemote    = nil :: RemoteEvent?
	self._syncNetwork   = nil :: any
	return self
end

function StickerController:_track(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

-- Wiring semua remote handler. Dipanggil oleh serverLifecycle:startAll().
function StickerController:onStart()
	self._setRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_SET,     Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._clearRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_CLEAR,   Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._addRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_ADD,     Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._requestRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_REQUEST, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._syncRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_SYNC,    Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?

	if not self._setRemote or not self._syncRemote then
		self._log:warn("Sticker remotes not ready — StickerController disabled")
		return
	end

	-- NetworkManager batches per-Heartbeat. Sticker syncs fire on set/clear/add
	-- and on auto-clear timer; batching coalesces rapid-fire updates onto one
	-- wire flush per player.
	self._syncNetwork = NetworkManager.create({
		reliable = self._syncRemote,
		logger = self._log,
		isServer = true,
	})

	local function sync(player: Player, payload: any?)
		if self._syncNetwork then
			self._syncNetwork:fireClient(player, payload or self._service:buildSyncPayload(player))
		end
	end

	local function syncAfterAutoClear(player: Player)
		task.delay(Config.Sticker.DISPLAY_DURATION_SECONDS + 0.1, function()
			if not player.Parent then return end
			if self._service:getCurrentImage(player) == "" then
				sync(player, nil)
			end
		end)
	end

	-- ── SET ────────────────────────────────────────────────────
	self:_track(self._setRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		-- 1. Rate limit
		local allowed, reason = self._rateLimiters.SET:check(player.UserId)
		if not allowed then
			-- Throttle warning: hanya log sekali per 10 detik per player
			local warnKey = "_lastStickerRateLimitWarn"
			local lastWarn = player:GetAttribute(warnKey) or 0
			local now = os.clock()
			if now - lastWarn > 10 then
				player:SetAttribute(warnKey, now)
				self._log:debug("StickerSet rate limited", { player = player.Name, reason = reason })
			end
			return
		end
		-- 2. Payload size guard (nil / non-table juga handled di sini)
		if payload ~= nil then
			local sizeOk = Validator.checkSize(payload)
			if not sizeOk then
				self._log:warn("StickerSet payload too large", { player = player.Name })
				return
			end
		end

		-- 3. Handle clear flag
		if type(payload) == "table" and payload.clear == true then
			sync(player, self._service:clearSticker(player))
			return
		end

		-- 4. Extract image string
		local image = ""
		if type(payload) == "table" then
			image = tostring(payload.image or "")
		elseif type(payload) == "string" then
			image = payload
		end

		if image == "" then
			sync(player, self._service:clearSticker(player))
			return
		end

		local applyResult = self._service:setSticker(player, image)
		sync(player, applyResult)
		syncAfterAutoClear(player)
	end))

	-- ── CLEAR ──────────────────────────────────────────────────
	if self._clearRemote then
		self:_track(self._clearRemote.OnServerEvent:Connect(function(player: Player)
			local allowed, reason = self._rateLimiters.CLEAR:check(player.UserId)
			if not allowed then
				self._log:warn("StickerClear rate limited", { player = player.Name, reason = reason })
				return
			end
			sync(player, self._service:clearSticker(player))
		end))
	end

	-- ── ADD ────────────────────────────────────────────────────
	if self._addRemote then
		self:_track(self._addRemote.OnServerEvent:Connect(function(player: Player, payload: any)
			local allowed, reason = self._rateLimiters.ADD:check(player.UserId)
			if not allowed then
				self._log:warn("StickerAdd rate limited", { player = player.Name, reason = reason })
				return
			end
			if payload ~= nil then
				local sizeOk = Validator.checkSize(payload)
				if not sizeOk then
					self._log:warn("StickerAdd payload too large", { player = player.Name })
					return
				end
			end
			local image = if type(payload) == "table" then payload.image else payload
			self._service:addSticker(player, tostring(image or ""))
			for _, other in ipairs(Players:GetPlayers()) do
				sync(other, self._service:buildSyncPayload(other))
			end
		end))
	end

	-- ── REQUEST (sync pull) ─────────────────────────────────────
	if self._requestRemote then
		self:_track(self._requestRemote.OnServerEvent:Connect(function(player: Player)
			local allowed, reason = self._rateLimiters.REQUEST:check(player.UserId)
			if not allowed then
				self._log:warn("StickerRequest rate limited", { player = player.Name, reason = reason })
				return
			end
			sync(player, nil)
		end))
	end

	self._log:info("Sticker controller initialized")
end

-- Dipanggil oleh serverLifecycle:destroyAll().
function StickerController:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._setRemote     = nil
	self._clearRemote   = nil
	self._addRemote     = nil
	self._requestRemote = nil
	self._syncRemote    = nil
end

return StickerController
