--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)
local TitleQuotaDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleQuotaDomain)
local TitleEventDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleEventDomain)
local TitleAccessDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleAccessDomain)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)
local TitleStyleDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleStyleDomain)
local TitleFontUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local AnimationModes = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset.AnimationModes)

type Result<T> = Types.Result<T>
type ProfileMenuPayload = Types.ProfileMenuPayload
type ProfileRelationshipMode = Types.ProfileRelationshipMode
type ProfileStoredData = Types.ProfileStoredData
type OverheadStoredData = Types.OverheadStoredData
type ILogger = Types.ILogger

local function trim(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

-- Same catalog the admin panel offers; players get no separate whitelist.
local VALID_TITLE_FONTS: { [string]: true } = (function()
	local map: { [string]: true } = {}
	for _, fontName in ipairs(TitleFontUtil.getConfiguredFonts()) do
		map[fontName] = true
	end
	return map
end)()

local function getRelationshipMode(rawMode: any, isCoupled: boolean): ProfileRelationshipMode
	if rawMode == "Fun" then
		return "Fun"
	end
	if rawMode == "Taken" and isCoupled then
		return "Taken"
	end
	if rawMode == "Single" then
		return "Single"
	end
	return if isCoupled then "Taken" else "Single"
end

local function createProfileMenuService(deps: {
	logger: ILogger,
	profileRepository: any,
	overheadRepository: any,
	profileCommandService: any,
	-- Only read when the Free Title event runs in "Donation" mode, so a place that
	-- does not run that variant never pays for the lookup.
	donationService: any?,
})
	local _log = deps.logger
	local profileRepository = deps.profileRepository
	local overheadRepository = deps.overheadRepository
	local profileCommandService = deps.profileCommandService
	local donationService = deps.donationService

	local service = {}

	-- Late-bound: DonationService is built after this one in Main.server.
	function service:setDonationService(svc: any)
		donationService = svc
	end

	-- The server is the authority on who the event lets in. The card paints itself
	-- from the same numbers, but every accept still goes through here.
	--
	-- Robux is only looked up in "Donation" mode: `getDonorProfile` resolves from
	-- the leaderboard cache in the normal case, but it can fall through to a
	-- DataStore read, and a place running the level variant should never pay that.
	local function evaluateEvent(player: Player, level: number)
		local eventConfig = {
			Mode = Config.FreeTitleEvent.MODE,
			RequiredLevel = Config.FreeTitleEvent.REQUIRED_LEVEL,
			MinDonationRobux = Config.FreeTitleEvent.MIN_DONATION_ROBUX,
			MinDonationCash = Config.FreeTitleEvent.MIN_DONATION_CASH,
		}
		-- Donation totals are only fetched when the buyer actually requires one:
		-- `getDonorProfile` usually resolves from the leaderboard cache, but it can
		-- fall through to a DataStore read, and a level-only event must not pay for
		-- that on every payload build. One call covers both Robux and Cash.
		local needsDonation = (tonumber(eventConfig.MinDonationRobux) or 0) >= 1
			or (tonumber(eventConfig.MinDonationCash) or 0) >= 1
		local robuxTotal, cashTotal = 0, 0
		if
			needsDonation
			and TitleEventDomain.normalizeMode(eventConfig.Mode) ~= "disabled"
			and donationService
			and type(donationService.getDonorProfile) == "function"
		then
			local ok, profile = pcall(function()
				return donationService:getDonorProfile(player)
			end)
			if ok and type(profile) == "table" then
				robuxTotal = tonumber(profile.robuxTotal) or 0
				cashTotal = tonumber(profile.cashTotal) or 0
			end
		end
		return TitleEventDomain.evaluate(eventConfig, {
			level = level,
			robuxTotal = robuxTotal,
			cashTotal = cashTotal,
		})
	end

	-- One line telling the player what they are still missing, in their own terms:
	-- a level, Robux, or cash in the venue's currency.
	local function eventLockedMessage(event: any, fallbackLevel: number): string
		local pending = TitleEventDomain.nextUnmet(event)
		if not pending then
			return string.format(Config.CustomTitle.MSG_LOCKED_LEVEL, fallbackLevel)
		end
		if pending.axis == "robux" then
			return string.format(Config.CustomTitle.MSG_LOCKED_ROBUX, pending.requirement)
		elseif pending.axis == "cash" then
			return string.format(
				Config.CustomTitle.MSG_LOCKED_CASH,
				DonationAmountFormat.formatCash(pending.requirement)
			)
		end
		return string.format(Config.CustomTitle.MSG_LOCKED_LEVEL, pending.requirement)
	end

	local function filterBroadcastText(text: string, userId: number): Result<string>
		local filtered = TextFilterUtil.filterForBroadcast(userId, text)
		if not filtered then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		local normalized = trim(filtered)
		if normalized == "" then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		return Result.Ok(normalized)
	end

	local function loadStored(userId: number): Result<{ profile: ProfileStoredData, overhead: OverheadStoredData }>
		local profileResult = profileRepository:load(userId)
		if not profileResult.ok then
			return Result.Err(profileResult.error)
		end

		local overheadResult = overheadRepository:load(userId)
		if not overheadResult.ok then
			return Result.Err(overheadResult.error)
		end

		return Result.Ok({
			profile = profileResult.value,
			overhead = overheadResult.value,
		})
	end

	local function buildPayload(player: Player, profile: ProfileStoredData, overhead: OverheadStoredData): ProfileMenuPayload
		local isCoupled = overhead.couplePartner ~= nil or overhead.couplePartnerId ~= nil
		local relationshipMode = getRelationshipMode(profile.relationshipMode, isCoupled)
		local displayNameOverride = type(profile.displayNameOverride) == "string" and profile.displayNameOverride ~= "" and profile.displayNameOverride or nil
		local statusText = if profileCommandService and type(profileCommandService.getStatus) == "function"
			then profileCommandService:getStatus(player.UserId)
			else nil

		-- Self-service gate: reaching MIN_LEVEL unlocks creating your own title, and
		-- holding an admin-granted one always keeps it editable. With the feature off
		-- selfServiceOn is false, so canEditSpecialTitle stays exactly what it was
		-- before this feature existed: "an admin gave me a title".
		local selfServiceOn = Config.FeatureFlags.SelfCustomTitleEnabled == true
		local level = OverheadDomain.normalizeLevel(overhead.level)
		local minLevel = Config.CustomTitle.MIN_LEVEL
		local meetsLevel = selfServiceOn and level >= minLevel
		-- The Free Title event is a second way in, never a way out: it can only add
		-- access on top of the level gate and an admin-granted title.
		local event = evaluateEvent(player, level)
		local meetsEvent = selfServiceOn and event.met
		local access = TitleAccessDomain.evaluate({
			selfServiceOn = selfServiceOn,
			hasTitle = overhead.specialTitle ~= nil,
			fromAdmin = overhead.specialTitleFromAdmin,
			freeUsed = overhead.specialTitleFreeUsed,
			freeEnabled = Config.CustomTitle.FREE_FIRST_TITLE == true,
			meetsLevel = meetsLevel,
			meetsEvent = meetsEvent,
		})
		local quota = TitleQuotaDomain.evaluate(overhead.specialTitleChanges, os.time(), {
			MaxChangesPerWindow = Config.CustomTitle.MAX_CHANGES_PER_WINDOW,
			WindowDays = Config.CustomTitle.WINDOW_DAYS,
			QuotaEnabled = Config.CustomTitle.QUOTA_ENABLED,
		})

		return {
			displayName = displayNameOverride or player.DisplayName,
			displayNameOverride = displayNameOverride,
			bio = profile.bio,
			statusText = statusText,
			specialTitle = overhead.specialTitle,
			canEditSpecialTitle = access.canEdit,
			-- The panel says "this one is on the house" only while the free slot is
			-- what is actually opening it.
			customTitleFreeAvailable = access.reason == "free",
			customTitleEnabled = selfServiceOn,
			specialTitlePreset = overhead.specialTitlePreset,
			specialTitleSize = overhead.specialTitleSize,
			specialTitleFont = overhead.specialTitleFont,
			customTitleLevel = level,
			customTitleMinLevel = minLevel,
			customTitleRemaining = quota.remaining,
			customTitleResetsAt = quota.resetsAt,
			customTitleUnlimited = quota.unlimited,
			-- What the event card needs to paint itself: which variant is running,
			-- the threshold, where this player stands, and whether they are in.
			titleEventMode = event.mode,
			titleEventActive = event.active,
			titleEventMet = event.met,
			titleEventRequirements = event.requirements,
			relationshipMode = relationshipMode,
			isCoupled = isCoupled,
			couplePartner = overhead.couplePartner,
			showCoupleName = overhead.showCoupleName ~= false,
		}
	end

	local function refreshPayload(player: Player): Result<ProfileMenuPayload>
		local loaded = loadStored(player.UserId)
		if not loaded.ok then
			return Result.Err(loaded.error)
		end
		return Result.Ok(buildPayload(player, loaded.value.profile, loaded.value.overhead))
	end

	function service:load(player: Player): Result<ProfileMenuPayload>
		return refreshPayload(player)
	end

	function service:updateField(player: Player, field: string, value: any): Result<ProfileMenuPayload>
		if field == "displayNameOverride" then
			if type(value) ~= "string" then
				return Result.Err(Config.ProfileMenu.MSG_DISPLAY_NAME_TOO_LONG)
			end

			local nextValue = trim(value)
			if #nextValue > Config.ProfileMenu.DISPLAY_NAME_MAX_LENGTH then
				return Result.Err(Config.ProfileMenu.MSG_DISPLAY_NAME_TOO_LONG)
			end

			local filtered: string? = nil
			if nextValue ~= "" then
				local filteredResult = filterBroadcastText(nextValue, player.UserId)
				if not filteredResult.ok then
					return filteredResult
				end
				filtered = filteredResult.value
				if filtered == player.DisplayName then
					filtered = nil
				end
			end

			local saved = profileRepository:update(player.UserId, function(current: ProfileStoredData): ProfileStoredData
				local nextProfile = table.clone(current)
				nextProfile.displayNameOverride = filtered
				return nextProfile
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "bio" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local saved = profileCommandService:setBio(player.UserId, value)
			if not saved.ok then
				return saved
			end
			return refreshPayload(player)
		end

		if field == "statusText" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local saved = profileCommandService:setStatus(player.UserId, value)
			if not saved.ok then
				return saved
			end
			return refreshPayload(player)
		end

		if field == "relationshipMode" then
			if value ~= "Single" and value ~= "Taken" and value ~= "Fun" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			local isCoupled = loaded.value.overhead.couplePartner ~= nil or loaded.value.overhead.couplePartnerId ~= nil
			if value == "Taken" and not isCoupled then
				return Result.Err(Config.ProfileMenu.MSG_SINGLE_DUMB)
			end

			local saved = profileRepository:update(player.UserId, function(current: ProfileStoredData): ProfileStoredData
				local nextProfile = table.clone(current)
				nextProfile.relationshipMode = value
				return nextProfile
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "showCoupleName" then
			if type(value) ~= "boolean" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			local isCoupled = loaded.value.overhead.couplePartner ~= nil or loaded.value.overhead.couplePartnerId ~= nil
			if not isCoupled then
				return Result.Err(Config.ProfileMenu.MSG_SINGLE_DUMB)
			end

			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				return OverheadDomain.mergeStored(current, {
					showCoupleName = value,
				})
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		-- Self-service custom title (Features.SelfCustomTitle). `value` carries the whole
		-- form: { title, size, preset, font }. An omitted style field is left as-is; a
		-- present but invalid one is rejected rather than silently dropped by sanitize.
		-- The legacy "specialTitle" branch below stays the feature-off path, untouched.
		if field == "customTitle" then
			if Config.FeatureFlags.SelfCustomTitleEnabled ~= true then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_LOCKED)
			end
			if type(value) ~= "table" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end
			local overhead = loaded.value.overhead

			local minLevel = Config.CustomTitle.MIN_LEVEL
			local level = OverheadDomain.normalizeLevel(overhead.level)
			-- Who is letting them through, decided here rather than trusted from the
			-- client — the card and the panel are the ones telling them they qualify.
			-- The event is only consulted when the cheaper routes have not already
			-- opened it, so a level-qualified player never pays for a donation lookup.
			local access = TitleAccessDomain.evaluate({
				selfServiceOn = true,
				hasTitle = overhead.specialTitle ~= nil,
				fromAdmin = overhead.specialTitleFromAdmin,
				freeUsed = overhead.specialTitleFreeUsed,
				freeEnabled = Config.CustomTitle.FREE_FIRST_TITLE == true,
				meetsLevel = level >= minLevel,
				meetsEvent = false,
			})
			local event = nil
			if not access.canEdit then
				event = evaluateEvent(player, level)
				access = TitleAccessDomain.evaluate({
					selfServiceOn = true,
					hasTitle = overhead.specialTitle ~= nil,
					fromAdmin = overhead.specialTitleFromAdmin,
					freeUsed = overhead.specialTitleFreeUsed,
					freeEnabled = Config.CustomTitle.FREE_FIRST_TITLE == true,
					meetsLevel = level >= minLevel,
					meetsEvent = event.met,
				})
			end
			if not access.canEdit then
				return Result.Err(eventLockedMessage(event or evaluateEvent(player, level), minLevel))
			end
			-- Only a write the free slot paid for burns it.
			local spendsFree = TitleAccessDomain.shouldSpendFree(access)

			-- Validate everything before spending quota: a rejected form must be free.
			local nextTitle = trim(if type(value.title) == "string" then value.title else "")
			if nextTitle == "" then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_EMPTY)
			end
			if #nextTitle > Config.Admin.TITLE_MAX_LENGTH then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_TOO_LONG)
			end

			local nextSize = if type(value.size) == "string" and TitleStyleDomain.isValidTitleSize(value.size)
				then value.size
				else nil
			if value.size ~= nil and nextSize == nil then
				return Result.Err(Config.CustomTitle.MSG_INVALID_SIZE)
			end
			local nextPreset = if type(value.preset) == "string" and AnimationModes.IsPreset(value.preset)
				then value.preset
				else nil
			if value.preset ~= nil and nextPreset == nil then
				return Result.Err(Config.CustomTitle.MSG_INVALID_PRESET)
			end
			local nextFont = if type(value.font) == "string" and VALID_TITLE_FONTS[value.font]
				then value.font
				else nil
			if value.font ~= nil and nextFont == nil then
				return Result.Err(Config.CustomTitle.MSG_INVALID_FONT)
			end

			local unchanged = nextTitle == overhead.specialTitle
				and (nextSize == nil or nextSize == overhead.specialTitleSize)
				and (nextPreset == nil or nextPreset == overhead.specialTitlePreset)
				and (nextFont == nil or nextFont == overhead.specialTitleFont)
			if unchanged then
				return Result.Err(Config.CustomTitle.MSG_NO_CHANGE)
			end

			local now = os.time()
			local quotaConfig = {
				MaxChangesPerWindow = Config.CustomTitle.MAX_CHANGES_PER_WINDOW,
				WindowDays = Config.CustomTitle.WINDOW_DAYS,
				QuotaEnabled = Config.CustomTitle.QUOTA_ENABLED,
			}
			local quotaMessage =
				string.format(Config.CustomTitle.MSG_QUOTA_SPENT, Config.CustomTitle.MAX_CHANGES_PER_WINDOW)
			-- Cheap early exit so an obviously-spent quota never pays for a text filter
			-- round trip. The authoritative check is inside the updater below.
			if not TitleQuotaDomain.evaluate(overhead.specialTitleChanges, now, quotaConfig).allowed then
				return Result.Err(quotaMessage)
			end

			local filteredResult = filterBroadcastText(nextTitle, player.UserId)
			if not filteredResult.ok then
				return filteredResult
			end

			local quotaBlocked = false
			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				-- Re-check against `current` rather than the earlier read: two updates
				-- racing here must not both spend the same slot.
				if not TitleQuotaDomain.evaluate(current.specialTitleChanges, now, quotaConfig).allowed then
					quotaBlocked = true
					return current
				end
				local changes: { [string]: any } = {
					specialTitle = filteredResult.value,
					specialTitleChanges = TitleQuotaDomain.record(current.specialTitleChanges, now, quotaConfig),
					-- The title is now theirs, not an admin's: it stops shielding future
					-- edits, which is what makes "one free title" mean one.
					specialTitleFromAdmin = false,
				}
				if spendsFree then
					changes.specialTitleFreeUsed = true
				end
				if nextSize ~= nil then
					changes.specialTitleSize = nextSize
				end
				if nextPreset ~= nil then
					changes.specialTitlePreset = nextPreset
				end
				if nextFont ~= nil then
					changes.specialTitleFont = nextFont
				end
				return OverheadDomain.mergeStored(current, changes)
			end)
			if quotaBlocked then
				return Result.Err(quotaMessage)
			end
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		-- Clearing your own title is always free: a player who has run out of changes
		-- must still be able to take off a title they no longer want.
		if field == "customTitleRemove" then
			if Config.FeatureFlags.SelfCustomTitleEnabled ~= true then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_LOCKED)
			end

			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				return OverheadDomain.mergeStored(current, {
					specialTitle = OverheadDomain.NIL,
					specialTitlePreset = OverheadDomain.NIL,
					specialTitleSize = OverheadDomain.NIL,
					specialTitleFont = OverheadDomain.NIL,
				})
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "specialTitle" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			if loaded.value.overhead.specialTitle == nil then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_LOCKED)
			end

			local nextValue = trim(value)
			if nextValue == "" then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_EMPTY)
			end
			if #nextValue > Config.Admin.TITLE_MAX_LENGTH then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_TOO_LONG)
			end

			local filteredResult = filterBroadcastText(nextValue, player.UserId)
			if not filteredResult.ok then
				return filteredResult
			end

			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				return OverheadDomain.mergeStored(current, {
					specialTitle = filteredResult.value,
				})
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
	end

	return service
end

return createProfileMenuService
