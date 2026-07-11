--!strict
-- Server/Controllers/OverheadController.lua
-- Tanggung jawab:
--   1. Clone template BillboardGui ke Character setiap player
--   2. Kirim payload ke client via RemoteEvent
--   3. Handle refresh request dari client (rate limited)
--   4. Cleanup saat player leave
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local DeltaCompressor = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DeltaCompressor)
local OverheadPremiumBadge = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.OverheadPremiumBadge)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
type OverheadPayload = Types.OverheadPayload
-- Structural type for the optional ProximityInterestService dependency injected by
-- Main.server.luau (task 2.2). We declare only the subset of the API used here so that
-- the controller does not hard-depend on the Service module at require-time.
type ProximityInterestService = {
	getSubscribers: (self: ProximityInterestService, channelPrefix: string, subject: Player) -> { Player },
	onSubscriberAdded: (
		self: ProximityInterestService,
		listener: (event: { subject: Player, viewer: Player, channelPrefix: string }) -> ()
	) -> () -> (),
	onSubscriberRemoved: (
		self: ProximityInterestService,
		listener: (event: { subject: Player, viewer: Player, channelPrefix: string }) -> ()
	) -> () -> (),
}
local log = Logger.new("OverheadController")
local function hexToColor3(hex: string): Color3?
	local clean = hex:gsub("#", "")
	if #clean ~= 6 then
		return nil
	end
	local r = tonumber(clean:sub(1, 2), 16)
	local g = tonumber(clean:sub(3, 4), 16)
	local b = tonumber(clean:sub(5, 6), 16)
	if not r or not g or not b then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end
-- ============================================================
-- FACTORY
-- ============================================================
	local function createOverheadController(
		deps: {
			service: Types.IOverheadService,
			remotes: Folder, -- Remotes folder di-inject, bukan dibuat di top-level
			eventBus: any?,
			-- Optional: injected by Main.server.luau (task 2.2) after ProximityInterestService
			-- is constructed. When nil every broadcast is suppressed with an error log (R1.3).
			proximity: ProximityInterestService?,
			playerSnapshotService: any?,
		}
	)
		local service = deps.service
		local remotes = deps.remotes
		local eventBus = deps.eventBus
		local proximity = deps.proximity
		local playerSnapshotService = deps.playerSnapshotService
	-- Remote dibuat di dalam factory, bukan saat module di-require
	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end
	-- Server -> Client: kirim payload overhead
	local RemoteOverheadUpdate = getOrCreateRemote("OverheadUpdate")
	local RemoteAboutRosterSync = getOrCreateRemote("AboutRosterSync")
	-- NetworkManagers batch per-Heartbeat. Overhead deltas can fan out to all
	-- 70+ players multiple times per second (donation tick, streak rollover,
	-- like count); batching coalesces same-frame fires onto one wire flush.
	local overheadNetwork = NetworkManager.create({
		reliable = RemoteOverheadUpdate,
		logger = log,
		isServer = true,
	})
	local aboutRosterNetwork = NetworkManager.create({
		reliable = RemoteAboutRosterSync,
		logger = log,
		isServer = true,
	})
	-- Client -> Server: minta ulang payload roster live untuk UI yang init belakangan
	local RemoteRosterRequest = getOrCreateRemote("OverheadRosterRequest")
	-- Client -> Server: minta refresh
	local RemoteRequestRefresh = getOrCreateRemote("OverheadRequestRefresh")
	local limiter = RateLimiter.new(Config.Security.REFRESH_MAX, Config.Security.REFRESH_WINDOW)
	local rosterLimiter =
		RateLimiter.new(Config.Overhead.ROSTER_REQUEST_RATE_MAX, Config.Overhead.ROSTER_REQUEST_RATE_WINDOW)
	-- Track requestId yang sudah diproses (anti-duplicate)
	-- Gunakan TTL-based dedup seperti AdminController, bukan wipe-all
	local processedReqs: { [string]: number } = {} -- value = expiry time
	-- Track GUI yang aktif per player (untuk cleanup)
	local activeGuis: { [number]: BillboardGui } = {}
	local subscriptionSignalConnections: { [number]: RBXScriptConnection } = {}
	local cachedPayloads: { [number]: OverheadPayload } = {}
	local payloadFingerprints: { [number]: string } = {}
	-- S1 (quota-efficiency-pass-2026-06, Phase 1): hash of input cache state at last
	-- successful buildAndCachePayload. Compared with current inputs fingerprint to
	-- detect cache changes; on match, skip the expensive service:buildPayload call.
	local storedInputsFingerprints: { [number]: string } = {}
	-- Track whether the cached payload for a user was built from fallback/default
	-- data because the DataStore load failed. Fallback payloads must never be
	-- short-circuited by S1, otherwise a transient DataStore failure locks the
	-- player into the default/Guest state until cache TTL expires.
	local payloadWasFallback: { [number]: boolean } = {}
	-- Join-time DataStore reads are serialized through ProfileLoader. Do not broadcast
	-- a player's overhead until their serialized load has completed (or timed out).
	local dataReadyPlayers: { [number]: boolean } = {}
	-- True after the first successful character setup (join). Respawns skip join gates.
	local hasCompletedInitialSetup: { [number]: boolean } = {}
	local gameplayReadyPlayers: { [number]: boolean } = {}
	local gameplayReadyTimeout = math.max(
		5,
		tonumber((Config.ClientBoot :: any).GAMEPLAY_READY_SERVER_TIMEOUT) or 15
	)
	local RemoteClientGameplayReady = getOrCreateRemote(
		tostring((Config.ClientBoot :: any).CLIENT_GAMEPLAY_READY_REMOTE or "ClientGameplayReady")
	)
	RemoteClientGameplayReady.OnServerEvent:Connect(function(player: Player)
		if player and player.Parent then
			gameplayReadyPlayers[player.UserId] = true
		end
	end)
	local function waitForGameplayReady(player: Player): boolean
		if gameplayReadyPlayers[player.UserId] then
			return player.Parent ~= nil
		end
		local deadline = os.clock() + gameplayReadyTimeout
		while not gameplayReadyPlayers[player.UserId] and os.clock() < deadline and player.Parent do
			task.wait(0.25)
		end
		return player.Parent ~= nil
	end
	local aboutRosterEntryFingerprints: { [number]: string } = {}
	-- v2.3: DeltaCompressor — broadcasts only changed fields after the
	-- initial full state per player. Reduces overhead payload size by
	-- 60-80% in steady state since most updates touch 1-3 fields out of
	-- ~30 (e.g. donation tick, streak day rollover, avatar like count).
	local deltaCompressor = DeltaCompressor.create()
	-- Per-recipient delta key: "overhead:<subjectUserId>:<viewerUserId>"
	-- Each viewer has an independent compression baseline so recovery and
	-- Snapshot-on-enter for one viewer never disturb other viewers (R6.4, R1.4).
	local function deltaKey(subjectUserId: number, viewerUserId: number): string
		return ("overhead:%d:%d"):format(subjectUserId, viewerUserId)
	end
	local function appendFingerprintNumber(parts: { string }, value: number?)
		table.insert(parts, if value ~= nil then tostring(value) else "")
	end
	local function appendFingerprintString(parts: { string }, value: string?)
		table.insert(parts, value or "")
	end
	local function appendFingerprintBoolean(parts: { string }, value: boolean)
		table.insert(parts, if value then "1" else "0")
	end
	local function appendFingerprintBoolMap(parts: { string }, values: { [string]: boolean }?)
		if type(values) ~= "table" then
			table.insert(parts, "")
			return
		end
		local keys = {}
		for key in pairs(values) do
			table.insert(keys, key)
		end
		table.sort(keys)
		local buffer = {}
		for _, key in ipairs(keys) do
			table.insert(buffer, key .. "=" .. (if values[key] then "1" else "0"))
		end
		table.insert(parts, table.concat(buffer, ","))
	end
	local function appendFingerprintNumberArray(parts: { string }, values: { number }?)
		if type(values) ~= "table" then
			table.insert(parts, "")
			return
		end
		local buffer = table.create(#values)
		for index = 1, #values do
			buffer[index] = tostring(values[index] or 0)
		end
		table.insert(parts, table.concat(buffer, ","))
	end
	local function appendFingerprintColorPoints(parts: { string }, values: any)
		if type(values) ~= "table" then
			table.insert(parts, "")
			return
		end
		local buffer = {}
		for _, point in ipairs(values) do
			if type(point) == "table" then
				table.insert(
					buffer,
					string.format(
						"%.3f,%d,%d,%d",
						tonumber(point[1]) or 0,
						tonumber(point[2]) or 0,
						tonumber(point[3]) or 0,
						tonumber(point[4]) or 0
					)
				)
			end
		end
		table.insert(parts, table.concat(buffer, ";"))
	end
	local function appendFingerprintTitleStyle(parts: { string }, style: any)
		if type(style) ~= "table" then
			table.insert(parts, "")
			return
		end
		appendFingerprintString(parts, style.label)
		appendFingerprintString(parts, style.family)
		appendFingerprintString(parts, style.animMode)
		appendFingerprintNumber(parts, style.animSpeed)
		appendFingerprintNumber(parts, style.bgRotation)
		appendFingerprintNumber(parts, style.textRotation)
		appendFingerprintColorPoints(parts, style.bgColors)
		appendFingerprintColorPoints(parts, style.textColors)
		appendFingerprintNumberArray(parts, style.strokeColor)
	end

	local function sendAboutRosterTo(player: Player)
		local result = service:getAboutRosterEntries()
		if not result.ok then
			log:warn("About roster load failed", { player = player.Name, error = result.error })
			aboutRosterNetwork:fireClient(player, {})
			return
		end

		aboutRosterNetwork:fireClient(player, result.value)
	end

	local function updateAboutRosterFromPayload(player: Player, payload: OverheadPayload)
		if not service:isAboutRosterRole(payload.role) then
			return
		end

		local fingerprint = table.concat({
			tostring(payload.userId),
			payload.displayName or "",
			player.Name,
			payload.role,
		}, "|")
		if aboutRosterEntryFingerprints[payload.userId] == fingerprint then
			return
		end
		aboutRosterEntryFingerprints[payload.userId] = fingerprint

		task.spawn(function()
			local result = service:syncAboutRosterEntry(player, payload)
			if not result.ok then
				aboutRosterEntryFingerprints[payload.userId] = nil
				log:warn("About roster update failed", {
					userId = payload.userId,
					error = result.error,
				})
				return
			end

			aboutRosterNetwork:fireAllClients(result.value)
		end)
	end

	local function fingerprintPayload(payload: OverheadPayload): string
		local visibleBadges = table.clone(payload.visibleBadges or {})
		table.sort(visibleBadges)
		local parts = {}
		appendFingerprintNumber(parts, payload.userId)
		appendFingerprintString(parts, payload.displayName)
		appendFingerprintBoolean(parts, payload.hasRobloxPremium)
		appendFingerprintString(parts, payload.role)
		appendFingerprintString(parts, payload.specialTitle)
		appendFingerprintString(parts, payload.specialTitlePreset)
		appendFingerprintString(parts, payload.specialTitleSize)
		appendFingerprintString(parts, payload.specialTitleFont)
		appendFingerprintTitleStyle(parts, payload.specialTitleStyle)
		appendFingerprintString(parts, payload.specialTitlePosition)
		appendFingerprintString(parts, payload.specialRank)
		appendFingerprintBoolean(parts, payload.specialRankGradient)
		appendFingerprintString(parts, payload.statusText)
		appendFingerprintString(parts, payload.rankText)
		appendFingerprintBoolean(parts, payload.rankGradient)
		appendFingerprintString(parts, payload.effectiveMembership)
		appendFingerprintString(parts, payload.membershipLabel)
		appendFingerprintString(parts, payload.membershipRankText)
		appendFingerprintString(parts, payload.membershipChatTag)
		appendFingerprintString(parts, payload.membershipBadgeFrame)
		appendFingerprintString(parts, payload.membershipGradientName)
		appendFingerprintString(parts, payload.chatPrimaryTag)
		appendFingerprintString(parts, payload.chatCoupleTag)
		appendFingerprintNumber(parts, payload.streakDays)
		appendFingerprintNumber(parts, payload.level)
		appendFingerprintNumber(parts, payload.xp)
		appendFingerprintNumber(parts, payload.xpProgress)
		appendFingerprintString(parts, payload.levelText)
		appendFingerprintBoolean(parts, payload.isCoupled)
		appendFingerprintString(parts, payload.relationshipMode)
		appendFingerprintBoolean(parts, payload.showCoupleName)
		appendFingerprintString(parts, payload.couplePartner)
		appendFingerprintNumber(parts, payload.topDonateRank)
		appendFingerprintString(parts, payload.topDonateText)
		appendFingerprintNumber(parts, payload.topSpenderRank)
		appendFingerprintString(parts, payload.topSpenderText)
		appendFingerprintBoolean(parts, payload.isSpender)
		appendFingerprintNumber(parts, payload.communityId)
		appendFingerprintString(parts, payload.communityName)
		appendFingerprintString(parts, payload.communityLogo)
		appendFingerprintNumber(parts, payload.likesCount)
		appendFingerprintNumber(parts, payload.robuxDonated)
		appendFingerprintNumber(parts, payload.cashDonated)
		appendFingerprintBoolMap(parts, payload.publicOverheadLayerVisible)
		appendFingerprintBoolMap(parts, payload.publicOverheadBadgeVisible)
		for _, badge in ipairs(visibleBadges) do
			appendFingerprintString(parts, badge)
		end
		return table.concat(parts, "|")
	end
	-- ----------------------------------------------------------
	-- Ambil template dari ReplicatedStorage
	-- ----------------------------------------------------------
	local activeVariant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
	local templateName = activeVariant.templateName or Config.Template.TEMPLATE_NAME
	local wrapperName = activeVariant.wrapperName or "OverheadGUIMainWrapper"
	-- Coba direct child dulu (path normal). Kalau gak ketemu, fallback ke
	-- pencarian rekursif — template kadang ditaruh dalam subfolder
	-- (mis. ReplicatedStorage/Assets/...). Ambil yang BillboardGui aja.
	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then
		local nested = ReplicatedStorage:FindFirstChild(templateName, true)
		if nested and nested:IsA("BillboardGui") then
			template = nested
			log:warn("Template ketemu via pencarian rekursif (bukan direct child ReplicatedStorage)", {
				name = templateName,
				path = nested:GetFullName(),
			})
		end
	end
	if not template then
		log:error("Template BillboardGui tidak ditemukan di ReplicatedStorage!", {
			name = templateName,
		})
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

	local function cleanupCharacterOverheads(character: Model, keep: BillboardGui?)
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant ~= keep and isProjectOverheadGui(descendant) then
				descendant:Destroy()
			end
		end
	end
	-- ----------------------------------------------------------
	-- Clone GUI ke character
	-- ----------------------------------------------------------
	local function attachGui(player: Player, character: Model): BillboardGui?
		if not template then
			return nil
		end
		local head = character:WaitForChild("Head", Config.Overhead.HEAD_WAIT_TIMEOUT)
		if not head or not head:IsA("BasePart") then
			log:warn("Head tidak ditemukan", { player = player.Name })
			return nil
		end
		-- Hapus GUI lama jika ada (e.g. respawn)
		local existing = activeGuis[player.UserId]
		if existing and existing.Parent then
			existing:Destroy()
		end
		cleanupCharacterOverheads(character, nil)
		local gui = template:Clone() :: BillboardGui
		gui.Enabled = false -- sembunyikan sampai payload datang
		gui.Adornee = head :: BasePart
		gui.Parent = head
		activeGuis[player.UserId] = gui
		OverheadPremiumBadge.apply(gui, cachedPayloads[player.UserId])
		log:debug("GUI attached", { player = player.Name })
		return gui
	end
	local function ensureGuiAttached(player: Player): BillboardGui?
		local character = player.Character
		if not character then
			return nil
		end
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return nil
		end
		local existing = activeGuis[player.UserId]
		if existing and existing.Parent == head then
			existing.Adornee = head
			cleanupCharacterOverheads(character, existing)
			return existing
		end
		cleanupCharacterOverheads(character, nil)
		return attachGui(player, character)
	end
	-- ----------------------------------------------------------
	-- Build payload untuk satu player
	-- ----------------------------------------------------------
	local function buildPayload(player: Player): (OverheadPayload?, boolean)
		local meta = service:buildPayloadWithMeta(player)
		if not meta.result.ok then
			log:warn("buildPayload gagal", { player = player.Name, err = meta.result.error })
			return nil, false
		end
		return meta.result.value, meta.usedFallback
	end
	local function buildAndCachePayload(player: Player): (OverheadPayload?, boolean)
		local userId = player.UserId

		-- S1 (quota-efficiency-pass-2026-06, Phase 1): short-circuit kalau input cache
		-- state tidak berubah sejak last build. Hash disimpan di storedInputsFingerprints.
		-- Skip service:buildPayload (yang spawn 5 parallel tasks + DataStore read) kalau
		-- inputs unchanged. Kill switch: Config.Overhead.S1_SHORTCIRCUIT = false.
		-- Fallback payloads are never short-circuited so the next attempt can load real data.
		if Config.Overhead.S1_SHORTCIRCUIT ~= false and not payloadWasFallback[userId] then
			local cached = cachedPayloads[userId]
			local stored = storedInputsFingerprints[userId]
			if cached and stored ~= nil then
				local currentFingerprint = service:computeInputsFingerprint(userId)
				if currentFingerprint == stored then
					-- Cache valid, return cached tanpa rebuild
					return cached, false
				end
			end
		end

		local payload, usedFallback = buildPayload(player)
		if not payload then
			return nil, false
		end
		-- Stability fix: JANGAN downgrade payload yang sudah bagus dengan Guest
		-- fallback. Kalau load gagal (throttle/budget) dan kita sudah punya cached
		-- payload non-fallback, return yang lama. Hanya pakai fallback kalau belum
		-- ada cache sama sekali (first load). Ini cegah "Guest flicker" di chat tags
		-- saat refreshAll hit transient DataStore failure.
		if usedFallback and cachedPayloads[userId] and not payloadWasFallback[userId] then
			return cachedPayloads[userId], false
		end
		local fingerprint = fingerprintPayload(payload)
		local changed = payloadFingerprints[userId] ~= fingerprint
		cachedPayloads[userId] = payload
		payloadFingerprints[userId] = fingerprint
		payloadWasFallback[userId] = usedFallback
		-- S1: only store inputs fingerprint when we loaded real stored data. If we fell
		-- back to default data, leave the fingerprint nil so the next build retries.
		if not usedFallback then
			storedInputsFingerprints[userId] = service:computeInputsFingerprint(userId)
		else
			storedInputsFingerprints[userId] = nil
		end
		updateAboutRosterFromPayload(player, payload)
		-- Selalu return payload build terbaru (bukan referensi cache lama) supaya
		-- syncBuiltinPlayerList dapat cash/robux terbaru untuk leaderstats.
		return payload, changed
	end
	local function getOrCreateLeaderstats(player: Player): Folder
		local existing = player:FindFirstChild("leaderstats")
		if existing and existing:IsA("Folder") then
			return existing
		end
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
		return leaderstats
	end
	local function getOrCreateRankStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.RANK_STAT_NAME or "Rank"
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local rankValue = Instance.new("IntValue")
		rankValue.Name = statName
		rankValue.Parent = leaderstats
		return rankValue
	end
	local function getOrCreateStreakStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.STREAK_STAT_NAME
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local streakValue = Instance.new("IntValue")
		streakValue.Name = statName
		streakValue.Parent = leaderstats
		return streakValue
	end
	local function getOrCreateLevelStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.LEVEL_STAT_NAME or "Level"
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local levelValue = Instance.new("IntValue")
		levelValue.Name = statName
		levelValue.Parent = leaderstats
		return levelValue
	end
	local function getOrCreateLikesStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.LIKES_STAT_NAME
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local likesValue = Instance.new("IntValue")
		likesValue.Name = statName
		likesValue.Parent = leaderstats
		return likesValue
	end
	local function getOrCreateRobuxStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.ROBUX_STAT_NAME
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local robuxValue = Instance.new("IntValue")
		robuxValue.Name = statName
		robuxValue.Parent = leaderstats
		return robuxValue
	end
	local function getOrCreateCashStat(player: Player): IntValue
		local leaderstats = getOrCreateLeaderstats(player)
		local statName = Config.PlayerList.CASH_STAT_NAME
		local existing = leaderstats:FindFirstChild(statName)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local cashValue = Instance.new("IntValue")
		cashValue.Name = statName
		cashValue.Parent = leaderstats
		return cashValue
	end
	local function normalizeColorKey(key: string?): string?
		if type(key) ~= "string" or key == "" then
			return nil
		end
		local aliases = Config.Membership and Config.Membership.ALIASES
		local alias = if type(aliases) == "table" then aliases[key] or aliases[string.lower(key)] else nil
		return if type(alias) == "string" then alias else key
	end
	local function spenderWithinMaxRank(spenderType: string, rank: number?): boolean
		if rank == nil then
			return false
		end
		local spenderRoles = Config.SpenderRoles
		if type(spenderRoles) ~= "table" then
			return rank >= 1
		end
		local spenderConfig = spenderRoles[spenderType]
		if type(spenderConfig) ~= "table" or spenderConfig.Enabled == false then
			return false
		end
		local maxRank = tonumber(spenderConfig.MaxRank) or 1
		return rank >= 1 and rank <= maxRank
	end
	local function resolvePrimaryColorKey(payload: OverheadPayload): string
		local rawRole = payload.role or "Guest"
		local rawMembership = payload.effectiveMembership or "Guest"
		local roleKey = normalizeColorKey(rawRole) or rawRole
		local membershipKey = normalizeColorKey(rawMembership) or rawMembership
		local rolePriority = Config.ChatPrimaryTagPriority[rawRole] or Config.ChatPrimaryTagPriority[roleKey] or 0
		local membershipPriority = Config.ChatPrimaryTagPriority[rawMembership]
			or Config.ChatPrimaryTagPriority[membershipKey]
			or 0
		local primaryKey = if rolePriority >= membershipPriority then roleKey else membershipKey
		local cashKey = "TopSpender"
		local robuxKey = "RoyaleSpender"
		local spenderRoles = Config.SpenderRoles
		if type(spenderRoles) == "table" then
			local cash = spenderRoles.CashSpender
			if type(cash) == "table" and type(cash.Key) == "string" then
				cashKey = cash.Key
			end
			local robux = spenderRoles.RobuxSpender
			if type(robux) == "table" and type(robux.Key) == "string" then
				robuxKey = robux.Key
			end
		end
		if spenderWithinMaxRank("CashSpender", payload.topSpenderRank) then
			local topSpenderPriority = Config.ChatPrimaryTagPriority[cashKey]
				or Config.ChatPrimaryTagPriority.TopSpender
				or Config.ChatPrimaryTagPriority.Spender
				or 0
			if topSpenderPriority > (Config.ChatPrimaryTagPriority[primaryKey] or 0) then
				primaryKey = cashKey
			end
		end
		if spenderWithinMaxRank("RobuxSpender", payload.topDonateRank) then
			local royalePriority = Config.ChatPrimaryTagPriority[robuxKey]
				or Config.ChatPrimaryTagPriority.RoyaleSpender
				or Config.ChatPrimaryTagPriority.Spender
				or 0
			if royalePriority > (Config.ChatPrimaryTagPriority[primaryKey] or 0) then
				primaryKey = robuxKey
			end
		end
		return primaryKey
	end
	local function resolvePlayerListRankScore(payload: OverheadPayload): number
		local primaryKey = resolvePrimaryColorKey(payload)
		local score = Config.ChatPrimaryTagPriority[primaryKey] or 0
		local robuxRank = if spenderWithinMaxRank("RobuxSpender", tonumber(payload.topDonateRank))
			then tonumber(payload.topDonateRank)
			else nil
		local saweriaRank = if spenderWithinMaxRank("CashSpender", tonumber(payload.topSpenderRank))
			then tonumber(payload.topSpenderRank)
			else nil
		local robuxPriority = Config.ChatPrimaryTagPriority.RoyaleSpender or 40
		local cashPriority = Config.ChatPrimaryTagPriority.TopSpender or 40
		if type(Config.SpenderRoles) == "table" then
			local robux = Config.SpenderRoles.RobuxSpender
			if type(robux) == "table" and type(robux.Priority) == "number" then
				robuxPriority = robux.Priority
			end
			local cash = Config.SpenderRoles.CashSpender
			if type(cash) == "table" and type(cash.Priority) == "number" then
				cashPriority = cash.Priority
			end
		end
		if robuxRank then
			score = math.max(score, robuxPriority - math.min(robuxRank, Config.Leaderboards.ROBUX_LIMIT))
		end
		if saweriaRank then
			score = math.max(score, cashPriority - math.min(saweriaRank, Config.Leaderboards.SAWERIA_LIMIT))
		end
		return math.max(0, math.floor(score))
	end
	local function resolveRoleKeyFromTag(tagName: string): string?
		if tagName == "" then
			return nil
		end
		local canonical = RolesDomain.normalizeRoleKey(tagName) or OverheadDomain.normalizeRoleKey(tagName)
		if canonical then
			return canonical
		end
		-- Strip suffix " #N" untuk Spender rank ("ROYALE SPENDER #1" → "ROYALE SPENDER").
		local lookupTagName = tagName:gsub(" #%d+$", "")
		local upperLookup = string.upper(lookupTagName)
		if Config.ChatPrimaryTagLabel[lookupTagName] then
			return lookupTagName
		end
		for roleKey, label in pairs(Config.ChatPrimaryTagLabel) do
			if type(label) == "string" and (label == lookupTagName or string.upper(label) == upperLookup) then
				return roleKey
			end
		end
		return nil
	end
	local function getTeamVisibleLabel(roleKey: string): string
		local label = Config.ChatPrimaryTagLabel[roleKey]
		if type(label) == "string" and label ~= "" then
			return string.upper(label)
		end
		local definition = RolesDomain.getDefinition(roleKey)
		if definition then
			return string.upper(definition.label)
		end
		return string.upper(roleKey)
	end
	local function getTeamDisplayName(roleKey: string): string
		local canonical = resolveRoleKeyFromTag(roleKey) or roleKey
		return getTeamVisibleLabel(canonical)
	end
	local function isLegacyTeamName(name: string): boolean
		if name:match("^%d%d%s") or name:match("^%d%d %d%d%s") then
			return true
		end
		local firstCodepoint = utf8.codepoint(name, 1, 1)
		if firstCodepoint and firstCodepoint >= 0xE000 and firstCodepoint <= 0xF8FF then
			return true
		end
		return false
	end
	local function resolvePlayerTeamRoleKey(payload: OverheadPayload): string
		-- Gunakan max priority antara group role DAN effectiveMembership.
		-- VIP/VVIP/Exclusive diberikan via grantMembership → stored.membershipBadge → effectiveMembership.
		-- payload.role saja tidak cukup — player dengan group rank Guest yang beli VIP
		-- tetap punya role="Guest" di payload, tapi effectiveMembership="Tier1" (VIP).
		-- Fix: ambil baseRole dari whichever has higher ChatPrimaryTagPriority.
		local groupRole = OverheadDomain.normalizeRoleKey(payload.role) or payload.role
		local membershipRole = payload.effectiveMembership
			and OverheadDomain.normalizeRoleKey(payload.effectiveMembership)
			or nil
		local groupPriority = Config.ChatPrimaryTagPriority[groupRole] or 0
		local membershipPriority = if membershipRole
			then (Config.ChatPrimaryTagPriority[membershipRole] or 0)
			else 0
		local baseRole = if membershipPriority > groupPriority then membershipRole :: string else groupRole
		local chatRole = RolesDomain.resolveDynamicChatRole(
			baseRole,
			payload.topSpenderRank,
			payload.topDonateRank,
			Config.ChatPrimaryTagPriority
		) :: string
		return OverheadDomain.normalizeRoleKey(chatRole) or chatRole
	end
	local function purgeLegacyPlayerListTeams()
		for _, child in ipairs(Teams:GetChildren()) do
			if child:IsA("Team") and isLegacyTeamName(child.Name) then
				child:Destroy()
			end
		end
	end
	-- Roblox treats TeamColor as the unique team ID. Duplicate BrickColors cause
	-- players to snap onto the wrong Team in the PlayerList. Prefer config color,
	-- then claim the next free BrickColor from a stable palette.
	local UNIQUE_TEAM_COLOR_PALETTE: { string } = {
		"Gold",
		"Bright orange",
		"Dark orange",
		"Bright red",
		"Really red",
		"Hot pink",
		"Magenta",
		"Bright violet",
		"Royal purple",
		"Bright blue",
		"Deep blue",
		"Cyan",
		"Teal",
		"Bright bluish green",
		"Bright green",
		"Lime green",
		"New Yeller",
		"Bright yellow",
		"Light orange",
		"CGA brown",
		"Brown",
		"Reddish brown",
		"Nougat",
		"White",
		"Light stone grey",
		"Medium stone grey",
		"Dark stone grey",
		"Black",
		"Institutional white",
		"Pastel Blue",
		"Pastel green",
		"Pastel yellow",
		"Pastel orange",
		"Pastel violet",
		"Pink",
		"Rose",
		"Alder",
		"Lavender",
		"Sand blue",
		"Sand green",
		"Earth green",
		"Camo",
		"Olive",
		"Sea green",
		"Storm blue",
		"Steel blue",
		"Lapis",
		"Electric blue",
		"Toothpaste",
		"Mint",
		"Moss",
		"Shamrock",
		"Forest green",
		"Grime",
		"Cork",
		"Burlap",
		"Brick yellow",
		"Cool yellow",
		"Neon orange",
		"Persimmon",
		"Crimson",
		"Maroon",
		"Burgundy",
	}
	local function brickColorName(color: BrickColor): string
		return color.Name
	end
	local function isTeamColorTaken(color: BrickColor, exceptTeam: Team?): boolean
		local name = brickColorName(color)
		for _, child in ipairs(Teams:GetChildren()) do
			if child:IsA("Team") and child ~= exceptTeam then
				if brickColorName(child.TeamColor) == name then
					return true
				end
			end
		end
		return false
	end
	local function claimUniqueTeamColor(preferred: BrickColor?, team: Team): BrickColor
		if preferred and not isTeamColorTaken(preferred, team) then
			return preferred
		end
		for _, colorName in ipairs(UNIQUE_TEAM_COLOR_PALETTE) do
			local candidate = BrickColor.new(colorName)
			if not isTeamColorTaken(candidate, team) then
				if preferred and brickColorName(preferred) ~= brickColorName(candidate) then
					log:debug("TeamColor remapped to keep PlayerList teams unique", {
						team = team.Name,
						preferred = brickColorName(preferred),
						assigned = brickColorName(candidate),
					})
				end
				return candidate
			end
		end
		-- Exhausted palette: keep preferred or fall back to Medium stone grey.
		return preferred or BrickColor.new("Medium stone grey")
	end
	local function applyTeamColor(team: Team, colorKey: string, fallbackRoleKey: string)
		local resolvedColorKey = normalizeColorKey(colorKey) or colorKey
		local colorName = Config.PlayerList.TEAM_COLORS[resolvedColorKey]
			or Config.PlayerList.TEAM_COLORS[fallbackRoleKey]
		local chatHex = Config.ChatPrimaryTagColor[resolvedColorKey] or Config.ChatPrimaryTagColor[fallbackRoleKey]
		local preferred: BrickColor? = nil
		if colorName then
			preferred = BrickColor.new(colorName)
		elseif chatHex then
			local color = hexToColor3(chatHex)
			if color then
				preferred = BrickColor.new(color)
			else
				log:warn("hexToColor3 gagal parse warna untuk tag, team akan pakai warna default", {
					tagName = fallbackRoleKey,
					hex = tostring(chatHex),
				})
			end
		end
		team.TeamColor = claimUniqueTeamColor(preferred, team)
	end
	local function getOrCreateTeam(tagName: string, colorKey: string?): Team?
		local roleKey = resolveRoleKeyFromTag(tagName) or OverheadDomain.normalizeRoleKey(tagName)
		if not roleKey then
			return nil
		end
		local resolvedColorKey = normalizeColorKey(colorKey) or normalizeColorKey(roleKey) or roleKey
		local teamName = getTeamDisplayName(roleKey)
		local existing = Teams:FindFirstChild(teamName)
		if existing and existing:IsA("Team") then
			applyTeamColor(existing, resolvedColorKey, roleKey)
			return existing
		end
		local team = Instance.new("Team")
		team.Name = teamName
		team.AutoAssignable = false
		applyTeamColor(team, resolvedColorKey, roleKey)
		team.Parent = Teams
		return team
	end
	local function ensurePremadeRoleTeams()
		purgeLegacyPlayerListTeams()
		local seenDisplayNames: { [string]: boolean } = {}
		local roleKeys: { string } = {}
		for roleKey in pairs(Config.ChatPrimaryTagLabel) do
			table.insert(roleKeys, roleKey)
		end
		table.sort(roleKeys, function(a: string, b: string)
			return (Config.ChatPrimaryTagPriority[a] or 0) > (Config.ChatPrimaryTagPriority[b] or 0)
		end)
		local created = 0
		for _, roleKey in ipairs(roleKeys) do
			local displayName = getTeamDisplayName(roleKey)
			if not seenDisplayNames[displayName] then
				seenDisplayNames[displayName] = true
				local team = getOrCreateTeam(roleKey, roleKey)
				if team then
					team.Parent = Teams
					created += 1
				end
			end
		end
		log:info("Premade PlayerList role teams", { count = created })
	end
	local function syncBuiltinPlayerList(player: Player, payload: OverheadPayload)
		-- Guard: player mungkin sudah leave saat deferred/delayed broadcast
		if not player.Parent then
			return
		end
		-- Rank dibuat sebagai leaderstat pertama supaya PlayerList Roblox sort dari role/rank tertinggi.
		local rankValue = getOrCreateRankStat(player)
		rankValue.Value = resolvePlayerListRankScore(payload)
		-- Streak
		local streakValue = getOrCreateStreakStat(player)
		streakValue.Value = payload.streakDays
		if Config.FeatureFlags.LevelSystemEnabled and payload.level ~= nil then
			local levelValue = getOrCreateLevelStat(player)
			levelValue.Value = payload.level
		end
		-- Likes
		local likesValue = getOrCreateLikesStat(player)
		likesValue.Value = payload.likesCount
		-- Robux
		local robuxValue = getOrCreateRobuxStat(player)
		robuxValue.Value = payload.robuxDonated
		-- Cash
		local cashValue = getOrCreateCashStat(player)
		cashValue.Value = payload.cashDonated
		-- Team = chatRole (sama judul overhead), bukan chatPrimaryTag membership (Exclusive/VIP).
		local teamRoleKey = resolvePlayerTeamRoleKey(payload)
		local team = getOrCreateTeam(teamRoleKey, teamRoleKey)
		if team and player.Parent then
			player.Neutral = false
			player.Team = team
		elseif player.Parent then
			-- Fallback: use LKG role to prevent player staying Neutral
			local lkgRole = player:GetAttribute("_LKG_Role")
			if type(lkgRole) == "string" and lkgRole ~= "" and lkgRole ~= "Guest" then
				local fallbackTeam = getOrCreateTeam(lkgRole, lkgRole)
				if fallbackTeam then
					player.Neutral = false
					player.Team = fallbackTeam
				end
			end
		end
	end
	-- ----------------------------------------------------------
	-- Broadcast payload satu player ke semua player di server
	-- Dipanggil saat player join atau datanya berubah
	-- ----------------------------------------------------------
	--
	-- mode:
	--   "delta"    (default) — send only changed fields to each subscriber; never
	--              resets any delta key. Used by refreshAll(), donation settle
	--              re-broadcast, and onCharacterAdded (R6.1, R6.2, R6.3).
	--   "recovery" — reset every recipient's per-pair delta key and send a full
	--              Snapshot to each recipient. Used by handleAvatarRefreshed and
	--              admin rank-change refresh (R6.4). This is the ONLY path that
	--              may reset delta keys.
	--
	-- If the proximity dependency is nil the broadcast is suppressed and an error
	-- is logged (R1.3).
	local function broadcastPayload(player: Player, mode: ("delta" | "recovery")?)
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0)
		if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("broadcastpayload_total")
		end
		local t0 = os.clock()
		local resolvedMode: "delta" | "recovery" = if mode == "recovery" then "recovery" else "delta"

		local payload, changed = buildAndCachePayload(player)
		if not payload then
			return
		end
		syncBuiltinPlayerList(player, payload)

		local attachedGui = activeGuis[player.UserId]
		if attachedGui and attachedGui.Parent then
			OverheadPremiumBadge.apply(attachedGui, payload)
		end

		-- SYNCHRONOUS snapshot update (critical path — tidak boleh deferred via EventBus).
		-- PlayerSnapshotService needs visibleBadges BEFORE the next ACM open agar
		-- fast-path payload tidak mengembalikan badge kosong.
		-- EventBus:emit menggunakan task.spawn (deferred), yang menyebabkan race
		-- condition dimana snapshot belum ter-update saat ACM request datang.
		if changed or resolvedMode == "recovery" then
			if playerSnapshotService and type(playerSnapshotService.updateFromOverhead) == "function" then
				playerSnapshotService:updateFromOverhead(payload)
			end
			if eventBus and type(eventBus.emit) == "function" then
				-- Emit ke downstream non-critical (RoleToolService, MusicService, dll).
				-- Deferred via task.spawn di EventBus acceptable untuk consumer ini.
				eventBus:emit("Overhead:Payload", payload)
			end
		end

		-- In delta mode skip the wire entirely when the payload is unchanged —
		-- there is nothing to send to any recipient.
		if not changed and resolvedMode ~= "recovery" then
			log:debug("Payload unchanged, skip broadcast", { player = player.Name })
			return
		end

		-- R1.3: proximity is required to route recipients. Suppress and log if missing.
		if not proximity then
			log:error("broadcastPayload: InterestManager/proximity dependency missing; suppressing broadcast", {
				player = player.Name,
				mode = resolvedMode,
			})
			return
		end

		-- Route to proximity subscribers only (R1.1 — no fireAllClients).
		local recipients = proximity:getSubscribers("overhead:", player)
		local subjectUserId = player.UserId

		for _, viewer in recipients do
			local key = deltaKey(subjectUserId, viewer.UserId)
			if resolvedMode == "recovery" then
				-- R6.4: reset this recipient's baseline so computeDelta returns full state.
				deltaCompressor:resetKey(key)
			end
			local delta = deltaCompressor:computeDelta(key, payload :: any)
			if delta then
				overheadNetwork:fireClient(viewer, {
					kind = Config.Overhead.DELTA_MESSAGE_KIND,
					userId = subjectUserId,
					delta = delta,
				})
			end
		end

		log:debug("Payload broadcast", {
			player = player.Name,
			mode = resolvedMode,
			recipients = #recipients,
		})
	end
	local function handleAvatarRefreshed(player: Player)
		-- Stability fix: JANGAN destroy GUI lama dulu. Sebelumnya destroy → gap
		-- 1.2s tanpa GUI (6 retry × 0.1s). Sekarang biar ensureGuiAttached handle:
		-- kalau Head reference sama, reuse existing GUI (zero gap). Kalau Head
		-- berubah, attachGui destroy+create atomik (no yield between).
		-- Memory leak note: attachGui sudah handle cleanup existing GUI (line 360-363)
		-- + cleanupCharacterOverheads, jadi destroy di sini redundant.
		local wasEnabled = false
		local existing = activeGuis[player.UserId]
		if existing then
			wasEnabled = existing.Enabled
		end

		task.spawn(function()
			for _ = 1, 6 do
				local gui = ensureGuiAttached(player)
				if gui then
					-- Preserve visibility: kalau GUI lama was Enabled, enable yang baru
					-- supaya client tidak lihat overhead hilang sepersekian detik.
					-- Client akan re-apply payload via recovery broadcast di bawah.
					if wasEnabled then
						gui.Enabled = true
					end
					task.wait(0.1)
					-- Recovery mode: reset all per-recipient baselines so every
					-- current viewer receives a full Snapshot (R6.4).
					broadcastPayload(player, "recovery")
					return
				end
				task.wait(0.1)
			end
			log:warn("Failed to reattach overhead after avatar refresh", {
				player = player.Name,
			})
		end)
	end
	-- ----------------------------------------------------------
	-- Kirim payload semua player yang sudah ada ke satu client baru
	-- Dipanggil saat player baru join agar bisa lihat overhead orang lain
	-- ----------------------------------------------------------
	local function sendAllExistingTo(newPlayer: Player)
		local batchSize = math.max(1, Config.Overhead.EXISTING_PAYLOAD_BATCH_SIZE)
		local batchDelay = math.max(0, Config.Overhead.EXISTING_PAYLOAD_BATCH_DELAY)
		local batch = table.create(batchSize)

		local function flushBatch()
			if #batch == 0 then
				return
			end

			overheadNetwork:fireClient(newPlayer, {
				kind = Config.Overhead.BATCH_MESSAGE_KIND,
				payloads = batch,
			})
			batch = table.create(batchSize)
		end

		for _, existingPlayer in ipairs(Players:GetPlayers()) do
			if existingPlayer.Character and dataReadyPlayers[existingPlayer.UserId] then
				local payload: OverheadPayload? = cachedPayloads[existingPlayer.UserId]
				if not payload then
					local builtPayload = select(1, buildAndCachePayload(existingPlayer))
					payload = builtPayload
				end
				if payload then
					table.insert(batch, payload)
					if #batch >= batchSize then
						flushBatch()
						if batchDelay > 0 then
							task.wait(batchDelay)
						end
					end
				end
			end
		end
		flushBatch()
		log:debug("Existing payloads sent to new player", { player = newPlayer.Name })
	end
	-- ----------------------------------------------------------
	-- PlayerAdded flow
	-- ----------------------------------------------------------
	-- Retry attach GUI dengan backoff. Saat avatar besar / humanoid description lambat
	-- / server high load, Head/HumanoidRootPart bisa muncul setelah timeout 5 detik.
	-- Tanpa retry overhead sama sekali tidak akan muncul untuk player tersebut.
	local ATTACH_RETRY_DELAYS = { 0.2, 0.5, 1, 1, 1, 1, 1, 1, 1, 1 }
	local ATTACH_RETRY_TOTAL_TIMEOUT = 12

	local function tryAttachGui(player: Player, character: Model): BillboardGui?
		local gui = attachGui(player, character)
		if gui then
			return gui
		end

		local startedAt = os.clock()
		for _, delay in ipairs(ATTACH_RETRY_DELAYS) do
			if not player.Parent then
				return nil
			end
			if os.clock() - startedAt >= ATTACH_RETRY_TOTAL_TIMEOUT then
				break
			end
			task.wait(delay)
			gui = ensureGuiAttached(player)
			if gui then
				return gui
			end
		end

		log:warn("Failed to attach overhead GUI after retries", {
			player = player.Name,
			elapsedMs = math.floor((os.clock() - startedAt) * 1000),
		})
		return nil
	end

	local JOIN_DATA_READY_TIMEOUT = 5

	local function finishCharacterSetup(player: Player, isRespawn: boolean?)
		-- Join-time DataStore reads are serialized; wait until this player's data is
		-- ready before the first broadcast so we don't fan out unbudgeted reads.
		if not dataReadyPlayers[player.UserId] then
			return
		end

		local respawn = isRespawn == true or hasCompletedInitialSetup[player.UserId] == true

		if respawn then
			-- Respawn: GUI baru + baseline client hilang. Recovery wajib supaya
			-- payload tetap terkirim walau S1 short-circuit (changed=false).
			if not player.Parent then
				return
			end
			broadcastPayload(player, "recovery")
			hasCompletedInitialSetup[player.UserId] = true
			return
		end

		-- Pastikan client-side sudah ready sebelum broadcast (join pertama saja)
		task.wait(Config.Overhead.CHARACTER_READY_DELAY)
		if not player.Parent then
			return
		end
		-- 1. Broadcast overhead player ini ke semua subscriber (delta mode — R6.2).
		--    The Snapshot-on-enter handler in ProximityInterestService (task 3.2) will
		--    send a full Snapshot to each viewer when they enter View_Range; this call
		--    ensures any subscriber who is *already* watching receives the latest delta.
		broadcastPayload(player)
		hasCompletedInitialSetup[player.UserId] = true
		task.spawn(function()
			if not waitForGameplayReady(player) then
				return
			end
			sendAllExistingTo(player)
		end)
		task.delay(Config.Overhead.GROUP_RANK_SETTLE_DELAY, function()
			if not player.Parent then
				return
			end
			if not waitForGameplayReady(player) then
				return
			end
			broadcastPayload(player)
		end)
		task.delay(Config.Overhead.GROUP_RANK_SETTLE_DELAY * 2, function()
			if not player.Parent then
				return
			end
			if not waitForGameplayReady(player) then
				return
			end
			broadcastPayload(player)
		end)
	end

	local function onCharacterAdded(player: Player, character: Model)
		local isRespawn = hasCompletedInitialSetup[player.UserId] == true
		-- 2E: Safety net hanya untuk join pertama. Respawn tidak perlu menunggu
		-- DataStore lagi — data sudah di memory.
		if not isRespawn then
			task.delay(JOIN_DATA_READY_TIMEOUT, function()
				if player.Parent and not dataReadyPlayers[player.UserId] then
					log:warn("Join-time data ready timeout; broadcasting with available data", {
						player = player.Name,
					})
					dataReadyPlayers[player.UserId] = true
					finishCharacterSetup(player, false)
				end
			end)
		end

		local gui = tryAttachGui(player, character)
		if not gui then
			return
		end

		-- Tampilkan segera saat respawn — data sudah di cache, tidak perlu tunggu wire.
		if isRespawn and cachedPayloads[player.UserId] then
			gui.Enabled = true
		end

		finishCharacterSetup(player, isRespawn)
	end
	local function onPlayerAdded(player: Player)
		-- Pre-create leaderstats sebelum character muncul. Bug 2026-05-23:
		-- Roblox PlayerList kadang cuma show DisplayName + Likes karena
		-- syncBuiltinPlayerList baru jalan setelah CHARACTER_READY_DELAY (kira-kira
		-- 0.5s setelah respawn). Kalau client udah subscribe ke leaderstats sebelum
		-- semua IntValue dibuat, column Streak/Robux/Cash bisa ke-skip di tampilan.
		-- Pre-create dengan Value=0 di sini bikin folder lengkap dari awal; nilai
		-- aktual di-isi saat broadcastPayload pertama jalan.
		--
		-- URUTAN PENTING: Rank dibuat PERTAMA. Roblox PlayerList sort descending
		-- berdasarkan IntValue pertama di leaderstats, jadi Rank-first = list
		-- terurut dari role/rank tertinggi ke terendah sejak awal (sebelum sync).
		-- Semua kolom premade (selalu ada), bukan on-demand.
		do
			local leaderstats = getOrCreateLeaderstats(player)
			local _ = leaderstats -- suppress unused warning
			getOrCreateRankStat(player)
			getOrCreateStreakStat(player)
			if Config.FeatureFlags.LevelSystemEnabled then
				getOrCreateLevelStat(player)
			end
			getOrCreateLikesStat(player)
			getOrCreateRobuxStat(player)
			getOrCreateCashStat(player)
		end
		-- 2C: Assign default Guest team segera saat player join, sebelum character
		-- muncul. Sebelumnya player stay Neutral (Roblox default) sampe datastore
		-- load selesai (15+ detik kalau throttled). Guest team instant → PlayerList
		-- langsung punya team color. Saat data asli load, syncBuiltinPlayerList
		-- update ke team yang benar.
		local guestTeam = getOrCreateTeam("Guest", "Guest")
		if guestTeam then
			player.Neutral = false
			player.Team = guestTeam
		end
		-- Handle karakter yang sudah ada (join mid-game)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		-- Handle respawn
		player.CharacterAdded:Connect(function(character)
			task.spawn(onCharacterAdded, player, character)
		end)
		local existingSubConn = subscriptionSignalConnections[player.UserId]
		if existingSubConn then
			existingSubConn:Disconnect()
		end
		subscriptionSignalConnections[player.UserId] = player
			:GetPropertyChangedSignal("HasRobloxSubscription")
			:Connect(function()
				if not player.Parent then
					return
				end
				storedInputsFingerprints[player.UserId] = nil
				task.spawn(broadcastPayload, player)
			end)
	end
	-- ----------------------------------------------------------
	-- PlayerRemoving cleanup
	-- ----------------------------------------------------------
	local function onPlayerRemoving(player: Player)
		local existing = activeGuis[player.UserId]
		if existing and existing.Parent then
			existing:Destroy()
		end
		activeGuis[player.UserId] = nil
		local subConn = subscriptionSignalConnections[player.UserId]
		if subConn then
			subConn:Disconnect()
			subscriptionSignalConnections[player.UserId] = nil
		end
		cachedPayloads[player.UserId] = nil
		payloadFingerprints[player.UserId] = nil
		-- S1: cleanup stored inputs fingerprint to avoid memory leak
		storedInputsFingerprints[player.UserId] = nil
		payloadWasFallback[player.UserId] = nil
		dataReadyPlayers[player.UserId] = nil
		hasCompletedInitialSetup[player.UserId] = nil
		gameplayReadyPlayers[player.UserId] = nil
		-- Free all per-recipient delta baselines where this player was the subject
		-- (keys "overhead:<userId>:<viewerUserId>"). The per-viewer side of any
		-- remaining pairs is cleaned up when the onSubscriberRemoved handler fires
		-- (task 3.2), or by the viewer's own onPlayerRemoving when they disconnect.
		local subjectPrefix = ("overhead:%d:"):format(player.UserId)
		deltaCompressor:cleanup(subjectPrefix)
		log:debug("Player cleanup", { player = player.Name })
	end
	-- ----------------------------------------------------------
	-- Client refresh request handler (rate limited + idempotent)
	-- ----------------------------------------------------------
	RemoteRequestRefresh.OnServerEvent:Connect(function(player: Player, raw: any)
		local sizeOk = Validator.checkSize(raw)
		if not sizeOk then
			return
		end
		local validation = Validator.overheadRefresh(raw)
		if not validation.valid then
			return
		end
		-- Authorization - hanya player dengan role Admin+ yang bisa manual refresh
		-- Cegah exploiter spam group cache invalidation
		local payloadResult = if type(service.getEffectivePayload) == "function"
			then service:getEffectivePayload(player)
			else service:buildPayload(player)
		local playerRole = if payloadResult.ok and payloadResult.value
			then payloadResult.value.role
			else service:getRawGroupRole(player)
		local isAdmin = PermissionDomain.canUseAdminPanel(playerRole, player.UserId)
		if not isAdmin then
			log:warn("Refresh rejected: not admin", { player = player.Name, role = playerRole })
			return
		end
		local allowed, reason = limiter:check(player.UserId)
		if not allowed then
			log:warn("Rate limited", { player = player.Name, reason = reason })
			return
		end
		-- TTL-based idempotency check + expired entries cleanup
		local now = os.clock()
		for key, expiresAt in pairs(processedReqs) do
			if expiresAt <= now then
				processedReqs[key] = nil
			end
		end

		if processedReqs[raw.requestId] then
			return
		end
		processedReqs[raw.requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW
		service:invalidateGroupCache(player.UserId)
		task.spawn(broadcastPayload, player)
	end)

	RemoteRosterRequest.OnServerEvent:Connect(function(player: Player)
		if not rosterLimiter:check(player.UserId) then
			log:warn("Roster request rate limited", { player = player.Name })
			return
		end

		task.spawn(function()
			sendAllExistingTo(player)
			sendAboutRosterTo(player)
		end)
	end)
	-- ----------------------------------------------------------
	-- Wiring lifecycle events
	-- ----------------------------------------------------------
	ensurePremadeRoleTeams()
	Players.PlayerMembershipChanged:Connect(function(player: Player)
		if not player.Parent then
			return
		end
		storedInputsFingerprints[player.UserId] = nil
		task.spawn(broadcastPayload, player)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	if eventBus and type(eventBus.on) == "function" then
		eventBus:on("Avatar:Refreshed", function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local player = payload.player
			if not player or not player:IsA("Player") or not player.Parent then
				return
			end
			handleAvatarRefreshed(player)
		end)
	end

	-- ----------------------------------------------------------
	-- Snapshot-on-enter and leave handlers (task 3.2)
	-- ----------------------------------------------------------
	-- Wire up ProximityInterestService events if the dependency is provided.
	-- These handlers implement Requirement 1.4, 6.5, 6.6:
	--   - onSubscriberAdded:   reset that pair's key and send a full Snapshot to
	--                          the entering viewer only within 1s (R1.4, R6.5)
	--   - onSubscriberRemoved: drop that pair's delta baseline so re-entry sends
	--                          a fresh Snapshot (R6.6)
	if proximity then
		proximity:onSubscriberAdded(function(ev)
			-- Only handle overhead channel events; sync is handled by SyncService.
			if ev.channelPrefix ~= "overhead:" then
				return
			end

			-- Build the current payload for the subject.
			local payload = buildPayload(ev.subject)
			if not payload then
				log:warn("Snapshot-on-enter: buildPayload failed", {
					subject = ev.subject.Name,
					viewer = ev.viewer.Name,
				})
				return
			end
			-- Note: usedFallback is ignored here; we still send the best snapshot we have.
			-- The fallback payload itself will trigger a rebuild on the next broadcast cycle.

			-- Ensure snapshot is fresh (mirrors broadcastPayload's synchronous update).
			-- Snapshot-on-enter happens AFTER the initial broadcastPayload timeout/race,
			-- jadi update di sini memastikan data tidak hilang.
			if playerSnapshotService and type(playerSnapshotService.updateFromOverhead) == "function" then
				playerSnapshotService:updateFromOverhead(payload)
			end

			-- Reset the per-pair delta key to establish a fresh baseline for this
			-- viewer, so the first computeDelta returns a full Snapshot (R1.4, R6.5).
			local key = deltaKey(ev.subject.UserId, ev.viewer.UserId)
			deltaCompressor:resetKey(key)

			-- Send the full Snapshot to the entering viewer only.
			-- After resetKey, computeDelta returns the full state as a "Snapshot".
			-- Use DELTA_MESSAGE_KIND — the client processes both full and delta the same way.
			local snap = deltaCompressor:computeDelta(key, payload :: any)
			if snap then
				overheadNetwork:fireClient(ev.viewer, {
					kind = Config.Overhead.DELTA_MESSAGE_KIND,
					userId = ev.subject.UserId,
					delta = snap,
				})
			end

			log:debug("Snapshot-on-enter sent", {
				subject = ev.subject.Name,
				viewer = ev.viewer.Name,
			})
		end)

		proximity:onSubscriberRemoved(function(ev)
			-- Only handle overhead channel events.
			if ev.channelPrefix ~= "overhead:" then
				return
			end

			-- Drop the per-pair delta baseline so that when the viewer re-enters
			-- View_Range, the onSubscriberAdded handler sends a fresh Snapshot (R6.6).
			local key = deltaKey(ev.subject.UserId, ev.viewer.UserId)
			deltaCompressor:resetKey(key)

			log:debug("Delta baseline dropped on leave", {
				subject = ev.subject.Name,
				viewer = ev.viewer.Name,
			})
		end)

		log:info("Snapshot-on-enter and leave handlers wired")
	else
		log:warn("ProximityInterestService not provided; Snapshot-on-enter/leave handlers not wired")
	end
	-- ----------------------------------------------------------
	-- Public API
	-- ----------------------------------------------------------
	local controller = {}
	-- Called by Main.server when ProfileLoader has finished the serialized join-time
	-- DataStore reads for this player. Marks the player's data as ready and triggers
	-- the first broadcast if the character/GUI is already attached.
	function controller:onPlayerDataReady(player: Player)
		if not player.Parent then
			return
		end
		dataReadyPlayers[player.UserId] = true
		if activeGuis[player.UserId] then
			finishCharacterSetup(player)
		end
	end
	-- Broadcast overhead player tertentu ke subscribers (e.g. setelah admin set rank).
	-- Pass mode="recovery" to force-reset all per-recipient baselines and send full
	-- Snapshots (use for avatar refresh, admin rank-change — R6.4).
	function controller:refreshPlayer(player: Player, mode: ("delta" | "recovery")?)
		task.spawn(broadcastPayload, player, mode)
	end
	-- Broadcast semua player ke subscribers (e.g. setelah leaderboard update).
	-- Uses delta mode — never resets keys / sends Force_Broadcast (R6.1).
	-- S2 (quota-efficiency-pass-2026-06, Phase 1): debounced — kalau dipanggil
	-- <S2_DEBOUNCE_MS dari last call, skip (coalesce donation burst). Set
	-- Config.Overhead.S2_DEBOUNCE_MS = 0 to disable.
	-- Patch #2 R5: additional rate-limit REFRESH_ALL_HARD_LIMIT_SEC agar CPU+fireClient
	-- budget tidak jebol walau fingerprint berubah (e.g. donasi burst >S2 window).
	local lastRefreshAllAt = 0
	local REFRESH_ALL_HARD_LIMIT_SEC = 5
	function controller:refreshAll()
		local now = os.clock()
		local debounceMs = tonumber(Config.Overhead.S2_DEBOUNCE_MS) or 0
		if debounceMs > 0 and (now - lastRefreshAllAt) < debounceMs / 1000 then
			log:debug("refreshAll skipped (debounce window)", { msSinceLast = (now - lastRefreshAllAt) * 1000 })
			return
		end
		if (now - lastRefreshAllAt) < REFRESH_ALL_HARD_LIMIT_SEC then
			log:debug("refreshAll skipped (hard rate-limit window)", { secSinceLast = (now - lastRefreshAllAt) })
			return
		end
		lastRefreshAllAt = now
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0)
		if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("overhead_refreshall_total")
		end
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(broadcastPayload, player)
		end
	end
	log:info("OverheadController initialized")
	return controller
end
return createOverheadController
