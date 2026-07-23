--!strict
-- SyncService - Server-side authoritative animation + sync system.
--
-- Refactored 2026-05-23: reverted to legacy "single source of truth" pattern.
-- Server is the only one that calls Animator:Play(). Roblox's built-in
-- animation replication takes the result to every client. Clients no longer
-- run their own VisualDanceSyncService — that dual-rendering setup was the
-- root cause of the wut/glitch/desync bugs in the previous build.
--
-- Public API kept stable for Main.server.luau and SessionCommandService:
--   :executeAnimation(player, animation, shouldPlay, speed, intent?, loaded?) -> Result
--   :handleSyncRequest(player, target, condition, loaded?) -> Result
--   :adjustSpeed(player, speed, loaded?) -> Result
--   :onPlayerAdded(player), :onPlayerRemoving(player), :onCharacterAdded(player, character)
--   :prepareRefreshRestore, :restorePreparedRefresh, :clearPreparedRefresh
--   :setOnFollowersHardUnsynced, :getAssetReports
--   :getLeaderDisplayName, :getCurrentAnimationName

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResultModule = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local SyncDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SyncDomain)
local AfkGuardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AfkGuardDomain)
local AnimatorUtils = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.ContextModule.AnimatorUtils)
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

-- Inlined Result<T> to keep this module self-contained for the analyzer.
type Result<T> = { ok: true, value: T } | { ok: false, error: string }

export type SyncService = {
	executeAnimation: (
		self: SyncService,
		player: Player,
		animation: Animation,
		shouldPlay: boolean,
		speed: number,
		intent: string?,
		loadedAnimations: { [string]: any }?
	) -> Result<string>,
	handleSyncRequest: (
		self: SyncService,
		player: Player,
		targetPlayer: Player,
		condition: boolean,
		loadedAnimations: { [string]: any }?
	) -> Result<string>,
	handleTransferLead: (
		self: SyncService,
		player: Player,
		targetPlayer: Player
	) -> Result<string>,
	adjustSpeed: (
		self: SyncService,
		player: Player,
		speed: number,
		loadedAnimations: { [string]: any }?
	) -> Result<string>,
	onPlayerAdded: (self: SyncService, player: Player) -> (),
	onPlayerRemoving: (self: SyncService, player: Player) -> { leaderName: string, followerNames: { string } }?,
	onCharacterAdded: (self: SyncService, player: Player, character: Model) -> (),
	prepareRefreshRestore: (self: SyncService, player: Player) -> (),
	restorePreparedRefresh: (self: SyncService, player: Player) -> (),
	clearPreparedRefresh: (self: SyncService, player: Player) -> (),
	captureSyncSnapshotForTeleport: (self: SyncService, player: Player) -> any?,
	getTopLeaderByFollowerCount: (self: SyncService, excludeUserId: number?) -> Player?,
	restoreAfterAfkRejoin: (
		self: SyncService,
		player: Player,
		syncRestore: any,
		options: {
			fireSyncNotification: ((player: Player, payload: { [string]: any }) -> ())?,
			notifyPlayer: ((player: Player, message: string, kind: string?) -> ())?,
		}?
	) -> (),
	setOnFollowersHardUnsynced: (
		self: SyncService,
		callback: (leaderName: string, followerNames: { string }) -> ()
	) -> (),
	getAssetReports: (self: SyncService) -> { [number]: any },
	getLeaderDisplayName: (self: SyncService, leaderName: string?) -> string,
	getCurrentAnimationName: (self: SyncService, leaderName: string?) -> string?,
}

-- Structural type for the optional ProximityInterestService dependency (R1.2, R1.3).
-- Injected by Main.server.luau (task 2.2). Declared here so SyncService does not
-- hard-depend on the Service module at require-time.
type ProximityInterestService = {
	getSubscribers: (self: ProximityInterestService, channelPrefix: string, subject: Player) -> { Player },
}

local function create(deps: {
	config: any,
	domain: any,
	logger: any,
	animationLoader: any,
	-- Optional: injected by Main.server.luau (task 2.2) for R1.2 proximity filtering.
	proximity: ProximityInterestService?,
	interest: any?,
	favoritesRepository: any?,
}): SyncService
	local config = deps.config
	local logger = deps.logger
	local animLoader = deps.animationLoader
	local proximity = deps.proximity
	local interest = deps.interest
	local favoritesRepository = deps.favoritesRepository
	local assetReporter = AssetHealthReporter.new(logger)

	-- ============================================================
	-- STATE — flat and minimal. Keys mostly by player.Name to stay
	-- consistent with SyncDomain helpers.
	-- ============================================================
	local syncMap: { [string]: string } = {} -- [followerName] = leaderName
	local followerMap: { [string]: { [string]: boolean } } = {} -- [leaderName] = { [followerName] = true }
	local activeAnimations: { [string]: string } = {} -- [playerName] = animationName (root only)
	local activeAnimationIds: { [string]: string } = {} -- [playerName] = animationId (root only)
	local activeSpeeds: { [string]: number } = {} -- [playerName] = speed (root only)
	local syncStartTimes: { [string]: number } = {} -- [playerName] = tick() when this player started leading

	local originalWalkSpeeds: { [number]: number } = {}
	local processingRequests: { [number]: boolean } = {}
	local lastRequestTime: { [number]: number } = {}
	local characterConnections: { [number]: RBXScriptConnection } = {}

	local pendingRefreshRestore: {
		[number]: {
			animationName: string?,
			animationId: string?,
			timePosition: number,
			speed: number,
			syncing: any,
			isLeader: any,
			followerCount: any,
		},
	} = {}

	-- Track lifecycle: detect Roblox Animate script tracks that must never be destroyed.
	-- These are critical for character movement (walk, run, idle, jump, etc.)
	local ANIMATE_PATTERNS = {
		"walk", "run", "idle", "jump", "fall", "climb", "swim",
		"sit", "toolnone", "laugh", "point", "wave", "cheer", "salute",
	}

	local function isAnimateTrack(track: any): boolean
		local anim = track.Animation
		if not anim then
			return false
		end
		local name = string.lower(anim.Name or "")
		for _, pattern in ANIMATE_PATTERNS do
			if name:find(pattern, 1, true) then
				return true
			end
		end
		-- Fallback: tracks without dance priority and without our custom ANIM_PRIORITY
		-- are likely Roblox system tracks
		local isDance = AnimatorUtils.isDanceTrack(track, prewarmAnimations)
		if not isDance and track.Priority ~= config.ANIM_PRIORITY then
			return true
		end
		return false
	end

	-- Tracks which animation IDs were prewarmed per player (userId → set of animationId).
	-- Used by executeAnimation to decide whether on-demand load is needed (R5.4, R5.5).
	local prewarmSets: { [number]: { [string]: boolean } } = {}
	-- Phase 4: cancel in-flight prewarm on leave / character swap.
	local prewarmGeneration: { [number]: number } = {}
	-- Global admission: max concurrent prewarming players + loads/sec across the server.
	local activePrewarmSlots = 0
	local prewarmLoadWindowStart = 0
	local prewarmLoadsInWindow = 0

	local onFollowersHardUnsyncedCallback: ((leaderName: string, followerNames: { string }) -> ())? = nil

	-- Dance request throttle: at least switch fade so crossfades cannot stack.
	local SWITCH_FADE = math.max(
		tonumber(config.SWITCH_FADE_IN) or 0.55,
		tonumber(config.SWITCH_FADE_OUT) or 0.55
	)
	local MIN_REQUEST_INTERVAL = math.max(
		0.10,
		tonumber(config.SWITCH_INPUT_COOLDOWN) or SWITCH_FADE,
		SWITCH_FADE
	)
	local FADE_IN = config.FADE_IN or 0.45
	local FADE_OUT = config.FADE_OUT or FADE_IN
	local SWITCH_FADE_IN = SWITCH_FADE
	local SWITCH_FADE_OUT = SWITCH_FADE
	local SYNC_JOIN_FADE = math.max(0.12, tonumber(config.SYNC_JOIN_FADE_IN) or 0.4)

	local prewarmAnimations = animLoader.loadAnimations()

	-- ============================================================
	-- WALK SPEED HELPERS
	-- ============================================================
	local function saveWalkSpeed(player: Player)
		if originalWalkSpeeds[player.UserId] then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			originalWalkSpeeds[player.UserId] = humanoid.WalkSpeed
		end
	end

	local function setDanceWalkSpeed(player: Player)
		saveWalkSpeed(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = config.DANCE_WALK_SPEED or 16
		end
	end

	local function restoreWalkSpeed(player: Player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and originalWalkSpeeds[player.UserId] then
			humanoid.WalkSpeed = originalWalkSpeeds[player.UserId]
		end
	end

	-- ============================================================
	-- THROTTLE
	-- ============================================================
	local function canProcessRequest(player: Player): boolean
		if processingRequests[player.UserId] then
			return false
		end
		local last = lastRequestTime[player.UserId] or 0
		if (os.clock() - last) < MIN_REQUEST_INTERVAL then
			return false
		end
		return true
	end

	local function startProcessing(player: Player)
		processingRequests[player.UserId] = true
		lastRequestTime[player.UserId] = os.clock()
	end

	local function endProcessing(player: Player)
		processingRequests[player.UserId] = false
	end

	local function isBeingCarried(player: Player): boolean
		local character = player.Character
		if not character then
			return false
		end
		local weldName = (Config.Carry and Config.Carry.WELD_NAME) or "CarryWeld"
		for _, inst in ipairs(character:GetDescendants()) do
			if inst:IsA("Weld") and inst.Name == weldName then
				return true
			end
		end
		return false
	end

	-- ============================================================
	-- SYNC MAP MAINTENANCE
	-- ============================================================
	local function registerSync(followerName: string, leaderName: string)
		local oldLeader = syncMap[followerName]
		if oldLeader and followerMap[oldLeader] then
			followerMap[oldLeader][followerName] = nil
		end
		syncMap[followerName] = leaderName
		followerMap[leaderName] = followerMap[leaderName] or {}
		followerMap[leaderName][followerName] = true
	end

	local function unregisterSync(followerName: string)
		local oldLeader = syncMap[followerName]
		syncMap[followerName] = nil
		if oldLeader and followerMap[oldLeader] then
			followerMap[oldLeader][followerName] = nil
		end
	end

	-- Find ultimate leader of a player (walk up syncMap)
	local function findAnimationLeader(player: Player): Player
		local currentName = player.Name
		local visited: { [string]: boolean } = {}
		for _ = 1, config.MAX_CHAIN_DEPTH or 100 do
			if visited[currentName] then
				break
			end
			visited[currentName] = true
			local nextLeader = syncMap[currentName]
			if not nextLeader then
				break
			end
			currentName = nextLeader
		end
		return Players:FindFirstChild(currentName) or player
	end

	-- BFS downward from rootPlayer through followerMap.
	-- Returns array of {player, humanoid} for everyone synced through rootPlayer
	-- (rootPlayer included).
	local function findSyncedPlayers(rootPlayer: Player): { { player: Player, humanoid: Humanoid? } }
		local result = {}
		local queue: { string } = { rootPlayer.Name }
		local visited: { [string]: boolean } = { [rootPlayer.Name] = true }
		while #queue > 0 do
			local currentName = table.remove(queue, 1) :: string
			local player = Players:FindFirstChild(currentName)
			if player then
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
				table.insert(result, { player = player, humanoid = humanoid })
			end
			local followers = followerMap[currentName]
			if followers then
				for followerName in pairs(followers) do
					if not visited[followerName] then
						visited[followerName] = true
						table.insert(queue, followerName)
					end
				end
			end
		end
		return result
	end

	-- ============================================================
	-- ANIMATION LOOKUP
	-- ============================================================
	-- Prefer AnimationId (authoritative). Name-first caused sync join to pick the
	-- wrong Dance/Pose asset when names collide — looks wrong until the player
	-- switches dance (panel passes the real Animation instance).
	local function findAnimation(animationName: string?, animationId: string?): Animation?
		if animationId and animationId ~= "" then
			for _, anim in pairs(prewarmAnimations) do
				if typeof(anim) == "Instance" and anim:IsA("Animation") and anim.AnimationId == animationId then
					return anim
				end
			end
		end
		if animationName then
			local byName = prewarmAnimations[animationName]
			if typeof(byName) == "Instance" and byName:IsA("Animation") then
				return byName
			end
		end
		return nil
	end

	-- ============================================================
	-- LEADER STATUS BROADCAST (debounced)
	-- ============================================================
	local leaderStatusPending = false
	local function scheduleLeaderUpdate()
		if leaderStatusPending then
			return
		end
		leaderStatusPending = true
		task.defer(function()
			local t0 = os.clock()
			leaderStatusPending = false
			-- Reset all
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then
					p.Character:SetAttribute("IsLeader", nil)
					p.Character:SetAttribute("FollowerCount", nil)
				end
			end
			-- Set for actual leaders (R1.2: only broadcast to players with subscribers in view range).
			for leaderName, followers in pairs(followerMap) do
				local count = 0
				for _ in pairs(followers) do
					count += 1
				end
				if count > 0 then
					local leader = Players:FindFirstChild(leaderName)
					if leader and leader.Character then
						-- R1.2: Skip attribute broadcast when no subscribers are in View_Range.
						-- ProximityInterestService drives InterestManager channel membership;
						-- getSubscribers returns only viewers within spatial range.
						if proximity then
							local subscribers = proximity:getSubscribers("sync:", leader)
							if #subscribers == 0 then
								continue
							end
						end
						leader.Character:SetAttribute("IsLeader", true)
						leader.Character:SetAttribute("FollowerCount", count)
					end
				end
			end
		end)
	end

	-- ============================================================
	-- LEADER TIME (for snap-to-phase on sync join)
	-- ============================================================
	local function getLeaderTime(leader: Player): number
		local startTime = syncStartTimes[leader.Name]
		if not startTime then
			return 0
		end
		local speed = activeSpeeds[leader.Name] or 1
		return math.max(0, (tick() - startTime) * speed)
	end

	local function getLeaderTrackTimePosition(leader: Player): number?
		local leaderAnimator = AnimatorUtils.getAnimator(leader)
		if not leaderAnimator then
			return nil
		end
		-- Prefer the authoritative active dance id so mid-crossfade never samples the fading-out track.
		local expectedId = activeAnimationIds[leader.Name]
		local leaderTrack = AnimatorUtils.getPlayingDanceTrack(leaderAnimator, prewarmAnimations, expectedId)
		if not leaderTrack or not leaderTrack.IsPlaying then
			return nil
		end
		local ok, timePosition = pcall(function()
			return leaderTrack.TimePosition
		end)
		if not ok or type(timePosition) ~= "number" then
			return nil
		end
		return timePosition
	end

	-- ============================================================
	-- PREWARM TRACK SELECTION (R5.1, R5.2, R5.3)
	--
	-- Selects up to maxCount Animation objects from the full catalog for
	-- server-side prewarming per character:
	--   1. Collect animation objects into a stable-sorted default list
	--      (sorted by AnimationId so identical inputs → identical selection).
	--   2. If the player has favorited dance tracks available at prewarm
	--      time, fill the selection with those first (up to maxCount).
	--   3. Fill any remaining slots from the deterministic default list.
	-- Returns between 1 and maxCount entries (or all entries if catalog < maxCount).
	-- ============================================================
	local function selectPrewarmTracks(player: Player, catalog: { [string]: Animation }, maxCount: number): { Animation }
		-- Build a deterministic default list sorted by AnimationId (R5.3).
		local defaultList: { Animation } = {}
		for _, anim in pairs(catalog) do
			if typeof(anim) == "Instance" and anim:IsA("Animation") then
				table.insert(defaultList, anim)
			end
		end
		table.sort(defaultList, function(a, b)
			return a.AnimationId < b.AnimationId
		end)

		if #defaultList == 0 then
			return defaultList
		end

		-- Read player's favorited animations from server memory (owner-only sync remote).
		local favoritedSet: { [string]: boolean } = {}
		if favoritesRepository and type(favoritesRepository.loadDecoded) == "function" then
			local decoded = favoritesRepository:loadDecoded(player)
			for animName, isFav in pairs(decoded) do
				if isFav == true and type(animName) == "string" then
					favoritedSet[animName] = true
				end
			end
		end

		local selected: { Animation } = {}
		local hasFavorites = next(favoritedSet) ~= nil

		if hasFavorites then
			-- First pass: prioritize favorited animations (R5.2).
			for _, anim in ipairs(defaultList) do
				if #selected >= maxCount then
					break
				end
				if favoritedSet[anim.Name] then
					table.insert(selected, anim)
				end
			end
		end

		-- Fill remaining slots from the deterministic default list (R5.3).
		for _, anim in ipairs(defaultList) do
			if #selected >= maxCount then
				break
			end
			if not favoritedSet[anim.Name] then
				table.insert(selected, anim)
			end
		end

		-- Clamp to maxCount in case both passes overshot (safety net).
		if #selected > maxCount then
			local trimmed: { Animation } = {}
			for i = 1, maxCount do
				trimmed[i] = selected[i]
			end
			return trimmed
		end

		return selected
	end

	local function bumpPrewarmGeneration(userId: number): number
		local nextGen = (prewarmGeneration[userId] or 0) + 1
		prewarmGeneration[userId] = nextGen
		return nextGen
	end

	local function acquirePrewarmSlot(userId: number, generation: number): boolean
		local maxConcurrent = math.max(1, math.floor(tonumber(config.SERVER_DANCE_TRACK_PREWARM_MAX_CONCURRENT) or 2))
		while activePrewarmSlots >= maxConcurrent do
			if prewarmGeneration[userId] ~= generation then
				return false
			end
			local player = Players:GetPlayerByUserId(userId)
			if not player or not player.Parent then
				return false
			end
			task.wait(0.05)
		end
		if prewarmGeneration[userId] ~= generation then
			return false
		end
		activePrewarmSlots += 1
		return true
	end

	local function releasePrewarmSlot()
		activePrewarmSlots = math.max(0, activePrewarmSlots - 1)
	end

	local function admitPrewarmLoad(userId: number, generation: number): boolean
		local maxPerSec = math.max(1, math.floor(tonumber(config.SERVER_DANCE_TRACK_PREWARM_MAX_LOADS_PER_SEC) or 24))
		while true do
			if prewarmGeneration[userId] ~= generation then
				return false
			end
			local now = os.clock()
			if now - prewarmLoadWindowStart >= 1 then
				prewarmLoadWindowStart = now
				prewarmLoadsInWindow = 0
			end
			if prewarmLoadsInWindow < maxPerSec then
				prewarmLoadsInWindow += 1
				return true
			end
			task.wait(0.05)
		end
	end

	local function prewarmAnimatorTracks(player: Player)
		if config.SERVER_DANCE_TRACK_PREWARM_ENABLED == false then
			return
		end
		local userId = player.UserId
		local generation = bumpPrewarmGeneration(userId)
		task.spawn(function()
			if not acquirePrewarmSlot(userId, generation) then
				return
			end
			local slotHeld = true
			local function releaseSlot()
				if slotHeld then
					slotHeld = false
					releasePrewarmSlot()
				end
			end

			local ok, err = pcall(function()
				if prewarmGeneration[userId] ~= generation then
					return
				end
				local animator = AnimatorUtils.getAnimator(player)
				if not animator then
					return
				end
				-- R5.1: clamp max prewarm to [1, SERVER_DANCE_TRACK_PREWARM_MAX].
				local maxPrewarm = math.max(1, math.min(
					math.floor(tonumber(config.SERVER_DANCE_TRACK_PREWARM_MAX) or 16),
					16
				))
				local batchDelay = math.max(0, tonumber(config.SERVER_DANCE_TRACK_PREWARM_BATCH_DELAY) or 0.03)

				-- R5.2, R5.3: select tracks using priority logic.
				local selectedTracks = selectPrewarmTracks(player, prewarmAnimations, maxPrewarm)

				-- Build a new prewarm set for this player (replaces any from a previous character).
				local newPrewarmSet: { [string]: boolean } = {}

				local warmed = 0
				for _, animation in ipairs(selectedTracks) do
					if prewarmGeneration[userId] ~= generation then
						return
					end
					if not admitPrewarmLoad(userId, generation) then
						return
					end
					local track, loadError = AnimatorUtils.getOrCreateTrack(animator, animation)
					if track then
						pcall(function()
							track.Priority = config.ANIM_PRIORITY
							track.Looped = true
							track:Stop(0)
						end)
						-- Record this animationId as prewarmed (R5.4: on-demand load check).
						if animation.AnimationId ~= "" then
							newPrewarmSet[animation.AnimationId] = true
						end
						newPrewarmSet[animation.Name] = true
					else
						assetReporter:recordInstanceFailure(
							animation,
							"SyncService.prewarmAnimatorTracks",
							loadError or "Failed to load animation",
							{ player = player.Name, userId = userId }
						)
					end
					warmed += 1
					task.wait(batchDelay)
				end

				if prewarmGeneration[userId] == generation then
					prewarmSets[userId] = newPrewarmSet
					logger:debug("Prewarmed animation tracks", { player = player.Name, count = warmed })
				end
			end)
			releaseSlot()
			if not ok then
				logger:warn("Prewarm animator tracks failed", {
					player = player.Name,
					error = tostring(err),
				})
			end
		end)
	end

	-- ============================================================
	-- CORE: replicateAnimation
	--
	-- Mirrors legacy CoreSync.replicateAnimation pattern. Server loads
	-- the track and Plays it on the rootPlayer + every transitive follower.
	-- Roblox replicates the AnimationTrack to clients automatically.
	--
	-- Parallel via task.spawn so N followers don't queue serially.
	-- ============================================================
	local function replicateAnimation(
		rootPlayer: Player,
		animation: Animation?,
		opts: { isSyncJoin: boolean?, speed: number?, fade: number?, stopFade: number?, timePosition: number? }?
	)
		local t0 = os.clock()
		opts = opts or {}
		local isSyncJoin = (opts :: any).isSyncJoin == true
		local fade = (opts :: any).fade
		local forcedPhase = (opts :: any).timePosition
		if type(forcedPhase) ~= "number" then
			forcedPhase = nil
		end
		if fade == nil then
			if not animation then
				fade = FADE_OUT
			elseif isSyncJoin then
				fade = SYNC_JOIN_FADE
			else
				fade = FADE_IN
			end
		end
		local stopFade = (opts :: any).stopFade or fade

		local leader = findAnimationLeader(rootPlayer)
		local isRootTheLeader = leader == rootPlayer

		-- Anchor leader timing only when:
		--   - rootPlayer is the leader of their chain, AND
		--   - this isn't a follower joining (sync join uses leader's existing time)
		if isRootTheLeader and animation and not isSyncJoin then
			if type(forcedPhase) == "number" then
				local speedForAnchor = (opts :: any).speed or activeSpeeds[rootPlayer.Name] or config.DEFAULT_SPEED or 1
				syncStartTimes[rootPlayer.Name] = tick() - (forcedPhase / math.max(speedForAnchor, 0.01))
			else
				syncStartTimes[rootPlayer.Name] = tick()
			end
			activeAnimations[rootPlayer.Name] = animation.Name
			activeAnimationIds[rootPlayer.Name] = animation.AnimationId
			if (opts :: any).speed then
				activeSpeeds[rootPlayer.Name] = (opts :: any).speed
			elseif activeSpeeds[rootPlayer.Name] == nil then
				activeSpeeds[rootPlayer.Name] = config.DEFAULT_SPEED or 1
			end
		end

		local leaderSpeed = activeSpeeds[leader.Name] or (opts :: any).speed or config.DEFAULT_SPEED or 1

		local syncedPlayers = findSyncedPlayers(rootPlayer)
		for _, entry in ipairs(syncedPlayers) do
			local syncedPlayer = entry.player
			local humanoid = entry.humanoid
			if not humanoid then
				continue
			end

			task.spawn(function()
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					-- Try to create one (some characters lose it briefly during respawn)
					local ok, created = pcall(function()
						local a = Instance.new("Animator")
						a.Parent = humanoid
						return a
					end)
					if not ok or not created then
						return
					end
					animator = created
				end

				-- STOP path
				if not animation then
					pcall(function()
						AnimatorUtils.stopAllDances(animator, prewarmAnimations, fade)
					end)
					restoreWalkSpeed(syncedPlayer)
					return
				end

				-- PLAY path
				-- Capacity guard: free zombie tracks before LoadAnimation to prevent
				-- silent failure at the 64-track Animator limit.
				do
					local MAX_USER_TRACKS = 52
					local tracks = animator:GetPlayingAnimationTracks()
					if #tracks >= MAX_USER_TRACKS then
						local toFree = #tracks - MAX_USER_TRACKS + 6
						local freed = 0
						-- Pass 1: destroy stopped non-Animate tracks (safe)
						for _, t in ipairs(tracks) do
							if freed >= toFree then break end
							if not t.IsPlaying and not isAnimateTrack(t) then
								pcall(function() t:Destroy() end)
								freed += 1
							end
						end
						-- Pass 2: force-stop oldest non-Animate tracks
						if freed < toFree then
							for _, t in ipairs(tracks) do
								if freed >= toFree then break end
								if not isAnimateTrack(t) then
									pcall(function()
										t:Stop(0)
										t:Destroy()
									end)
									freed += 1
								end
							end
						end
					end
				end

				local track, loadError = AnimatorUtils.getOrCreateTrack(animator, animation)
				if not track then
					assetReporter:recordInstanceFailure(
						animation,
						"SyncService.replicateAnimation",
						loadError or "Failed to load animation",
						{ player = syncedPlayer.Name, userId = syncedPlayer.UserId }
					)
					return
				end

				track.Looped = true
				track.Priority = config.ANIM_PRIORITY

				-- Matching Stop+Play fade (Roblox crossfade). Soft path clears mid-fade
				-- zombies first so rapid switches cannot stack Action4 weights.
				if type(stopFade) == "number" and stopFade > 0 then
					pcall(function()
						AnimatorUtils.prepareDanceCrossfade(animator, track, prewarmAnimations, stopFade)
					end)
				else
					pcall(function()
						AnimatorUtils.stopOtherDances(animator, track, prewarmAnimations, 0)
					end)
				end

				local function applySnap(targetTrack: AnimationTrack, phase: number): boolean
					if not targetTrack.IsPlaying then
						return false
					end
					local length = targetTrack.Length
					if type(length) == "number" and length > 0 then
						pcall(function()
							targetTrack.TimePosition = phase % length
						end)
						return true
					end
					return false
				end

				-- Cold LoadAnimation often has Length=0 for a few frames.
				local function applySnapWhenReady(targetTrack: AnimationTrack, phase: number)
					if applySnap(targetTrack, phase) then
						return
					end
					task.spawn(function()
						for _ = 1, 12 do
							if not targetTrack.Parent or not targetTrack.IsPlaying then
								return
							end
							if applySnap(targetTrack, phase) then
								return
							end
							task.wait()
						end
					end)
				end

				-- Keep fade-in. Do not Stop(0) the target track — that cancels Play fade.
				-- If the track is mid fade-out (switch-back), AdjustWeight brings it up
				-- smoothly; AdjustSpeed alone left it stuck at low weight ("not smooth").
				local function ensurePlayingWithFade(targetTrack: AnimationTrack)
					if not targetTrack.IsPlaying then
						targetTrack:Play(fade, 1, leaderSpeed)
						return
					end
					local weight = 1
					pcall(function()
						weight = targetTrack.WeightCurrent
					end)
					if weight < 0.98 then
						pcall(function()
							targetTrack:AdjustWeight(1, fade)
						end)
					end
					targetTrack:AdjustSpeed(leaderSpeed)
				end

				if type(forcedPhase) == "number" then
					ensurePlayingWithFade(track)
					applySnapWhenReady(track, forcedPhase)
				else
					ensurePlayingWithFade(track)
				end

				-- Snap follower to leader when caller did not pass timePosition.
				if type(forcedPhase) ~= "number" and syncedPlayer ~= leader and isSyncJoin then
					local snapTime: number? = nil
					if config.SYNC_JOIN_USE_LEADER_TRACK_TIME ~= false then
						snapTime = getLeaderTrackTimePosition(leader)
					end
					if snapTime == nil then
						local leaderTime = getLeaderTime(leader)
						if leaderTime > 0 then
							snapTime = leaderTime
						end
					end
					if snapTime then
						applySnapWhenReady(track, snapTime)
					end
				end

				-- Followers always run at leader's speed
				if syncedPlayer ~= leader then
					pcall(function()
						track:AdjustSpeed(leaderSpeed)
					end)
				end

				setDanceWalkSpeed(syncedPlayer)

				-- Mark Syncing attribute for non-leader members of the chain
				if syncedPlayer ~= leader and syncedPlayer.Character then
					syncedPlayer.Character:SetAttribute("Syncing", leader.Name)
				end
			end)
		end
	end
	-- ============================================================
	-- PUBLIC API
-- ============================================================
local self = {} :: any

	function self:executeAnimation(
		player: Player,
		animation: Animation,
		shouldPlay: boolean,
		speed: number,
		_intent: string?,
		_loadedAnimations: { [string]: any }?
	): Result<string>
		if not canProcessRequest(player) then
			return ResultModule.Err("rate_limited")
		end
		startProcessing(player)

		local clampedSpeed = math.clamp(tonumber(speed) or 1, config.MIN_SPEED or 0.5, config.MAX_SPEED or 2.0)
		local character = player.Character
		local animator = AnimatorUtils.getAnimator(player)
		if not animator then
			endProcessing(player)
			return ResultModule.Err("error")
		end

		-- Carried players keep limp Action4 pose; starting a dance would blend same-priority tracks.
		if shouldPlay ~= false and isBeingCarried(player) then
			endProcessing(player)
			return ResultModule.Err("carrying")
		end

		-- Detach from any leader if currently syncing (so we become our own root)
		if syncMap[player.Name] then
			unregisterSync(player.Name)
			if character then
				character:SetAttribute("Syncing", nil)
			end
			scheduleLeaderUpdate()
		end

		-- STOP request
		if shouldPlay == false then
			activeAnimations[player.Name] = nil
			activeAnimationIds[player.Name] = nil
			activeSpeeds[player.Name] = nil
			syncStartTimes[player.Name] = nil
			replicateAnimation(player, nil, { fade = FADE_OUT })
			endProcessing(player)
			return ResultModule.Ok("stopped")
		end

		if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
			endProcessing(player)
			return ResultModule.Err("error")
		end

		-- Toggle off if same animation already active
		if activeAnimations[player.Name] == animation.Name then
			activeAnimations[player.Name] = nil
			activeAnimationIds[player.Name] = nil
			activeSpeeds[player.Name] = nil
			syncStartTimes[player.Name] = nil
			replicateAnimation(player, nil, { fade = FADE_OUT })
			endProcessing(player)
			return ResultModule.Ok("stopped")
		end

		-- Play (possibly switching from another animation)
		--
		-- R5.4, R5.5: If this animation was not prewarmed, load it on demand now
		-- before committing state. This ensures the track is available and playback
		-- begins within 1s. On failure, leave dance state unchanged and return error.
		local playerPrewarmSet = prewarmSets[player.UserId]
		local animId = animation.AnimationId or ""
		local wasPrewarmed = playerPrewarmSet ~= nil
			and (playerPrewarmSet[animId] == true or playerPrewarmSet[animation.Name] == true)

		if not wasPrewarmed then
			-- Attempt on-demand load (R5.4). getOrCreateTrack is synchronous on the
			-- server (no yield) — it uses animator:LoadAnimation under pcall.
			local track, loadError = AnimatorUtils.getOrCreateTrack(animator, animation)
			if not track then
				-- R5.5: leave dance state unchanged and return error.
				logger:warn("On-demand dance track load failed", {
					player = player.Name,
					animationId = animId,
					error = loadError or "unknown",
				})
				assetReporter:recordInstanceFailure(
					animation,
					"SyncService.executeAnimation.onDemand",
					loadError or "Failed to load animation on demand",
					{ player = player.Name, userId = player.UserId }
				)
				endProcessing(player)
				return ResultModule.Err("track_load_failed")
			end
			-- Track loaded successfully; mark it as available so repeated requests
			-- don't pay the load cost again.
			if playerPrewarmSet then
				if animId ~= "" then
					playerPrewarmSet[animId] = true
				end
				playerPrewarmSet[animation.Name] = true
			end
		end

		local isSwitch = activeAnimations[player.Name] ~= nil
		activeAnimations[player.Name] = animation.Name
		activeAnimationIds[player.Name] = animation.AnimationId
		activeSpeeds[player.Name] = clampedSpeed
		if isSwitch then
			-- Matching Stop+Play fade (map-style crossfade). Anti-stack via
			-- prepareDanceCrossfade + request cooldown >= fade.
			replicateAnimation(player, animation, {
				speed = clampedSpeed,
				fade = SWITCH_FADE_IN,
				stopFade = SWITCH_FADE_OUT,
			})
		else
			replicateAnimation(player, animation, {
				speed = clampedSpeed,
				fade = FADE_IN,
				stopFade = FADE_OUT,
			})
		end

		endProcessing(player)
		return ResultModule.Ok("playing")
	end

	function self:handleSyncRequest(
		player: Player,
		targetPlayer: Player,
		condition: boolean,
		_loadedAnimations: { [string]: any }?
	): Result<string>
		if not player.Character then
			return ResultModule.Err("error")
		end

		-- UNSYNC
		if condition == false then
			if syncMap[player.Name] then
				unregisterSync(player.Name)
			end
			if player.Character then
				player.Character:SetAttribute("Syncing", nil)
			end
			activeAnimations[player.Name] = nil
			activeAnimationIds[player.Name] = nil
			activeSpeeds[player.Name] = nil
			syncStartTimes[player.Name] = nil
			-- Stop self only (not downstream) — downstream stays bound to us as new root
			local animator = AnimatorUtils.getAnimator(player)
			if animator then
				pcall(function()
					AnimatorUtils.stopAllDances(animator, prewarmAnimations, FADE_OUT)
				end)
			end
			restoreWalkSpeed(player)
			scheduleLeaderUpdate()
			return ResultModule.Ok("unsync")
		end

		-- SYNC
		if not targetPlayer or not targetPlayer.Parent or targetPlayer == player then
			return ResultModule.Err("self_target")
		end
		if not targetPlayer.Character then
			return ResultModule.Err("error")
		end

		-- Block leader from syncing into their own follower chain
		if player.Character:GetAttribute("IsLeader") == true then
			local upstream = SyncDomain.getSyncSource(targetPlayer.Name, syncMap, config.MAX_CHAIN_DEPTH or 100)
			if upstream == player.Name then
				return ResultModule.Err("leader_blocked")
			end
		end

		-- Cycle protection
		if SyncDomain.wouldCreateCircular(player.Name, targetPlayer.Name, syncMap) then
			return ResultModule.Err("circular_blocked")
		end

		-- Resolve ultimate leader of target's chain
		local ultimateName = SyncDomain.getSyncSource(targetPlayer.Name, syncMap, config.MAX_CHAIN_DEPTH or 100)
			or targetPlayer.Name
		local ultimateLeader = Players:FindFirstChild(ultimateName)
		if not ultimateLeader then
			return ResultModule.Err("error")
		end

		-- Toggle off when re-syncing to current leader
		if player.Character:GetAttribute("Syncing") == ultimateLeader.Name then
			unregisterSync(player.Name)
			player.Character:SetAttribute("Syncing", nil)
			activeAnimations[player.Name] = nil
			activeAnimationIds[player.Name] = nil
			activeSpeeds[player.Name] = nil
			syncStartTimes[player.Name] = nil
			local animator = AnimatorUtils.getAnimator(player)
			if animator then
				pcall(function()
					AnimatorUtils.stopAllDances(animator, prewarmAnimations, FADE_OUT)
				end)
			end
			restoreWalkSpeed(player)
			scheduleLeaderUpdate()
			return ResultModule.Err("unsync_success")
		end

		-- Establish bond
		registerSync(player.Name, ultimateLeader.Name)
		player.Character:SetAttribute("Syncing", ultimateLeader.Name)
		-- Player no longer their own root; clear their solo state.
		activeAnimations[player.Name] = nil
		activeAnimationIds[player.Name] = nil
		activeSpeeds[player.Name] = nil
		syncStartTimes[player.Name] = nil
		scheduleLeaderUpdate()

		-- Replicate leader's animation: soft matching fade + upfront phase snap.
		local leaderAnimName = activeAnimations[ultimateLeader.Name]
		local leaderAnimId = activeAnimationIds[ultimateLeader.Name]
		if leaderAnimName then
			local animation = findAnimation(leaderAnimName, leaderAnimId)
			if animation then
				local snapTime: number? = nil
				if config.SYNC_JOIN_USE_LEADER_TRACK_TIME ~= false then
					snapTime = getLeaderTrackTimePosition(ultimateLeader)
				end
				if snapTime == nil then
					local leaderTime = getLeaderTime(ultimateLeader)
					if leaderTime > 0 then
						snapTime = leaderTime
					end
				end
				replicateAnimation(player, animation, {
					isSyncJoin = true,
					fade = SYNC_JOIN_FADE,
					stopFade = SYNC_JOIN_FADE,
					timePosition = snapTime or 0,
				})
			else
				-- Anim resource missing locally — let client know.
				return ResultModule.Err("leader_not_dancing")
			end
		else
			-- Leader idle. Stop player's chain too.
			replicateAnimation(player, nil, { fade = FADE_OUT })
		end

		return ResultModule.Ok(ultimateLeader.Name)
	end

	-- ============================================================
	-- Transfer Lead — Lead dancer (caller dengan minimal 1 follower) hand-over
	-- kepemimpinan ke target. Seluruh subtree caller (caller + transitive
	-- followers) di-move ke target's ultimate leader, jadi rata di bawah dia.
	--
	-- Beda dari handleSyncRequest:
	--   handleSyncRequest = caller doang yang move (chain). Followers caller
	--                        tetep nempel ke caller.
	--   handleTransferLead = SELURUH subtree caller flat ke target→ultimateLeader.
	--                        Hasil: targetUltimateLeader punya followers langsung
	--                        ke seluruh anggota subtree caller.
	-- ============================================================
	function self:handleTransferLead(player: Player, targetPlayer: Player): Result<string>
		if not player.Character then
			return ResultModule.Err("error")
		end
		if not targetPlayer or not targetPlayer.Parent or targetPlayer == player then
			return ResultModule.Err("self_target")
		end
		if not targetPlayer.Character then
			return ResultModule.Err("error")
		end

		-- Caller harus actually punya followers untuk transfer. Kalau enggak,
		-- fallback ke normal sync (treat sebagai sync biasa).
		local hasFollowers = followerMap[player.Name] and next(followerMap[player.Name]) ~= nil
		if not hasFollowers then
			return self:handleSyncRequest(player, targetPlayer, true)
		end

		-- Resolve target's ultimate leader (kalau target lagi syncing ke X,
		-- transfer ke X bukan ke target).
		local ultimateName = SyncDomain.getSyncSource(targetPlayer.Name, syncMap, config.MAX_CHAIN_DEPTH or 100)
			or targetPlayer.Name
		local ultimateLeader = Players:FindFirstChild(ultimateName)
		if not ultimateLeader then
			return ResultModule.Err("error")
		end
		if ultimateLeader == player then
			-- Target's ultimate leader = caller. Artinya target ada di subtree caller.
			return ResultModule.Err("leader_blocked")
		end
		if SyncDomain.wouldCreateCircular(player.Name, ultimateLeader.Name, syncMap) then
			return ResultModule.Err("circular_blocked")
		end

		-- BFS collect seluruh subtree caller (caller + transitive followers).
		local subtreeMembers: { string } = {}
		do
			local queue: { string } = { player.Name }
			local visited: { [string]: boolean } = { [player.Name] = true }
			while #queue > 0 do
				local name = table.remove(queue, 1) :: string
				table.insert(subtreeMembers, name)
				local children = followerMap[name]
				if children then
					for childName in pairs(children) do
						if not visited[childName] then
							visited[childName] = true
							table.insert(queue, childName)
						end
					end
				end
			end
		end

		-- Move setiap member: registerSync nge-handle cleanup followerMap lama,
		-- plus clear self-leader state. Setelah loop ini followerMap caller kosong
		-- dan ultimateLeader's followerMap dapet seluruh subtree caller.
		for _, name in ipairs(subtreeMembers) do
			registerSync(name, ultimateLeader.Name)
			activeAnimations[name] = nil
			activeAnimationIds[name] = nil
			activeSpeeds[name] = nil
			syncStartTimes[name] = nil
			local member = Players:FindFirstChild(name)
			if member and member.Character then
				member.Character:SetAttribute("Syncing", ultimateLeader.Name)
			end
		end

		scheduleLeaderUpdate()

		-- Replicate leader's animation ke seluruh subtree (hard join, same as sync).
		local leaderAnimName = activeAnimations[ultimateLeader.Name]
		local leaderAnimId = activeAnimationIds[ultimateLeader.Name]
		if leaderAnimName then
			local animation = findAnimation(leaderAnimName, leaderAnimId)
			if animation then
				local snapTime: number? = nil
				if config.SYNC_JOIN_USE_LEADER_TRACK_TIME ~= false then
					snapTime = getLeaderTrackTimePosition(ultimateLeader)
				end
				if snapTime == nil then
					local leaderTime = getLeaderTime(ultimateLeader)
					if leaderTime > 0 then
						snapTime = leaderTime
					end
				end
				replicateAnimation(ultimateLeader, animation, {
					isSyncJoin = true,
					fade = SYNC_JOIN_FADE,
					stopFade = SYNC_JOIN_FADE,
					timePosition = snapTime or 0,
				})
			end
		else
			-- Leader idle: stop dance di seluruh subtree caller (yang baru di-move).
			for _, name in ipairs(subtreeMembers) do
				local member = Players:FindFirstChild(name)
				if member then
					local animator = AnimatorUtils.getAnimator(member)
					if animator then
						pcall(function()
							AnimatorUtils.stopAllDances(animator, prewarmAnimations, FADE_OUT)
						end)
					end
					restoreWalkSpeed(member)
				end
			end
		end

		return ResultModule.Ok(ultimateLeader.Name)
	end

	function self:adjustSpeed(player: Player, speed: number, _loadedAnimations: { [string]: any }?): Result<string>
		-- Followers can't change speed — they run at their leader's speed.
		if player.Character and player.Character:GetAttribute("Syncing") then
			return ResultModule.Err("syncing")
		end
		local clamped = math.clamp(tonumber(speed) or 1, config.MIN_SPEED or 0.5, config.MAX_SPEED or 2.0)
		if not activeAnimations[player.Name] then
			-- Not actively dancing; record speed for next play but no track to adjust.
			activeSpeeds[player.Name] = clamped
			return ResultModule.Ok("speed_changed")
		end

		-- Re-anchor start time so getLeaderTime stays continuous after speed change.
		local prevStart = syncStartTimes[player.Name] or tick()
		local prevSpeed = activeSpeeds[player.Name] or 1
		local elapsed = (tick() - prevStart) * prevSpeed
		activeSpeeds[player.Name] = clamped
		syncStartTimes[player.Name] = tick() - (elapsed / clamped)

		-- Apply to player + transitive followers
		for _, entry in ipairs(findSyncedPlayers(player)) do
			local p = entry.player
			local humanoid = entry.humanoid
			if humanoid then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if animator then
					local track = AnimatorUtils.getPlayingDanceTrack(animator, prewarmAnimations)
					if track then
						pcall(function()
							track:AdjustSpeed(clamped)
						end)
					end
				end
			end
			-- Avoid unused-var lint
			local _ = p
		end
		return ResultModule.Ok("speed_changed")
	end

	function self:onPlayerAdded(player: Player)
		if characterConnections[player.UserId] then
			characterConnections[player.UserId]:Disconnect()
		end
		characterConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			self:onCharacterAdded(player, character)
		end)
	end

	function self:onPlayerRemoving(player: Player)
		local affectedFollowerNames: { string } = {}
		local followers = followerMap[player.Name]
		if followers then
			for followerName in pairs(followers) do
				table.insert(affectedFollowerNames, followerName)
				local follower = Players:FindFirstChild(followerName)
				if follower then
					local animator = AnimatorUtils.getAnimator(follower)
					if animator then
						pcall(function()
							AnimatorUtils.stopAllDances(animator, prewarmAnimations, FADE_OUT)
						end)
					end
					if follower.Character then
						follower.Character:SetAttribute("Syncing", nil)
					end
					restoreWalkSpeed(follower)
				end
				syncMap[followerName] = nil
			end
			followerMap[player.Name] = nil
		end

		unregisterSync(player.Name)
		activeAnimations[player.Name] = nil
		activeAnimationIds[player.Name] = nil
		activeSpeeds[player.Name] = nil
		syncStartTimes[player.Name] = nil
		processingRequests[player.UserId] = nil
		lastRequestTime[player.UserId] = nil
		originalWalkSpeeds[player.UserId] = nil
		pendingRefreshRestore[player.UserId] = nil
		prewarmSets[player.UserId] = nil
		bumpPrewarmGeneration(player.UserId)

		if characterConnections[player.UserId] then
			characterConnections[player.UserId]:Disconnect()
			characterConnections[player.UserId] = nil
		end

		scheduleLeaderUpdate()

		if #affectedFollowerNames > 0 then
			return { leaderName = player.Name, followerNames = affectedFollowerNames }
		end
		return nil
	end

	function self:onCharacterAdded(player: Player, character: Model)
		originalWalkSpeeds[player.UserId] = nil
		AnimatorUtils.clearCacheForPlayer(player)

		-- If respawn happens during a managed /re refresh, leave state alone.
		-- restorePreparedRefresh will rehydrate everything in a moment.
		if pendingRefreshRestore[player.UserId] ~= nil then
			scheduleLeaderUpdate()
			return
		end

		-- Natural respawn: cut every bond cleanly so neither the player nor
		-- their followers get stuck on stale animations.
		if character then
			character:SetAttribute("Syncing", nil)
		end

		local hadFollowers = followerMap[player.Name] ~= nil
		local followerNames: { string } = {}
		if hadFollowers then
			for followerName in pairs(followerMap[player.Name] :: any) do
				table.insert(followerNames, followerName)
			end
		end

		-- Clear leader state for this player
		activeAnimations[player.Name] = nil
		activeAnimationIds[player.Name] = nil
		activeSpeeds[player.Name] = nil
		syncStartTimes[player.Name] = nil

		-- Cut downstream
		if hadFollowers then
			for _, followerName in ipairs(followerNames) do
				local follower = Players:FindFirstChild(followerName)
				if follower then
					local animator = AnimatorUtils.getAnimator(follower)
					if animator then
						pcall(function()
							AnimatorUtils.stopAllDances(animator, prewarmAnimations, FADE_OUT)
						end)
					end
					if follower.Character then
						follower.Character:SetAttribute("Syncing", nil)
					end
					restoreWalkSpeed(follower)
				end
				syncMap[followerName] = nil
			end
			followerMap[player.Name] = nil
		end

		-- Cut upstream (in case this player was a follower)
		unregisterSync(player.Name)
		scheduleLeaderUpdate()

		if #followerNames > 0 and onFollowersHardUnsyncedCallback then
			local ok, err = pcall(onFollowersHardUnsyncedCallback, player.Name, followerNames)
			if not ok then
				logger:warn("Hard unsync callback failed", { error = tostring(err) })
			end
		end

		-- Clear prewarm set for this character; prewarmAnimatorTracks will rebuild it.
		prewarmSets[player.UserId] = nil

		prewarmAnimatorTracks(player)
	end

	function self:setOnFollowersHardUnsynced(callback: (leaderName: string, followerNames: { string }) -> ())
		onFollowersHardUnsyncedCallback = callback
	end

	-- ============================================================
	-- /re REFRESH SUPPORT
	-- ============================================================
	function self:prepareRefreshRestore(player: Player)
		local character = player.Character
		local animator = AnimatorUtils.getAnimator(player)
		if not character or not animator then
			pendingRefreshRestore[player.UserId] = nil
			return
		end

		local track, animationName = AnimatorUtils.getPlayingDanceTrack(animator, prewarmAnimations)
		if not track then
			pendingRefreshRestore[player.UserId] = nil
			return
		end

		local animationId = ""
		local speed = config.DEFAULT_SPEED or 1
		pcall(function()
			animationId = if track.Animation then track.Animation.AnimationId else ""
			speed = track.Speed
		end)

		pendingRefreshRestore[player.UserId] = {
			animationName = animationName,
			animationId = animationId,
			timePosition = track.TimePosition,
			speed = speed,
			syncing = character:GetAttribute("Syncing"),
			isLeader = character:GetAttribute("IsLeader"),
			followerCount = character:GetAttribute("FollowerCount"),
		}
	end

	function self:restorePreparedRefresh(player: Player)
		local snapshot = pendingRefreshRestore[player.UserId]
		pendingRefreshRestore[player.UserId] = nil
		if not snapshot then
			return
		end

		local character = player.Character
		if not character then
			return
		end
		character:SetAttribute("Syncing", snapshot.syncing)
		character:SetAttribute("IsLeader", snapshot.isLeader)
		character:SetAttribute("FollowerCount", snapshot.followerCount)

		if not snapshot.animationName then
			return
		end
		local animationName: string = snapshot.animationName
		local animationId: string = snapshot.animationId or ""

		local animation = findAnimation(animationName, animationId)
		if not animation then
			return
		end

		-- ApplyDescription can invalidate cached tracks — drop cache before replay.
		AnimatorUtils.clearCacheForPlayer(player)

		-- Dance needs Animator, not Head. Wait briefly so /re restore does not
		-- one-shot nil when Animator lags Humanoid by a frame.
		local animator = AnimatorUtils.getAnimator(player)
		if not animator then
			local snap = CharacterReady.wait(player, "anim", 5)
			animator = if snap then snap.animator else AnimatorUtils.getAnimator(player)
		end
		if not animator then
			return
		end

		local phase = tonumber(snapshot.timePosition) or 0
		local speed = tonumber(snapshot.speed) or (config.DEFAULT_SPEED or 1)

		-- If not following anyone, this player is a root leader — re-anchor
		-- timing and re-replicate to followers (if any) so they snap back in-phase.
		if not snapshot.syncing then
			activeAnimations[player.Name] = animationName
			activeAnimationIds[player.Name] = animationId
			activeSpeeds[player.Name] = speed
			syncStartTimes[player.Name] = tick() - (phase / math.max(speed, 0.01))
			replicateAnimation(player, animation, {
				speed = speed,
				fade = 0,
				stopFade = 0,
				timePosition = phase,
			})
		else
			-- Restored as follower. Prefer live leader phase (salon-continuous sync).
			local syncingName = if type(snapshot.syncing) == "string" then snapshot.syncing else nil
			local leader = if syncingName then Players:FindFirstChild(syncingName) else nil
			if leader then
				replicateAnimation(player, animation, {
					isSyncJoin = true,
					fade = 0,
					stopFade = 0,
				})
			else
				-- Leader gone — fall back to playing solo at saved phase.
				activeAnimations[player.Name] = animationName
				activeAnimationIds[player.Name] = animationId
				activeSpeeds[player.Name] = speed
				syncStartTimes[player.Name] = tick() - (phase / math.max(speed, 0.01))
				character:SetAttribute("Syncing", nil)
				replicateAnimation(player, animation, {
					speed = speed,
					fade = 0,
					stopFade = 0,
					timePosition = phase,
				})
			end
		end
	end

	function self:clearPreparedRefresh(player: Player)
		pendingRefreshRestore[player.UserId] = nil
	end

	-- ============================================================
	-- AFK REJOIN SUPPORT (TeleportData snapshot + post-join restore)
	-- ============================================================
	function self:captureSyncSnapshotForTeleport(player: Player): any?
		local character = player.Character
		local animator = AnimatorUtils.getAnimator(player)
		if not character or not animator then
			return nil
		end

		local track, animationName = AnimatorUtils.getPlayingDanceTrack(animator, prewarmAnimations)
		local syncingName = character:GetAttribute("Syncing")
		local wasSyncing = type(syncingName) == "string" and syncingName ~= ""

		local lastLeaderUserId: number? = nil
		if wasSyncing then
			local leader = Players:FindFirstChild(syncingName :: string)
			if leader and leader:IsA("Player") then
				lastLeaderUserId = leader.UserId
			end
		end

		if not track and not wasSyncing then
			return nil
		end

		local animationId: string? = nil
		local speed = config.DEFAULT_SPEED or 1
		local timePosition = 0
		if track then
			pcall(function()
				local rawId = if track.Animation then track.Animation.AnimationId else ""
				if type(rawId) == "string" and rawId ~= "" then
					animationId = rawId
				end
				speed = track.Speed
				timePosition = track.TimePosition
			end)
		end

		return {
			wasSyncing = wasSyncing,
			lastLeaderUserId = lastLeaderUserId,
			animationName = animationName,
			animationId = animationId,
			timePosition = timePosition,
			speed = speed,
			isLeader = character:GetAttribute("IsLeader") == true,
		}
	end

	function self:getTopLeaderByFollowerCount(excludeUserId: number?): Player?
		local afkConfig = Config.AfkGuard or {}
		local requireDancing = afkConfig.SYNC_REQUIRE_LEADER_DANCING == true

		local bestLeader: Player? = nil
		local bestCount = 0
		local bestUserId = math.huge

		for leaderName, followers in pairs(followerMap) do
			local count = 0
			for _ in pairs(followers) do
				count += 1
			end
			if count <= 0 then
				continue
			end

			local leader = Players:FindFirstChild(leaderName)
			if not leader or not leader:IsA("Player") or not leader.Character then
				continue
			end
			if excludeUserId and leader.UserId == excludeUserId then
				continue
			end
			if requireDancing and not activeAnimations[leaderName] then
				continue
			end

			if count > bestCount or (count == bestCount and leader.UserId < bestUserId) then
				bestCount = count
				bestLeader = leader
				bestUserId = leader.UserId
			end
		end

		return bestLeader
	end

	local function restoreSoloAnimation(player: Player, snapshot: any)
		local character = player.Character
		if not character or not snapshot.animationName then
			return
		end

		local animationName: string = snapshot.animationName
		local animationId: string = snapshot.animationId or ""
		local animation = findAnimation(animationName, animationId)
		if not animation then
			return
		end

		local animator = AnimatorUtils.getAnimator(player)
		if not animator then
			return
		end

		activeAnimations[player.Name] = animationName
		activeAnimationIds[player.Name] = animationId
		activeSpeeds[player.Name] = snapshot.speed
		syncStartTimes[player.Name] = tick() - (snapshot.timePosition / math.max(snapshot.speed, 0.01))
		character:SetAttribute("Syncing", nil)
		replicateAnimation(player, animation, { speed = snapshot.speed, fade = 0 })
	end

	local function isLeaderEligible(leader: Player): boolean
		if not leader.Parent or not leader.Character then
			return false
		end
		local afkConfig = Config.AfkGuard or {}
		if afkConfig.SYNC_REQUIRE_LEADER_DANCING == true and not activeAnimations[leader.Name] then
			return false
		end
		return true
	end

	function self:restoreAfterAfkRejoin(
		player: Player,
		syncRestore: any,
		options: {
			fireSyncNotification: ((player: Player, payload: { [string]: any }) -> ())?,
			notifyPlayer: ((player: Player, message: string, kind: string?) -> ())?,
		}?
	)
		local validated = AfkGuardDomain.validateSyncRestorePayload(syncRestore)
		if not validated.ok then
			logger:warn("afk_restore_sync_invalid", {
				player = player.Name,
				userId = player.UserId,
				error = validated.error,
			})
			return
		end

		local snapshot = validated.value
		local afkConfig = Config.AfkGuard or {}
		local notifyPlayer = options and options.notifyPlayer
		local fireSyncNotification = options and options.fireSyncNotification

		local function fireSyncSuccess(leaderName: string, targetUserId: number)
			if fireSyncNotification then
				fireSyncNotification(player, {
					type = "sync_success",
					leaderName = leaderName,
					leaderDisplay = self:getLeaderDisplayName(leaderName),
					currentAnim = self:getCurrentAnimationName(leaderName),
					targetUserId = targetUserId,
				})
			end
		end

		if not snapshot.wasSyncing then
			restoreSoloAnimation(player, snapshot)
			logger:info("afk_restore_sync_solo_fallback", {
				player = player.Name,
				userId = player.UserId,
				reason = "not_syncing",
			})
			return
		end

		local lastLeader: Player? = nil
		if snapshot.lastLeaderUserId then
			lastLeader = Players:GetPlayerByUserId(snapshot.lastLeaderUserId)
		end

		if lastLeader and isLeaderEligible(lastLeader) then
			local result = self:handleSyncRequest(player, lastLeader, true)
			if result.ok then
				fireSyncSuccess(result.value, lastLeader.UserId)
				if notifyPlayer then
					notifyPlayer(
						player,
						string.format(afkConfig.MSG_SYNC_RESTORED or "[Session] Synced back to %s.", self:getLeaderDisplayName(result.value)),
						"SUCCESS"
					)
				end
				logger:info("afk_restore_sync_last_leader", {
					player = player.Name,
					userId = player.UserId,
					leaderUserId = lastLeader.UserId,
				})
				return
			end
		end

		if afkConfig.SYNC_FALLBACK_TOP_LEADER == true then
			local topLeader = self:getTopLeaderByFollowerCount(player.UserId)
			if topLeader and isLeaderEligible(topLeader) then
				local result = self:handleSyncRequest(player, topLeader, true)
				if result.ok then
					fireSyncSuccess(result.value, topLeader.UserId)
					if notifyPlayer then
						local oldLeaderName = if lastLeader then lastLeader.DisplayName else "Your leader"
						notifyPlayer(
							player,
							string.format(
								afkConfig.MSG_SYNC_FALLBACK or "[Session] %s left — synced to %s.",
								oldLeaderName,
								self:getLeaderDisplayName(result.value)
							),
							"INFO"
						)
					end
					logger:info("afk_restore_sync_top_leader", {
						player = player.Name,
						userId = player.UserId,
						leaderUserId = topLeader.UserId,
					})
					return
				end
			end
		end

		restoreSoloAnimation(player, snapshot)
		if notifyPlayer then
			notifyPlayer(player, afkConfig.MSG_SYNC_SOLO or "[Session] Rejoined. Dance sync could not be restored.", "INFO")
		end
		logger:info("afk_restore_sync_solo_fallback", {
			player = player.Name,
			userId = player.UserId,
		})
	end

	-- ============================================================
	-- HELPERS USED BY SyncController FOR sync_success NOTIFICATION
	-- ============================================================
	function self:getLeaderDisplayName(leaderName: string?): string
		if type(leaderName) ~= "string" or leaderName == "" then
			return "target"
		end
		local leader = Players:FindFirstChild(leaderName)
		return leader and leader.DisplayName or leaderName
	end

	function self:getCurrentAnimationName(leaderName: string?): string?
		if type(leaderName) ~= "string" or leaderName == "" then
			return nil
		end
		return activeAnimations[leaderName]
	end

	function self:getAssetReports()
		return assetReporter:getReports()
	end

	-- Periodic track scavenger: cleanup zombie tracks every 120s.
	-- Catches tracks from paths that never go through getOrCreateTrack
	-- or replicateAnimation (emotes, carry, plugins).
	local _scavengeActive = true
	local _scavengeThread: thread? = nil
	local SCAVENGE_INTERVAL = 120

	local function scavengeTracks()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then continue end
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then continue end

			local success, tracks = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if not success or #tracks <= 50 then continue end

			logger:warn("Track count high, scavenging", {
				player = player.Name,
				count = #tracks,
			})

			local destroyed = 0
			for _, t in ipairs(tracks) do
				if not t.IsPlaying and not isAnimateTrack(t) then
					pcall(function() t:Destroy() end)
					destroyed += 1
				end
			end

			if destroyed > 0 then
				logger:warn("Scavenged zombie tracks", {
					player = player.Name,
					destroyed = destroyed,
				})
			end
		end
	end

	_scavengeThread = task.spawn(function()
		-- Loop berhenti ketika _scavengeActive di-flip oleh destroy() (dipanggil
		-- dari script.Destroying di Main.server). Tanpa ini, setiap hot-reload
		-- menumpuk thread scavenge baru yang reference closure lama.
		while _scavengeActive do
			task.wait(SCAVENGE_INTERVAL)
			if _scavengeActive then
				scavengeTracks()
			end
		end
	end)

	function self:destroy()
		_scavengeActive = false
		if _scavengeThread then
			task.cancel(_scavengeThread)
			_scavengeThread = nil
		end
	end

	return self :: SyncService
end

return create
