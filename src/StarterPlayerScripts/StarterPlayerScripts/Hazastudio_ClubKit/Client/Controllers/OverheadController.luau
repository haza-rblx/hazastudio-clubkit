--!strict
-- PATH: StarterPlayerScripts/Client/Controllers/OverheadController.luau (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Types      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationPanelBridge = require(script.Parent.Parent.DonationPanelBridge)
local OverheadUI = require(script.Parent.Parent.UI.OverheadUI)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Logger     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local DeltaCompressor = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DeltaCompressor)
local NetworkPerfCounters = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkPerfCounters)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

type OverheadPayload = Types.OverheadPayload

local log = Logger.new("Client.OverheadController")
local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroyConnections()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	for userId, ui in pairs(_uiCache) do
		if ui and type(ui.destroy) == "function" then
			pcall(function()
				ui:destroy()
			end)
		end
		_uiCache[userId] = nil
	end
	for userId, conn in pairs(_pendingFlushConnections) do
		conn:Disconnect()
		_pendingFlushConnections[userId] = nil
	end
	for userId, conn in pairs(_headRebindConnections) do
		conn:Disconnect()
		_headRebindConnections[userId] = nil
	end
	for userId, conn in pairs(_playerCharacterConnections) do
		conn:Disconnect()
		_playerCharacterConnections[userId] = nil
	end
	table.clear(_pendingPayloads)
	table.clear(_cachedPayloadsByUserId)
	table.clear(_roleCache)
	table.clear(_membershipCache)
end

local activeVariant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
local templateName = activeVariant.templateName or Config.Template.TEMPLATE_NAME
local wrapperName = activeVariant.wrapperName or "OverheadGUIMainWrapper"

-- Module-level role cache: userId -> RoleKey
-- Populated every time an overhead payload is received.
local _roleCache: { [number]: string } = {}
local _membershipCache: { [number]: string } = {}
local roleCache = _roleCache
local membershipCache = _membershipCache
local roleChangeListeners: { (userId: number, role: string?) -> () } = {}
local overheadCacheListeners: { (userId: number?) -> () } = {}

local function notifyRoleChanged(userId: number, role: string?)
	for _, listener in ipairs(roleChangeListeners) do
		task.defer(listener, userId, role)
	end
end

local function notifyOverheadCacheUpdated(userId: number?)
	for _, listener in ipairs(overheadCacheListeners) do
		task.defer(listener, userId)
	end
end
-- v2.3: Cache last full payload per userId so that delta wire frames can be
-- merged into the cached state. Server sends only changed fields after the
-- initial full broadcast; client reconstructs the full payload before
-- forwarding to OverheadUI:apply().
local _cachedPayloadsByUserId: { [number]: any } = {}
local cachedPayloadsByUserId = _cachedPayloadsByUserId
local _uiCache: { [number]: any } = {}
local _pendingPayloads: { [number]: OverheadPayload } = {}
local _pendingFlushConnections: { [number]: RBXScriptConnection } = {}
local _headRebindConnections: { [number]: RBXScriptConnection } = {}
local _playerCharacterConnections: { [number]: RBXScriptConnection } = {}
local NIL_SENTINEL = DeltaCompressor.NIL_SENTINEL
local applyLocalPayloadPatchImpl: ((number, { [string]: any }) -> ())? = nil

local function mergeDelta(base: any, delta: any): any
	local result: any = if base then table.clone(base) else {}
	for field, value in delta do
		if value == NIL_SENTINEL then
			result[field] = nil
		else
			result[field] = value
		end
	end
	return result
end

local function getPlayerRole(userId: number): string?
	return roleCache[userId]
end

local function getPlayerEffectiveMembership(userId: number): string?
	return membershipCache[userId]
end

local function getCachedPayload(userId: number): OverheadPayload?
	local cached = cachedPayloadsByUserId[userId]
	if type(cached) ~= "table" then
		return nil
	end
	return cached :: OverheadPayload
end

local function isProjectOverheadGui(instance: Instance): boolean
	if not instance:IsA("BillboardGui") then
		return false
	end
	if instance.Name == templateName then
		return true
	end
	return instance:FindFirstChild(wrapperName, true) ~= nil
		or instance:FindFirstChild("OverheadGUIMainWrapper", true) ~= nil
end

local function waitForOverheadUpdateRemote(remotes: Instance): RemoteEvent?
	local timeout = math.max(10, tonumber(Config.Overhead.REMOTE_READY_TIMEOUT) or 45)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local existing = remotes:FindFirstChild("OverheadUpdate")
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		local child = remotes:WaitForChild("OverheadUpdate", math.min(2, remaining))
		if child and child:IsA("RemoteEvent") then
			return child
		end
	end
	return nil
end

local function init(_deps: {}?): ()
	local remotesTimeout = math.max(10, tonumber(Config.Overhead.REMOTE_READY_TIMEOUT) or 45)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes", remotesTimeout)
	if not Remotes then
		log:warn("Remotes folder not found")
		return
	end

	local RemoteOverheadUpdate = waitForOverheadUpdateRemote(Remotes)
	if not RemoteOverheadUpdate then
		log:warn("RemoteEvent OverheadUpdate not found (timeout)", {
			timeoutSeconds = remotesTimeout,
		})
		return
	end

	-- Payloads received before the BillboardGui has replicated/streamed to this client.
	local pendingPayloads = _pendingPayloads
	-- Connections that watch for the overhead GUI appearing on a character's Head.
	local pendingFlushConnections = _pendingFlushConnections
	local headRebindConnections = _headRebindConnections
	local uiCache = _uiCache
	-- Per-player CharacterAdded — Disconnect on PlayerRemoving (not module-lifetime _connections).
	local playerCharacterConnections = _playerCharacterConnections

	-- Forward declaration: `applyPayload` is defined further down in init(),
	-- but `flushPendingPayload` (a callback installed by CharacterAdded) needs
	-- to reach it. The local is hoisted in Luau, so the forward reference is
	-- valid at invocation time even though it appears textually above the
	-- definition.
	local applyPayload: (payload: any) -> ()

	local function syncOverheadGuiForUser(userId: number)
		local payload = pendingPayloads[userId] or cachedPayloadsByUserId[userId]
		if payload and applyPayload then
			applyPayload(payload)
		end
	end

	local function disconnectPendingFlush(userId: number)
		local conn = pendingFlushConnections[userId]
		if conn then
			conn:Disconnect()
			pendingFlushConnections[userId] = nil
		end
	end

	local function disconnectHeadRebind(userId: number)
		local conn = headRebindConnections[userId]
		if conn then
			conn:Disconnect()
			headRebindConnections[userId] = nil
		end
	end

	local function flushPendingPayload(userId: number)
		syncOverheadGuiForUser(userId)
	end

	local function bindToHead(userId: number, head: Instance)
		if not head:IsA("BasePart") then
			return
		end
		disconnectPendingFlush(userId)
		syncOverheadGuiForUser(userId)
		local conn = head.ChildAdded:Connect(function(child)
			if isProjectOverheadGui(child) and child:IsA("BillboardGui") then
				syncOverheadGuiForUser(userId)
			end
		end)
		pendingFlushConnections[userId] = conn
		for _, child in ipairs(head:GetChildren()) do
			if isProjectOverheadGui(child) and child:IsA("BillboardGui") then
				syncOverheadGuiForUser(userId)
				break
			end
		end
	end

	-- Watch current Head for GUI replication, and rebind when appearance settle
	-- replaces Head (large / streamed maps). Without rebind, ChildAdded stays on
	-- the destroyed Head and pending payloads never paint.
	local function bindOverheadGuiWatcher(player: Player, character: Model)
		local userId = player.UserId
		disconnectHeadRebind(userId)
		disconnectPendingFlush(userId)

		headRebindConnections[userId] = CharacterReady.onHeadAdded(character, function(head)
			if player.Character ~= character then
				return
			end
			local old = uiCache[userId]
			if old and type(old.destroy) == "function" then
				old:destroy()
			end
			uiCache[userId] = nil
			bindToHead(userId, head)
		end)

		task.spawn(function()
			local head = CharacterReady.waitStableHead(character, 10)
			if not head then
				return
			end
			if player.Character ~= character then
				return
			end
			bindToHead(userId, head)
		end)
	end

	local function watchPlayer(player: Player)
		local userId = player.UserId
		local existing = playerCharacterConnections[userId]
		if existing then
			existing:Disconnect()
			playerCharacterConnections[userId] = nil
		end
		playerCharacterConnections[userId] = player.CharacterAdded:Connect(function(character)
			-- Destroy previous OverheadUI before clearing cache so AttributeChanged connections disconnect.
			local old = uiCache[userId]
			if old and type(old.destroy) == "function" then
				old:destroy()
			end
			uiCache[userId] = nil
			-- Re-seed pending from the last known snapshot. Clearing to nil raced with
			-- recovery Broadcast (pending wiped before Head/GUI existed) and left the
			-- new BillboardGui unpainted after mid-session VIP / respawn.
			local cached = cachedPayloadsByUserId[userId]
			pendingPayloads[userId] = if type(cached) == "table" then cached else nil
			disconnectPendingFlush(userId)
			disconnectHeadRebind(userId)
			bindOverheadGuiWatcher(player, character)
		end)
		if player.Character then
			bindOverheadGuiWatcher(player, player.Character)
		end
	end

	track(Players.PlayerAdded:Connect(watchPlayer))
	track(Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		local charConn = playerCharacterConnections[userId]
		if charConn then
			charConn:Disconnect()
			playerCharacterConnections[userId] = nil
		end
		local old = uiCache[userId]
		if old and type(old.destroy) == "function" then
			old:destroy()
		end
		uiCache[userId] = nil
		roleCache[userId] = nil
		membershipCache[userId] = nil
		cachedPayloadsByUserId[userId] = nil
		pendingPayloads[userId] = nil
		disconnectPendingFlush(userId)
		disconnectHeadRebind(userId)
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	local function getUI(userId: number): typeof(OverheadUI.new(nil :: any))?
		local targetPlayer = Players:GetPlayerByUserId(userId)
		if not targetPlayer then
			log:warn("Player not found", { userId = userId })
			return nil
		end
		local character = targetPlayer.Character
		if not character then
			return nil
		end
		local head = character:FindFirstChild("Head")
		if not head then
			return nil
		end
		local gui = head:FindFirstChild(templateName)
		if not gui or not gui:IsA("BillboardGui") then
			for _, child in ipairs(head:GetChildren()) do
				if isProjectOverheadGui(child) and child:IsA("BillboardGui") then
					gui = child
					break
				end
			end
		end
		if not gui or not gui:IsA("BillboardGui") then
			log:debug("BillboardGui not found (pending queue)", { userId = userId })
			return nil
		end
		local cached = uiCache[userId]
		if cached and cached._gui == gui then
			return cached
		end
		local ui = OverheadUI.new(gui :: BillboardGui)
		uiCache[userId] = ui
		return ui
	end

	local function preserveCashDonatedWhenRankOnlyUpdate(nextPayload: any, previous: any?): any
		if type(nextPayload) ~= "table" then
			return nextPayload
		end
		local rank = tonumber(nextPayload.topSpenderRank)
		local cash = math.max(0, math.floor(tonumber(nextPayload.cashDonated) or 0))
		if not rank or cash > 0 or type(previous) ~= "table" then
			return nextPayload
		end
		local previousCash = math.max(0, math.floor(tonumber(previous.cashDonated) or 0))
		if previousCash <= 0 then
			return nextPayload
		end
		local copy = table.clone(nextPayload)
		copy.cashDonated = previousCash
		return copy
	end

	-- Keep-last OverheadUI:apply per userId per Heartbeat (Recv fan-in → 1 apply/frame).
	local pendingUiApplies: { [number]: OverheadPayload } = {}
	local uiApplyFlushConn: RBXScriptConnection? = nil

	local function flushPendingUiApplies()
		uiApplyFlushConn = nil
		local skipApply = type(Config.NetworkPerf) == "table" and Config.NetworkPerf.SKIP_OVERHEAD_UI_APPLY == true
		for userId, payload in pendingUiApplies do
			pendingUiApplies[userId] = nil
			if skipApply then
				NetworkPerfCounters.record("overhead_ui_apply_skipped")
				continue
			end
			local ui = getUI(userId)
			if not ui then
				pendingPayloads[userId] = payload
				continue
			end
			pendingPayloads[userId] = nil
			NetworkPerfCounters.record("overhead_ui_apply")
			ui:apply(payload)
		end
	end

	local function queueUiApply(userId: number, payload: OverheadPayload)
		pendingUiApplies[userId] = payload
		if uiApplyFlushConn then
			return
		end
		uiApplyFlushConn = RunService.Heartbeat:Connect(function()
			local conn = uiApplyFlushConn
			uiApplyFlushConn = nil
			if conn then
				conn:Disconnect()
			end
			flushPendingUiApplies()
		end)
	end

	local function applyPayload(payload: any)
		if type(payload) ~= "table" then
			log:warn("Payload invalid")
			return
		end
		if type(payload.userId) ~= "number" then
			log:warn("Payload.userId invalid")
			return
		end
		local userId = payload.userId
		payload = preserveCashDonatedWhenRankOnlyUpdate(payload, cachedPayloadsByUserId[userId])
		-- v2.3: keep a local snapshot so subsequent deltas can merge.
		cachedPayloadsByUserId[userId] = payload
		DonationPanelBridge.notifyLocalPayload(payload)
		-- Cache role for cross-controller lookup (canonical key)
		if type(payload.role) == "string" then
			local normalizedRole = OverheadDomain.normalizeRoleKey(payload.role) or payload.role
			local previousRole = roleCache[payload.userId]
			roleCache[payload.userId] = normalizedRole
			if normalizedRole ~= previousRole then
				notifyRoleChanged(payload.userId, normalizedRole)
			end
		end
		notifyOverheadCacheUpdated(payload.userId)
		if type(payload.effectiveMembership) == "string" then
			membershipCache[payload.userId] = payload.effectiveMembership
		end
		-- Coalesce dense apply storm; SKIP_OVERHEAD_UI_APPLY still updates caches above.
		queueUiApply(userId, payload :: OverheadPayload)
	end

	-- v2.3: apply server-sent delta on top of the cached snapshot.
	-- If no baseline exists yet (joiner race: delta arrived before the initial
	-- batch from sendAllExistingTo), drop it; the next broadcast or batch will
	-- re-seed the cache.
	local function applyDeltaPayload(message: any)
		local userId = if type(message) == "table" then message.userId else nil
		local delta = if type(message) == "table" then message.delta else nil
		if type(userId) ~= "number" or type(delta) ~= "table" then
			log:warn("Delta payload invalid", { userId = userId })
			return
		end
		local base = cachedPayloadsByUserId[userId]
		if not base then
			-- First message for this userId: server's first computeDelta returns
			-- the full state, so the delta itself IS the full payload.
			-- Treat it as full payload only if userId matches inside delta.
			if type(delta.userId) == "number" then
				applyPayload(delta)
			end
			return
		end
		local merged = mergeDelta(base, delta)
		merged.userId = userId
		merged = preserveCashDonatedWhenRankOnlyUpdate(merged, base)
		applyPayload(merged)
	end

	local function applyLocalPayloadPatch(userId: number, patch: { [string]: any })
		if type(patch) ~= "table" then
			return
		end
		local base = cachedPayloadsByUserId[userId]
		if type(base) ~= "table" then
			return
		end
		local merged = table.clone(base)
		for field, value in patch do
			merged[field] = value
		end
		merged.userId = userId
		applyPayload(merged)
	end
	applyLocalPayloadPatchImpl = applyLocalPayloadPatch

	track(RemoteOverheadUpdate.OnClientEvent:Connect(function(payload: any)
		NetworkPerfCounters.record("overhead_update_recv")
		if type(payload) == "table" and payload.kind == Config.Overhead.BATCH_MESSAGE_KIND then
			local payloads = payload.payloads
			if type(payloads) ~= "table" then
				return
			end

			for _, item in ipairs(payloads) do
				applyPayload(item)
			end
			notifyOverheadCacheUpdated(nil)
			return
		end

		-- v2.3: delta wire frame routes through merge logic; full payloads
		-- (legacy or non-delta path) keep going through applyPayload directly.
		if type(payload) == "table" and payload.kind == Config.Overhead.DELTA_MESSAGE_KIND then
			applyDeltaPayload(payload)
			return
		end

		applyPayload(payload)
	end))
end

return {
	init = init,
	getPlayerRole = getPlayerRole,
	getPlayerEffectiveMembership = getPlayerEffectiveMembership,
	getCachedPayload = getCachedPayload,
	applyLocalPayloadPatch = function(userId: number, patch: { [string]: any })
		if applyLocalPayloadPatchImpl then
			applyLocalPayloadPatchImpl(userId, patch)
		end
	end,
	subscribeRoleChanged = function(callback: (userId: number, role: string?) -> ())
		table.insert(roleChangeListeners, callback)
		return function()
			local index = table.find(roleChangeListeners, callback)
			if index then
				table.remove(roleChangeListeners, index)
			end
		end
	end,
	subscribeOverheadCacheUpdated = function(callback: (userId: number?) -> ())
		table.insert(overheadCacheListeners, callback)
		return function()
			local index = table.find(overheadCacheListeners, callback)
			if index then
				table.remove(overheadCacheListeners, index)
			end
		end
	end,
	destroy = destroyConnections,
}
