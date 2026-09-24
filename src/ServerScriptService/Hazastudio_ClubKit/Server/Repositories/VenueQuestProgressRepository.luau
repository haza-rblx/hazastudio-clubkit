--!strict
-- Server/Repositories/VenueQuestProgressRepository.luau
-- Per-player venue quest progress (ADR 0015), DataStore `VenueQuestProgress_v1`, one document per
-- player: per-quest counters, check-in days, claims, and the join posts already seen.
-- Every write merges with what is stored (EventBoardDomain.mergeProgress), so a player hopping
-- servers never loses a counter or a claim; a claim is its own UpdateAsync that refuses when the
-- stored document already holds one, so two servers cannot both pay a reward out.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local EventBoardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.EventBoardDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

type Result<T> = Types.Result<T>
type ProgressDoc = EventBoardDomain.ProgressDoc

local function createVenueQuestProgressRepository(deps: { logger: Types.ILogger? }?)
	local log = if deps and deps.logger then deps.logger else Logger.new("VenueQuestProgressRepository")
	local store = DataStoreService:GetDataStore(Config.EventBoard.PROGRESS_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "VenueQuestProgressRepository" })

	local repo = {}

	local function mutex(userId: number): string
		return "venue-quest::" .. tostring(userId)
	end

	function repo:load(userId: number): Result<ProgressDoc>
		local read = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(tostring(userId))
			end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or Config.DataStore.RETRY_ATTEMPTS)
		end, mutex(userId))
		if not read.ok then
			return Result.Err(read.error)
		end
		return Result.Ok(EventBoardDomain.sanitizeProgress(read.value))
	end

	-- Writes this server's copy merged onto the stored one; returns the merged document.
	function repo:save(userId: number, doc: ProgressDoc): Result<ProgressDoc>
		local merged: ProgressDoc = doc
		local write = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(tostring(userId), function(old: any): any
					merged = EventBoardDomain.mergeProgress(EventBoardDomain.sanitizeProgress(old), doc)
					return merged
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutex(userId))
		if not write.ok then
			log:warn("Venue quest progress save failed", { userId = userId, err = write.error })
			return Result.Err(write.error)
		end
		return Result.Ok(merged)
	end

	-- Records the claim of `questKey` unless the stored document already has one.
	-- Ok(true) = claimed now, Ok(false) = already claimed (elsewhere). Returns the merged document.
	function repo:claim(userId: number, doc: ProgressDoc, questKey: string, now: number): (Result<boolean>, ProgressDoc?)
		local claimedNow = false
		local merged: ProgressDoc? = nil
		local write = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(tostring(userId), function(old: any): any
					local stored = EventBoardDomain.sanitizeProgress(old)
					local existing = stored.quests[questKey]
					if existing and existing.claimedAt then
						claimedNow = false
						merged = EventBoardDomain.mergeProgress(stored, doc)
						return nil -- keep the stored claim; nothing to write
					end
					local next = EventBoardDomain.mergeProgress(stored, doc)
					local entry = next.quests[questKey]
					if not entry then
						entry = { progress = 0, lastDay = 0, completed = false, claimedAt = nil }
						next.quests[questKey] = entry
					end
					entry.claimedAt = now
					claimedNow = true
					merged = next
					return next
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutex(userId))
		if not write.ok then
			log:warn("Venue quest claim failed", { userId = userId, quest = questKey, err = write.error })
			return Result.Err(write.error), nil
		end
		return Result.Ok(claimedNow), merged
	end

	-- Undoes a claim whose reward could not be granted, so the player can try again.
	function repo:unclaim(userId: number, questKey: string): Result<boolean>
		local write = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(tostring(userId), function(old: any): any
					local stored = EventBoardDomain.sanitizeProgress(old)
					local entry = stored.quests[questKey]
					if not entry or not entry.claimedAt then
						return nil
					end
					entry.claimedAt = nil
					return stored
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutex(userId))
		return if write.ok then Result.Ok(true) else Result.Err(write.error)
	end

	return repo
end

return {
	new = createVenueQuestProgressRepository,
}
