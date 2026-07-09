--!strict
-- ServerScriptService/Server/Services/PlayerSnapshotService.luau
--
-- In-memory snapshot per userId for fast ACM data lookup.
-- Updated on: overhead broadcast, profile save/load, like toggle, social warm.
-- Query method for AvatarContextService to avoid calling full OverheadService:buildPayload.
--
-- This service acts as a central cache that aggregates data from multiple sources
-- so ACM can retrieve pre-computed data in <50ms instead of triggering 4+ parallel
-- DataStore/API calls each time a player clicks an avatar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)

type OverheadPayload = Types.OverheadPayload
type SocialProofData = Types.SocialProofData
type ILogger = Types.ILogger

export type PlayerSnapshot = {
	userId: number,
	displayName: string?,
	username: string?,
	role: string?,
	effectiveMembership: string?,
	visibleBadges: { string }?,
	streakDays: number?,
	couplePartner: string?,
	isCoupled: boolean?,
	showCoupleName: boolean?,
	communityId: number?,
	communityName: string?,
	communityLogo: string?,
	likesCount: number?,
	robuxDonated: number?,
	cashDonated: number?,
	topDonateRank: number?,
	topSpenderRank: number?,
	relationshipMode: string?,
	statusText: string?,
	followersCount: number?,
	connectionsCount: number?,
	updatedAt: number,
}

export type PlayerSnapshotService = {
	getSnapshot: (self: PlayerSnapshotService, userId: number) -> PlayerSnapshot?,
	updateFromOverhead: (self: PlayerSnapshotService, payload: OverheadPayload) -> (),
	updateFromSocial: (self: PlayerSnapshotService, userId: number, social: SocialProofData) -> (),
	updateLikesCount: (self: PlayerSnapshotService, userId: number, likesCount: number) -> (),
	invalidate: (self: PlayerSnapshotService, userId: number) -> (),
	onPlayerRemoving: (self: PlayerSnapshotService, player: Player) -> (),
	subscribeSnapshotUpdated: (self: PlayerSnapshotService, callback: (userId: number) -> ()) -> () -> (),
	destroy: (self: PlayerSnapshotService) -> (),
}

local function createPlayerSnapshotService(deps: {
	logger: ILogger?,
}?): PlayerSnapshotService
	local log = if deps and deps.logger then deps.logger else Logger.new("PlayerSnapshotService")
	
	local snapshots: { [number]: PlayerSnapshot } = {}
	local listeners: { (userId: number) -> () } = {}
	local cleaner = Cleaner.new()
	
	local service = {} :: PlayerSnapshotService
	
	local function notifyListeners(userId: number)
		for _, listener in ipairs(listeners) do
			task.defer(listener, userId)
		end
	end
	
	local function ensureSnapshot(userId: number): PlayerSnapshot
		local existing = snapshots[userId]
		if existing then
			return existing
		end
		
		local snapshot: PlayerSnapshot = {
			userId = userId,
			updatedAt = os.clock(),
		}
		snapshots[userId] = snapshot
		return snapshot
	end
	
	function service:getSnapshot(userId: number): PlayerSnapshot?
		return snapshots[userId]
	end
	
	function service:updateFromOverhead(payload: OverheadPayload)
		local userId = payload.userId
		if not userId or userId <= 0 then
			return
		end
		
		local snapshot = ensureSnapshot(userId)
		
		snapshot.displayName = payload.displayName
		snapshot.role = payload.role
		snapshot.effectiveMembership = payload.effectiveMembership
		snapshot.visibleBadges = payload.visibleBadges
		snapshot.streakDays = payload.streakDays
		snapshot.couplePartner = payload.couplePartner
		snapshot.isCoupled = payload.isCoupled
		snapshot.showCoupleName = payload.showCoupleName
		snapshot.communityId = payload.communityId
		snapshot.communityName = payload.communityName
		snapshot.communityLogo = payload.communityLogo
		snapshot.likesCount = payload.likesCount
		snapshot.robuxDonated = payload.robuxDonated
		snapshot.cashDonated = payload.cashDonated
		snapshot.topDonateRank = payload.topDonateRank
		snapshot.topSpenderRank = payload.topSpenderRank
		snapshot.relationshipMode = payload.relationshipMode
		snapshot.statusText = payload.statusText
		snapshot.updatedAt = os.clock()
		
		local player = Players:GetPlayerByUserId(userId)
		if player then
			snapshot.username = player.Name
		end
		
		log:debug("Snapshot updated from overhead", {
			userId = userId,
			role = payload.role,
		})
		
		notifyListeners(userId)
	end
	
	function service:updateFromSocial(userId: number, social: SocialProofData)
		if not userId or userId <= 0 then
			return
		end
		
		local snapshot = ensureSnapshot(userId)
		
		if social.followersCount ~= nil then
			snapshot.followersCount = social.followersCount
		end
		if social.connectionsCount ~= nil then
			snapshot.connectionsCount = social.connectionsCount
		end
		snapshot.updatedAt = os.clock()
		
		log:debug("Snapshot updated from social", {
			userId = userId,
			connectionsCount = social.connectionsCount,
		})
		
		notifyListeners(userId)
	end
	
	function service:updateLikesCount(userId: number, likesCount: number)
		if not userId or userId <= 0 then
			return
		end
		
		local snapshot = ensureSnapshot(userId)
		snapshot.likesCount = likesCount
		snapshot.updatedAt = os.clock()
		
		log:debug("Snapshot likes updated", {
			userId = userId,
			likesCount = likesCount,
		})
		
		notifyListeners(userId)
	end
	
	function service:invalidate(userId: number)
		snapshots[userId] = nil
		log:debug("Snapshot invalidated", { userId = userId })
	end
	
	function service:onPlayerRemoving(player: Player)
		snapshots[player.UserId] = nil
	end
	
	function service:subscribeSnapshotUpdated(callback: (userId: number) -> ()): () -> ()
		table.insert(listeners, callback)
		return function()
			local index = table.find(listeners, callback)
			if index then
				table.remove(listeners, index)
			end
		end
	end
	
	cleaner:add(Players.PlayerRemoving:Connect(function(player)
		service:onPlayerRemoving(player)
	end))
	
	function service:destroy()
		cleaner:clean()
		table.clear(snapshots)
		table.clear(listeners)
	end
	
	log:info("PlayerSnapshotService initialized")
	
	return service
end

return {
	create = createPlayerSnapshotService,
}
