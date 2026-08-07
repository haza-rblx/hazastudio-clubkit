--!strict
-- Server/Services/CoupleService.lua
-- Couple business logic. Zero direct DataStore access, zero UI, zero Remote.
local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
-- Use the ReplicatedStorage local variable, not game.ReplicatedStorage
local Config       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types        = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local CoupleDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CoupleDomain)
local ResultUtil   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
type Result<T>           = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository
type PendingRequest = {
	fromUserId   : number,
	fromName     : string,
	fromUsername : string,
	requestId    : string,
	expiredAt    : number,
}
local function createCoupleService(deps: {
	repo : IOverheadRepository,
	})
	local repo = deps.repo
	local log  = Logger.new("CoupleService")

	-- Flipped to true by service:destroy(). The long-background rollback/breakup
	-- retry chains (up to 80s) check this before each attempt so teardown does
	-- not keep hammering a repo that is already shutting down.
	local _destroyed = false

	-- Budget guard: check whether enough UpdateAsync budget before entering
	-- 2-step transaction. Without this, target already committed but sender dropped in queue,
	-- creating half-coupled state users report as "couple gone after refresh".
	local function hasUpdateBudget(minBudget: number): boolean
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		return ok and type(budget) == "number" and budget >= minBudget
	end

	-- Robust rollback with long exponential backoff in background.
	-- repo:update already retries 3x (~14s), but when queue is saturated 14s is often
	-- not enough. Background retry up to 4 attempts (10s, 20s, 40s, 80s)
	-- prevents permanent half-committed state.
	local function rollbackCoupleAsync(userId: number, partnerName: string?)
		task.spawn(function()
			local delays = { 10, 20, 40, 80 }
			for attempt, waitSec in ipairs(delays) do
				if _destroyed then
					return
				end
				local result = repo:update(userId, function(current)
					return CoupleDomain.removeCouple(current)
				end)
				if result.ok then
					log:warn("Couple rollback eventually succeeded", {
						userId = userId,
						attempt = attempt,
					})
					return
				end
				if _destroyed then
					return
				end
				log:warn("Couple rollback retry pending", {
					userId = userId,
					attempt = attempt,
					nextDelay = waitSec,
					err = result.error,
				})
				task.wait(waitSec)
			end
			if not _destroyed then
				log:error("CRITICAL: Couple rollback failed completely, manual intervention required", {
					userId = userId,
					partnerName = partnerName,
				})
			end
		end)
	end

	local function clearPartnerCoupleAsync(partnerUserId: number, context: string)
		task.spawn(function()
			local delays = { 2, 5, 10, 20 }
			for attempt, waitSec in ipairs(delays) do
				if _destroyed then
					return
				end
				local result = repo:update(partnerUserId, function(current)
					return CoupleDomain.removeCouple(current)
				end)
				if result.ok then
					if attempt > 1 then
						log:info("Partner breakup retry succeeded", {
							partnerId = partnerUserId,
							attempt = attempt,
							context = context,
						})
					end
					return
				end
				if _destroyed then
					return
				end
				log:warn("Partner breakup retry pending", {
					partnerId = partnerUserId,
					attempt = attempt,
					nextDelay = waitSec,
					context = context,
					err = result.error,
				})
				task.wait(waitSec)
			end
			if not _destroyed then
				log:error("CRITICAL: Partner breakup failed after retries", {
					partnerId = partnerUserId,
					context = context,
				})
			end
		end)
	end
	-- Pending requests in memory — no need to persist to DataStore
	-- Key: targetUserId, Value: { fromUserId, fromName, fromUsername, requestId, expiredAt }
	local pendingRequests: {[number]: PendingRequest} = {}
	-- Clean up expired requests every 30 seconds
	-- Thread stored so it can be cancelled via service:destroy()
	local cleanupThread = task.spawn(function()
		while true do
			task.wait(30)
			local now = os.time()
			for targetId, req in pairs(pendingRequests) do
				if now >= req.expiredAt then
					pendingRequests[targetId] = nil
					log:debug("Request expired", { targetId = targetId })
				end
			end
		end
	end)
	local service = {}
	-- ----------------------------------------------------------
	-- sendRequest — send couple request from sender to target
	-- ----------------------------------------------------------
	function service:sendRequest(
		sender        : Player,
		target        : Player,
		requestId     : string
	): Result<nil>
		-- Cannot couple with yourself
		if sender.UserId == target.UserId then
			return ResultUtil.Err(Config.Couple.MSG_SELF)
		end
		-- Check sender already has couple
		local senderStored = repo:load(sender.UserId)
		if not senderStored.ok then
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		if CoupleDomain.isCoupled(senderStored.value) then
			return ResultUtil.Err(Config.Couple.MSG_ALREADY_COUPLED)
		end
		-- Check sender already has pending request
		for _, req in pairs(pendingRequests) do
			if req.fromUserId == sender.UserId then
				return ResultUtil.Err(Config.Couple.MSG_REQUEST_PENDING)
			end
		end
		-- Check target already has couple
		local targetStored = repo:load(target.UserId)
		if not targetStored.ok then
			return ResultUtil.Err("[Couple] I could not load that player's couple data. Try again.")
		end
		if CoupleDomain.isCoupled(targetStored.value) then
			return ResultUtil.Err(Config.Couple.MSG_TARGET_COUPLED)
		end
		-- Store pending request
		pendingRequests[target.UserId] = {
			fromUserId   = sender.UserId,
			fromName     = sender.DisplayName,
			fromUsername = sender.Name,
			requestId    = requestId,
			expiredAt    = os.time() + Config.Couple.REQUEST_TIMEOUT,
		}
		log:info("Request sent", { from = sender.Name, to = target.Name })
		return ResultUtil.Ok(nil)
	end
	-- ----------------------------------------------------------
	-- acceptRequest - target accept request from sender
	-- Move all validation into UpdateAsync mutator
	-- atomic with no race condition
	-- ----------------------------------------------------------
	function service:acceptRequest(
		target    : Player,
		requestId : string
	): Result<{ senderUserId: number, senderName: string }>
		local req = pendingRequests[target.UserId]
		if not req or req.requestId ~= requestId then
			return ResultUtil.Err("[Couple] That request is gone or already expired.")
		end
		if os.time() >= req.expiredAt then
			pendingRequests[target.UserId] = nil
			return ResultUtil.Err("[Couple] That request already expired.")
		end

		-- Refuse if budget too low. acceptRequest needs 2 UpdateAsync
		-- (target + sender) plus rollback budget if salah satu fail.
		-- Fail fast with a clear message rather than entering a half-committed state.
		if not hasUpdateBudget(4) then
			log:warn("acceptRequest refused: low DataStore budget", {
				target = target.Name,
				sender = req.fromName,
			})
			return ResultUtil.Err("[Couple] Server is busy right now. Try again in a few seconds.")
		end

		local senderUserId = req.fromUserId
		local senderName   = req.fromName
		local targetName   = target.DisplayName
		-- Save target with validation inside mutator (atomic)
		local saveTarget = repo:update(target.UserId, function(current)
			-- Validate inside mutator for atomicity
			if CoupleDomain.isCoupled(current) then
				-- If already coupled, return current state unchanged
				-- UpdateAsync returns nil and we can detect this
				return current
			end
			return CoupleDomain.applyCouple(current, senderName, senderUserId)
		end)

		if not saveTarget.ok then
			return ResultUtil.Err("[Couple] Could not save that player's couple data. Try again.")
		end
		-- Check whether target already coupled (validation failed in mutator)
		if CoupleDomain.isCoupled(saveTarget.value) and saveTarget.value.couplePartnerId ~= senderUserId then
			-- Target already coupled with someone else (race condition detected)
			return ResultUtil.Err(Config.Couple.MSG_TARGET_COUPLED)
		end
		-- Save sender with validation inside mutator (atomic)
		local saveSender = repo:update(senderUserId, function(current)
			-- Validate inside mutator for atomicity
			if CoupleDomain.isCoupled(current) then
				return current
			end
			return CoupleDomain.applyCouple(current, targetName, target.UserId)
		end)

		if not saveSender.ok then
			-- Rollback target if sender failed. Use long background retry
			-- so when queue clears, rollback still commits and state does not
			-- stuck in a half-coupled state.
			rollbackCoupleAsync(target.UserId, senderName)
			return ResultUtil.Err("[Couple] Could not save your couple data. Try again.")
		end
		-- Check whether sender already coupled (validation failed in mutator)
		if CoupleDomain.isCoupled(saveSender.value) and saveSender.value.couplePartnerId ~= target.UserId then
			-- Sender already coupled with someone else (race condition detected)
			-- Rollback target with long retry
			rollbackCoupleAsync(target.UserId, senderName)
			return ResultUtil.Err(Config.Couple.MSG_ALREADY_COUPLED)
		end
		-- Hapus pending request
		pendingRequests[target.UserId] = nil
		log:info("Couple formed", { sender = senderName, target = target.Name })
		return ResultUtil.Ok({ senderUserId = senderUserId, senderName = senderName })
	end
	-- ----------------------------------------------------------
	-- rejectRequest - target reject request
	-- ----------------------------------------------------------
	function service:rejectRequest(
		target    : Player,
		requestId : string
	): Result<{ senderUserId: number }>
		local req = pendingRequests[target.UserId]
		if not req or req.requestId ~= requestId then
			return ResultUtil.Err("[Couple] That request is no longer available.")
		end
		local senderUserId = req.fromUserId
		pendingRequests[target.UserId] = nil
		log:info("Request rejected", { from = req.fromName, by = target.Name })
		return ResultUtil.Ok({ senderUserId = senderUserId })
	end
	-- ----------------------------------------------------------
	-- breakup — remove couple from both players
	-- ----------------------------------------------------------
	function service:breakup(player: Player): Result<{ partnerUserId: number? }>
		local stored = repo:load(player.UserId)
		if not stored.ok then
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		if not CoupleDomain.isCoupled(stored.value) then
			return ResultUtil.Err(Config.Couple.MSG_NO_COUPLE)
		end

		local partnerIdFromStore = stored.value.couplePartnerId
		local partnerNameFromStore = stored.value.couplePartner

		local saveResult = repo:update(player.UserId, function(current)
			return CoupleDomain.removeCouple(current)
		end)
		if not saveResult.ok then
			return ResultUtil.Err("[Couple] Could not save the breakup. Try again.")
		end

		local resolvedPartnerId = partnerIdFromStore
		if not resolvedPartnerId and partnerNameFromStore then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Name == partnerNameFromStore or p.DisplayName == partnerNameFromStore then
					resolvedPartnerId = p.UserId
					break
				end
			end
		end
		if resolvedPartnerId ~= nil and resolvedPartnerId ~= player.UserId then
			local savePartner = repo:update(resolvedPartnerId, function(current)
				return CoupleDomain.removeCouple(current)
			end)
			if not savePartner.ok then
				log:warn("Breakup partner save failed — scheduling retry", {
					player = player.Name,
					partnerId = resolvedPartnerId,
					err = savePartner.error,
				})
				clearPartnerCoupleAsync(resolvedPartnerId, "breakup")
			end
		end

		log:info("Breakup", { player = player.Name, partnerId = resolvedPartnerId })
		return ResultUtil.Ok({ partnerUserId = resolvedPartnerId })
	end
	-- ----------------------------------------------------------
	-- breakupBoth — remove couple from both players at once
	-- Use couplePartnerId from DataStore so breakup works even if partner offline
	-- ----------------------------------------------------------
	function service:breakupBoth(playerA: Player): Result<nil>
		local storedA = repo:load(playerA.UserId)
		if not storedA.ok then
			log:error("Failed to load breakup data", { err = storedA.error })
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		if not CoupleDomain.isCoupled(storedA.value) then
			return ResultUtil.Err(Config.Couple.MSG_NO_COUPLE)
		end
		local partnerIdFromStore   = storedA.value.couplePartnerId
		local partnerNameFromStore = storedA.value.couplePartner
		-- Hapus couple from player A
		local saveA = repo:update(playerA.UserId, function(current)
			return CoupleDomain.removeCouple(current)
		end)
		if not saveA.ok then
			log:error("Failed to save breakup playerA", { err = saveA.error })
			return ResultUtil.Err("[Couple] Breakup could not be saved. Try again.")
		end
		-- Resolve partnerId — prefer couplePartnerId from DataStore (primary key)
		-- Fallback to name lookup only if couplePartnerId nil (legacy data)
		local resolvedPartnerId = partnerIdFromStore
		if not resolvedPartnerId and partnerNameFromStore then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Name == partnerNameFromStore or p.DisplayName == partnerNameFromStore then
					resolvedPartnerId = p.UserId
					break
				end
			end
		end
		if resolvedPartnerId ~= nil then
			local saveB = repo:update(resolvedPartnerId, function(current)
				return CoupleDomain.removeCouple(current)
			end)
			if not saveB.ok then
				log:error("Failed to save breakup partner — scheduling retry", {
					partnerId = resolvedPartnerId,
					err = saveB.error,
				})
				clearPartnerCoupleAsync(resolvedPartnerId, "breakupBoth")
			end
		else
			log:warn("Partner not found when breakup", { partnerName = tostring(partnerNameFromStore) })
		end
		log:info("Breakup done", { playerA = playerA.Name })
		return ResultUtil.Ok(nil)
	end
	-- ----------------------------------------------------------
	-- getPendingRequest - check apakah ada request pending for player
	-- ----------------------------------------------------------
	function service:getPendingRequest(userId: number): PendingRequest?
		local req = pendingRequests[userId]
		if not req or os.time() >= req.expiredAt then
			return nil
		end
		return req
	end
	-- ----------------------------------------------------------
	-- cancelPendingFrom - remove all pending request from sender
	-- (used when sender leaves)
	-- ----------------------------------------------------------
	function service:cancelPendingFrom(userId: number)
		for targetId, req in pairs(pendingRequests) do
			if req.fromUserId == userId then
				pendingRequests[targetId] = nil
			end
		end
	end
	-- Stop cleanup loop and clear state - for testing or teardown
	function service:destroy()
		_destroyed = true
		task.cancel(cleanupThread)
		table.clear(pendingRequests)
	end
	return service
end
return createCoupleService
