--!strict
-- Server/Services/GiveawayService.luau
--
-- Giveaway (Auto Gacha): an hourly prize draw among the players in the server. The draw runs on
-- its own (timer, or as soon as MinPlayers are in the server); admins can also spin it now or
-- reset the timer. Admins edit the settings in the Admin Spotlight "Giveaway" sheet and pay the
-- winner through Roblox's Robux Transfers API. Settings and history persist in DataStore
-- Giveaway_v1 (key "state"). That document shape is versioned (v = 1): changing it needs a new key.
--
-- Remotes (created by Server/Init/EarlyRemotes from Config.Giveaway):
--   REMOTE_STATE    snapshot of phase / countdown / settings   (server -> all)
--   REMOTE_SPIN     spin payload: pool, winner, timing          (server -> all)
--   REMOTE_HISTORY  history list                                (server -> all, and on request)
--   REMOTE_NOTICE   pay-prompt result for one history row       (server -> one admin)
--   REMOTE_ADMIN    client requests: hello, spin, resetTimer, getHistory, markPaid, pay, setConfig

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage.Hazastudio_ClubKit
local Config = require(Kit.Shared.Constants.Config)
local PermissionDomain = require(Kit.Shared.Domain.PermissionDomain)
local Logger = require(Kit.Shared.Utils.Logger)

local G = Config.Giveaway

local ANCHORS = { "TopLeft", "TopCenter", "TopRight" }
local SPIN_LEAD = 0.35
local STUDIO_MIN_POOL = 12
local HISTORY_MAX = 50
-- Transfers API: 10–500 R$ per prompt, so bigger prizes are paid in several prompts.
local TRANSFER_MIN, TRANSFER_MAX = 10, 500
local PRIZE_MAX = 10000
local WIN_FX_MAX = 15
local SAVE_DEBOUNCE = 6
local PERSISTED_KEYS = { "IntervalSeconds", "MinPlayers", "Anchor", "PrizeText", "WinFxVariant", "Enabled", "SpinDuration" }

type Settings = {
	IntervalSeconds: number,
	MinPlayers: number,
	Anchor: string,
	PrizeText: string,
	WinFxVariant: number,
	Enabled: boolean,
	SpinDuration: number,
}

type Effective = {
	interval: number,
	minPlayers: number,
	anchor: string,
	prize: string,
	winFxVariant: number,
	enabled: boolean,
	spinDuration: number,
}

local function createGiveawayService(deps: { remotes: Folder })
	local log = Logger.new("GiveawayService")
	local remotes = deps.remotes

	-- Defaults come from Config.Giveaway (ClubKitConfig.Giveaway, via ConfigBootstrap).
	local DEFAULTS: Settings = {
		IntervalSeconds = G.DEFAULT_INTERVAL_MINUTES * 60,
		MinPlayers = G.DEFAULT_MIN_PLAYERS,
		Anchor = G.DEFAULT_ANCHOR,
		PrizeText = tostring(G.DEFAULT_PRIZE_ROBUX),
		WinFxVariant = G.DEFAULT_WIN_FX_VARIANT,
		Enabled = G.DEFAULT_ENABLED,
		SpinDuration = G.DEFAULT_SPIN_DURATION,
	}
	-- Live values: start from the defaults, then the DataStore document overrides them.
	local settings: Settings = table.clone(DEFAULTS)

	local history: { { [string]: any } } = {}
	local pending: { [string]: { entryId: any, amount: number, payerId: number } } = {}
	local nextId = 1
	local persistReady = false -- false until the stored document loaded: never save over unknown data
	local saveQueued = false
	local ready = false
	local destroyed = false
	local connections: { RBXScriptConnection } = {}

	local dataStore: DataStore? = nil
	do
		local ok, ds = pcall(function()
			return DataStoreService:GetDataStore(G.STORE_NAME)
		end)
		if ok then
			dataStore = ds
		else
			log:warn("DataStore unavailable", { error = tostring(ds) })
		end
	end

	local function remoteEvent(name: string): RemoteEvent
		local ev = remotes:FindFirstChild(name)
		assert(ev and ev:IsA("RemoteEvent"), "[GiveawayService] missing remote " .. name)
		return ev :: RemoteEvent
	end
	local stateEvent = remoteEvent(G.REMOTE_STATE)
	local spinEvent = remoteEvent(G.REMOTE_SPIN)
	local adminEvent = remoteEvent(G.REMOTE_ADMIN)
	local historyEvent = remoteEvent(G.REMOTE_HISTORY)
	local noticeEvent = remoteEvent(G.REMOTE_NOTICE)

	local function readNumber(value: any, default: number): number
		if type(value) == "number" then
			return value
		end
		return default
	end

	-- Validation for AdminRequest "setConfig" and for values read back from the DataStore.
	-- Returns the cleaned value, or nil to reject.
	local VALIDATE: { [string]: (any) -> any? } = {
		Anchor = function(v)
			if type(v) == "string" and table.find(ANCHORS, v) then
				return v
			end
			return nil
		end,
		PrizeText = function(v)
			local n = tonumber(string.gsub(tostring(v), "[^%d]", ""), 10)
			if not n or n < TRANSFER_MIN or n > PRIZE_MAX then
				return nil
			end
			return tostring(math.floor(n))
		end,
		IntervalSeconds = function(v)
			local n = tonumber(v)
			if not n then
				return nil
			end
			n = math.floor(n)
			if n < 60 or n > 86400 then
				return nil
			end
			return n
		end,
		MinPlayers = function(v)
			local n = tonumber(v)
			if not n then
				return nil
			end
			n = math.floor(n)
			if n < 1 or n > 700 then
				return nil
			end
			return n
		end,
		SpinDuration = function(v)
			local n = tonumber(v)
			if not n or n < 3 or n > 10 then
				return nil
			end
			return math.floor(n * 10 + 0.5) / 10
		end,
		WinFxVariant = function(v)
			local n = tonumber(v)
			if not n then
				return nil
			end
			n = math.floor(n)
			if n < 0 or n > WIN_FX_MAX then
				return nil
			end
			return n
		end,
		Enabled = function(v)
			if type(v) == "boolean" then
				return v
			end
			return nil
		end,
	}

	local function readSettings(): Effective
		local anchor = settings.Anchor
		if not table.find(ANCHORS, anchor) then
			anchor = DEFAULTS.Anchor
		end
		local prize = settings.PrizeText
		if prize == "" then
			prize = DEFAULTS.PrizeText
		end
		return {
			interval = math.max(5, readNumber(settings.IntervalSeconds, DEFAULTS.IntervalSeconds)),
			minPlayers = math.max(1, math.floor(readNumber(settings.MinPlayers, DEFAULTS.MinPlayers))),
			anchor = anchor,
			prize = prize,
			winFxVariant = math.clamp(math.floor(readNumber(settings.WinFxVariant, DEFAULTS.WinFxVariant)), 0, WIN_FX_MAX),
			enabled = settings.Enabled == true,
			spinDuration = math.clamp(readNumber(settings.SpinDuration, DEFAULTS.SpinDuration), 3, 10),
		}
	end

	local function prizeAmount(): number
		return tonumber(settings.PrizeText) or tonumber(DEFAULTS.PrizeText) or 0
	end

	-- ============================================================
	-- Persistence
	-- ============================================================
	local function applyDocument(doc: any)
		if type(doc.history) == "table" then
			table.clear(history)
			for _, e in ipairs(doc.history) do
				table.insert(history, e)
			end
		end
		nextId = math.max(nextId, tonumber(doc.nextId) or 1)
		if type(doc.pending) == "table" then
			pending = doc.pending
		end
		if type(doc.config) == "table" then
			for _, key in ipairs(PERSISTED_KEYS) do
				local validator = VALIDATE[key]
				local value = validator and validator(doc.config[key])
				if value ~= nil then
					(settings :: any)[key] = value
				end
			end
		end
	end

	local function loadFromStore()
		if not dataStore then
			return
		end
		local ok, doc = pcall(function()
			return (dataStore :: DataStore):GetAsync(G.STORE_KEY)
		end)
		if not ok then
			log:warn("load failed; saves stay off until a load succeeds", { error = tostring(doc) })
			return
		end
		persistReady = true
		if type(doc) == "table" then
			applyDocument(doc)
			log:info("loaded giveaway history", { entries = #history })
		end
		-- Entries from before amounts existed get today's prize.
		for _, e in ipairs(history) do
			if type(e) == "table" and e.amount == nil then
				e.amount = prizeAmount()
				e.paidAmount = if e.paid then e.amount else 0
			end
		end
	end

	local function saveNow()
		if not dataStore or not persistReady then
			return
		end
		local config = {}
		for _, key in ipairs(PERSISTED_KEYS) do
			config[key] = (settings :: any)[key]
		end
		local ok, err = pcall(function()
			(dataStore :: DataStore):UpdateAsync(G.STORE_KEY, function()
				return { v = 1, nextId = nextId, history = history, pending = pending, config = config }
			end)
		end)
		if not ok then
			log:warn("save failed", { error = tostring(err) })
		end
	end

	local function save()
		if saveQueued then
			return
		end
		saveQueued = true
		task.delay(SAVE_DEBOUNCE, function()
			saveQueued = false
			saveNow()
		end)
	end

	-- ============================================================
	-- Draw state + broadcasts
	-- ============================================================
	-- phase: "counting" | "waiting" | "spinning"
	local phase = "counting"
	local nextAt = 0
	local spinEndAt = 0
	local lastSig = ""

	local function snapshot(): { [string]: any }
		local s = readSettings()
		return {
			phase = phase,
			nextAt = nextAt,
			count = #Players:GetPlayers(),
			min = s.minPlayers,
			anchor = s.anchor,
			prize = s.prize,
			enabled = s.enabled,
			interval = s.interval,
			spinDuration = s.spinDuration,
			winFxVariant = s.winFxVariant,
		}
	end

	local function broadcastState(force: boolean?)
		local snap = snapshot()
		local sig = string.format(
			"%s|%d|%d|%s|%s|%d|%s|%s|%s|%d",
			snap.phase,
			snap.count,
			snap.min,
			snap.anchor,
			snap.prize,
			math.floor(snap.nextAt),
			tostring(snap.enabled),
			tostring(snap.interval),
			tostring(snap.spinDuration),
			snap.winFxVariant
		)
		if not force and sig == lastSig then
			return
		end
		lastSig = sig
		stateEvent:FireAllClients(snap)
	end

	local function historyPayload(): { any }
		local out = {}
		for _, e in ipairs(history) do
			table.insert(out, e)
		end
		return out
	end

	local function broadcastHistory()
		historyEvent:FireAllClients(historyPayload())
	end

	local function findEntry(id: any): any
		for _, e in ipairs(history) do
			if e.id == id then
				return e
			end
		end
		return nil
	end

	-- ============================================================
	-- Draw
	-- ============================================================
	local function buildPool(host: Player): { { userId: number, displayName: string, username: string, fake: boolean } }
		local pool = {}
		local seen: { [number]: boolean } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			seen[p.UserId] = true
			table.insert(pool, { userId = p.UserId, displayName = p.DisplayName, username = p.Name, fake = false })
		end
		-- Studio only: pad to 12 with the host's friends (page 1) so the reel has enough faces.
		if RunService:IsStudio() and #pool < STUDIO_MIN_POOL then
			local ok, pages = pcall(function()
				return Players:GetFriendsAsync(host.UserId)
			end)
			if ok and pages then
				local okPage, list = pcall(function()
					return pages:GetCurrentPage()
				end)
				if okPage and type(list) == "table" then
					for _, f in ipairs(list) do
						if #pool >= STUDIO_MIN_POOL then
							break
						end
						if not seen[f.Id] then
							seen[f.Id] = true
							table.insert(pool, { userId = f.Id, displayName = f.DisplayName, username = f.Username, fake = true })
						end
					end
				end
			end
		end
		return pool
	end

	local function spin(trigger: string)
		local host = Players:GetPlayers()[1]
		if not host then
			return
		end
		local now = workspace:GetServerTimeNow()
		local s = readSettings()
		local pool = buildPool(host)
		local winnerIndex = Random.new():NextInteger(1, #pool)
		local winner = pool[winnerIndex]
		local startAt = now + SPIN_LEAD

		phase = "spinning"
		spinEndAt = startAt + s.spinDuration

		local entry = {
			id = nextId,
			ts = os.time(),
			userId = winner.userId,
			name = winner.username,
			displayName = winner.displayName,
			poolSize = #pool,
			trigger = trigger,
			amount = prizeAmount(),
			paidAmount = 0,
			paid = false,
		}
		nextId += 1
		table.insert(history, 1, entry)
		while #history > HISTORY_MAX do
			table.remove(history)
		end

		spinEvent:FireAllClients({
			pool = pool,
			winnerIndex = winnerIndex,
			startAt = startAt,
			duration = s.spinDuration,
			prize = s.prize,
			winFxVariant = s.winFxVariant,
			trigger = trigger,
		})
		log:info("spin", { trigger = trigger, pool = #pool, winner = winner.username })
		broadcastHistory()
		broadcastState(true)
		save()
	end

	local function tick()
		if not ready or destroyed then
			return
		end
		local now = workspace:GetServerTimeNow()
		if phase == "spinning" then
			if now >= spinEndAt then
				phase = "counting"
				nextAt = now + readSettings().interval
			end
		else
			local s = readSettings()
			if not s.enabled then
				-- Disabled: no automatic draws. The timer keeps rolling so re-enabling is instant.
				phase = "counting"
				if now >= nextAt then
					nextAt = now + s.interval
				end
				broadcastState(false)
				return
			end
			local count = #Players:GetPlayers()
			if phase == "counting" and now >= nextAt then
				if count >= s.minPlayers then
					spin("timer")
					return
				end
				phase = "waiting"
			end
			if phase == "waiting" and count >= s.minPlayers then
				spin("threshold")
				return
			end
		end
		broadcastState(false)
	end

	-- ============================================================
	-- Admin gate + requests
	-- ============================================================
	-- Admin = the kit's Admin Panel gate (server-set _LKG_Role + PermissionDomain). Studio = everyone.
	local function isGiveawayAdmin(player: Player): boolean
		if RunService:IsStudio() then
			return true
		end
		return PermissionDomain.canUseAdminPanel(player:GetAttribute("_LKG_Role"), player.UserId) == true
	end

	-- Robux Transfers API: the sender receipt marks the matching history row paid.
	local function onSenderReceipt(info: any): Enum.ReceiptDecision
		if not ready then
			return Enum.ReceiptDecision.NotProcessedYet
		end
		local key = tostring(info.TransferRequestId)
		local p = pending[key]
		if not p then
			return Enum.ReceiptDecision.Processed -- not ours (or already settled)
		end
		pending[key] = nil
		local e = findEntry(p.entryId)
		if e then
			e.paidAmount = (tonumber(e.paidAmount) or 0) + p.amount
			if e.paidAmount >= (tonumber(e.amount) or 0) then
				e.paid = true
				e.via = "transfer"
				e.paidBy = p.payerId
				e.paidAt = os.time()
			end
			broadcastHistory()
		end
		save()
		return Enum.ReceiptDecision.Processed
	end

	-- Pay = Roblox's own transfer prompt to the admin. One prompt per call (max 500 R$); the
	-- chip asks again for whatever is still owed.
	local paying: { [number]: boolean } = {}
	local function pay(player: Player, entryId: any)
		local e = findEntry(entryId)
		if not e or e.paid then
			return
		end
		local owed = (tonumber(e.amount) or 0) - (tonumber(e.paidAmount) or 0)
		if owed <= 0 then
			return
		end
		if e.userId == player.UserId then
			noticeEvent:FireClient(player, { id = e.id, text = "Can't pay yourself" })
			return
		end
		if paying[player.UserId] then
			return
		end
		paying[player.UserId] = true
		local amount = math.clamp(owed, TRANSFER_MIN, TRANSFER_MAX)
		local ok, result = pcall(function()
			return MarketplaceService:PromptRobuxTransferAsync(player, e.userId, amount)
		end)
		paying[player.UserId] = nil
		if ok and result ~= nil then
			pending[tostring(result)] = { entryId = e.id, amount = amount, payerId = player.UserId }
			save()
		else
			log:warn("transfer prompt failed", { error = tostring(result) })
			noticeEvent:FireClient(player, { id = e.id, text = "Transfer unavailable", fallback = true })
		end
	end

	local function onAdminRequest(player: Player, action: any, payload: any)
		if destroyed or type(action) ~= "string" then
			return
		end
		if action == "hello" then
			stateEvent:FireClient(player, snapshot())
			return
		end
		if not ready then
			return
		end
		if not isGiveawayAdmin(player) then
			log:warn("rejected admin request", { action = action, player = player.Name })
			return
		end
		if action == "getHistory" then
			historyEvent:FireClient(player, historyPayload())
			return
		elseif action == "markPaid" then
			if type(payload) ~= "table" or type(payload.id) ~= "number" or type(payload.paid) ~= "boolean" then
				return
			end
			local e = findEntry(payload.id)
			-- A Robux transfer can't be taken back, so its Paid can't be undone either.
			if e and e.via ~= "transfer" then
				e.paid = payload.paid
				e.via = if payload.paid then "manual" else nil
				e.paidBy = if payload.paid then player.UserId else nil
				e.paidAt = if payload.paid then os.time() else nil
				broadcastHistory()
				save()
			end
			return
		elseif action == "pay" then
			if type(payload) == "table" then
				task.spawn(pay, player, payload.id)
			end
			return
		elseif action == "setConfig" then
			if type(payload) ~= "table" or type(payload.key) ~= "string" then
				return
			end
			local validator = VALIDATE[payload.key]
			local value = validator and validator(payload.value)
			if value == nil then
				log:warn("setConfig rejected", { key = tostring(payload.key), value = tostring(payload.value) })
				return
			end
			;(settings :: any)[payload.key] = value
			broadcastState(true)
			save()
			return
		end
		if action == "spin" then
			if phase ~= "spinning" then
				spin("manual")
			end
		elseif action == "resetTimer" then
			if phase ~= "spinning" then
				phase = "counting"
				nextAt = workspace:GetServerTimeNow() + readSettings().interval
			end
		else
			return
		end
		broadcastState(true)
	end

	-- ============================================================
	-- Lifecycle (Server/Main registers this via trackLifecycle)
	-- ============================================================
	local service = {}

	function service:onStart()
		loadFromStore()
		ready = true
		nextAt = workspace:GetServerTimeNow() + readSettings().interval

		game:BindToClose(function()
			saveNow()
		end)

		local ok, err = pcall(function()
			MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferSender, onSenderReceipt)
		end)
		if not ok then
			log:warn("BindReceiptHandler failed", { error = tostring(err) })
		end

		local acc = 0
		table.insert(
			connections,
			RunService.Heartbeat:Connect(function(dt)
				if destroyed then
					return
				end
				acc += dt
				if acc < 1 then
					return
				end
				acc = 0
				tick()
			end)
		)
		table.insert(connections, adminEvent.OnServerEvent:Connect(onAdminRequest))
		local function refreshForPlayers()
			task.defer(function()
				if not destroyed then
					broadcastState(true)
				end
			end)
		end
		table.insert(connections, Players.PlayerAdded:Connect(refreshForPlayers))
		table.insert(connections, Players.PlayerRemoving:Connect(refreshForPlayers))

		broadcastState(true)
		broadcastHistory()
	end

	function service:onDestroy()
		destroyed = true
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
	end

	return service
end

return createGiveawayService
