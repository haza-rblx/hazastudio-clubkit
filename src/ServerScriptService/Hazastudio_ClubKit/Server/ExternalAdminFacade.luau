--!strict
--[[
	External Admin Bridge facade (Adonis / Kohl's ↔ Club Kit).

	Singleton ModuleScript: Main.server calls `_init` once at boot; external
	admin plugins/addons (extras/place-packs/ExternalAdminBridge) reach it via
	FindFirstChild + pcall(require) on
	ServerScriptService.Hazastudio_ClubKit.Server.ExternalAdminFacade.

	Hard rules:
	- Runtime gate only: ExternalAdmin.Provider picks the bridge target; the
	  facade never installs/removes/touches the external admin itself.
	- No privilege bypass: every command re-runs the normal Club Kit services,
	  so canGift/canAnnounce gates apply exactly like chat commands.
	- Membership (VIP/VVIP/Supreme) and Spender roles never sync to external
	  ranks (ExternalAdminDomain never-sync guard).
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ExternalAdminDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ExternalAdminDomain)
local ExternalAdminPerksDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ExternalAdminPerksDomain)
local AnnouncementRateLimitDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AnnouncementRateLimitDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type Provider = ExternalAdminDomain.Provider

export type RoleChangedPayload = {
	userId: number,
	roleKey: string?,
	action: string, -- "give" | "remove"
	provider: Provider,
	target: (number | string)?, -- Adonis level / Kohl's role key (old rank on "remove")
}

local log = Logger.new("ExternalAdmin")

local initialized = false
local started = false
local deps: {
	giftService: any,
	membershipCommandService: any,
	genericBroadcastService: any,
	overheadService: any,
	eventBus: any,
}? = nil
local provider: Provider = "None"
local roleChangedCallbacks: { (RoleChangedPayload) -> () } = {}
local eventBusUnsubscribe: (() -> ())? = nil
-- Per-role-group announce limiters (same source of truth as /announce chat
-- command: AnnouncementRateLimitDomain). Lazily created per group.
local announceLimiters: { [string]: any } = {}
-- Self-reported presence from place-pack bridge modules (most reliable signal:
-- if our Adonis plugin / Kohl's addon ran, that admin is installed by definition).
local reportedAdmins: { Adonis: boolean, Kohls: boolean } = { Adonis = false, Kohls = false }
-- Perk quota store (injected via injectPerkQuotaRepository at boot; nil keeps
-- checkPerk gating working while consume fails closed with a clear error).
local perkQuotaRepository: any? = nil
-- Subscribers for effective-membership changes (perk-role mirror in addons).
local membershipChangedCallbacks: { (payload: any) -> () } = {}
local membershipEventUnsubscribe: (() -> ())? = nil

local ExternalAdminFacade = {}

local function externalAdminConfig(): ExternalAdminDomain.ExternalAdminConfig?
	local section = Config.ExternalAdmin
	if type(section) ~= "table" then
		return nil
	end
	return section
end

local function relayRoleChanged(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local target = ExternalAdminDomain.resolveRankTarget(externalAdminConfig(), payload.roleKey)
	if target == nil then
		return -- not a syncable role (never-sync, unmapped, or toggle off)
	end
	local enriched: RoleChangedPayload = {
		userId = payload.userId,
		roleKey = payload.roleKey,
		action = payload.action,
		provider = provider,
		target = target,
	}
	local snapshot = table.clone(roleChangedCallbacks)
	for _, callback in ipairs(snapshot) do
		task.spawn(callback, enriched)
	end
end

--- Called once by Main wiring before first use; idempotent.
function ExternalAdminFacade.injectPerkQuotaRepository(repo: any)
	if perkQuotaRepository == nil then
		perkQuotaRepository = repo
	end
end

function ExternalAdminFacade._init(newDeps: {
	giftService: any,
	membershipCommandService: any,
	genericBroadcastService: any,
	overheadService: any,
	eventBus: any,
})
	if initialized then
		return
	end
	initialized = true
	deps = newDeps
	local section = externalAdminConfig()
	provider = ExternalAdminDomain.normalizeProvider(if section then section.Provider else nil)

	-- Facade announce bypasses CommandExecutionService, so it resolves the same
	-- per-role-group budget via AnnouncementRateLimitDomain (single source of
	-- truth). Limiters are created lazily on first check per group.

	if provider ~= "None" and newDeps.eventBus and type(newDeps.eventBus.on) == "function" then
		eventBusUnsubscribe = newDeps.eventBus:on("Gift:RoleChanged", relayRoleChanged)
		-- Perk mirror feed: Overhead:Payload fires per player whenever the
		-- effective payload (incl. membership) changes. Bridge addons decide
		-- what to mirror (Kohl's perk roles); kit stays provider-agnostic.
		if provider == "Kohls" then
			membershipEventUnsubscribe = newDeps.eventBus:on("Overhead:Payload", function(payload: any)
				if type(payload) ~= "table" or type(payload.userId) ~= "number" then
					return
				end
				local enriched = {
					userId = payload.userId,
					effectiveMembership = payload.effectiveMembership,
					role = payload.role,
				}
				local callbacks = table.clone(membershipChangedCallbacks)
				for _, callback in ipairs(callbacks) do
					task.spawn(callback, enriched)
				end
			end)
		end
	end

	log:info("Facade initialised", { provider = provider })
end

-- Best-effort detection of installed admin loaders. Keep isolated: version
-- skew in either loader should be a one-function fix.
-- Signal priority: pack self-report > _G API > ServerScriptService name scan.
-- (Adonis renames its loader model to a random number at runtime, so the name
-- scan alone misses it; _G.Adonis needs G_API = true. Self-report covers both.)
-- The name scan is selector-aware: a loader whose entry Script is Disabled
-- (ExternalAdminSelector pack pattern) does not count as installed.
local function loaderEntryActive(child: Instance, relPath: { string }): boolean
	local inst: Instance = child
	for _, name in ipairs(relPath) do
		local nextInst = inst:FindFirstChild(name)
		if not nextInst then
			return true -- unknown layout: assume active (best effort)
		end
		inst = nextInst
	end
	if inst:IsA("Script") then
		return not inst.Disabled
	end
	return true
end

local function detectExternalAdmins(): (boolean, boolean)
	-- Note: official Adonis exposes _G.Adonis as userdata (API proxy), not a
	-- table — accept any non-nil. Kohl's new loader sets no globals; the name
	-- scan + pack self-report cover both.
	local adonis = reportedAdmins.Adonis or _G.Adonis ~= nil
	local kohls = reportedAdmins.Kohls or _G.Kohls ~= nil or _G._K ~= nil
	if not adonis or not kohls then
		for _, child in ipairs(ServerScriptService:GetChildren()) do
			local name = string.lower(child.Name)
			if not adonis and string.find(name, "adonis", 1, true) and loaderEntryActive(child, { "Loader", "Loader" }) then
				adonis = true
			end
			if not kohls and string.find(name, "kohl", 1, true) and loaderEntryActive(child, { "Loader" }) then
				kohls = true
			end
			if adonis and kohls then
				break
			end
		end
	end
	return adonis, kohls
end

function ExternalAdminFacade.onStart()
	if started then
		return
	end
	started = true
	-- Loaders initialise asynchronously (observed: a modified Adonis fork took
	-- >10s in Studio); 20s keeps the warn honest without meaningfully delaying it.
	task.delay(20, function()
		local adonis, kohls = detectExternalAdmins()
		if provider == "None" then
			if adonis or kohls then
				log:info("External admin detected but ExternalAdmin.Provider = \"None\" — bridge inactive", {
					adonis = adonis,
					kohls = kohls,
				})
			end
			return
		end
		if provider == "Adonis" and not adonis then
			log:warn("ExternalAdmin.Provider = \"Adonis\" but Adonis was not detected — bridge commands/sync will not run")
		end
		if provider == "Kohls" and not kohls then
			log:warn("ExternalAdmin.Provider = \"Kohls\" but Kohl's (new loader) was not detected — bridge commands/sync will not run")
		end
		if adonis and kohls then
			log:warn("Both Adonis and Kohl's detected — bridging " .. provider .. " only; consider removing the other")
		end
	end)
end

function ExternalAdminFacade.onDestroy()
	if eventBusUnsubscribe then
		eventBusUnsubscribe()
		eventBusUnsubscribe = nil
	end
	if membershipEventUnsubscribe then
		membershipEventUnsubscribe()
		membershipEventUnsubscribe = nil
	end
	table.clear(membershipChangedCallbacks)
	for group, limiter in pairs(announceLimiters) do
		limiter:destroy()
		announceLimiters[group] = nil
	end
	table.clear(roleChangedCallbacks)
end

function ExternalAdminFacade.isEnabled(): boolean
	return initialized and provider ~= "None"
end

-- Called by place-pack bridge modules on load to self-report that their admin
-- system is installed (works before _init; read by startup detection).
function ExternalAdminFacade.reportAdminPresent(providerName: string)
	local normalized = ExternalAdminDomain.normalizeProvider(providerName)
	if normalized == "Adonis" then
		reportedAdmins.Adonis = true
	elseif normalized == "Kohls" then
		reportedAdmins.Kohls = true
	end
end

function ExternalAdminFacade.getProvider(): Provider
	return provider
end

function ExternalAdminFacade.getRankMap(): { [string]: any }
	local config = externalAdminConfig()
	if config and type(config.RankMap) == "table" then
		return config.RankMap
	end
	return {}
end

--- Live view of the Perks section (bridge addons read this each run so buyer
--- config edits apply without a reboot).
function ExternalAdminFacade.getPerksConfig(): { [string]: any }?
	local config = externalAdminConfig()
	if config and type(config.Perks) == "table" then
		return (config.Perks :: any)
	end
	return nil
end

--- Membership tier -> canonical TierN key used by perk gates (nil = none).
--- Uses OverheadDomain normalization, so all buyer aliases (vip/vvip/supreme/
--- elite/exclusive/...) resolve to their TierN key.
function ExternalAdminFacade.tierForMembershipKey(membership: any): string?
	local normalized = OverheadDomain.normalizeMembershipTier(membership)
	if normalized == "Tier1" or normalized == "Tier2" or normalized == "Tier3" then
		return normalized
	end
	return nil
end

-- Subscribe to rank-sync payloads (place-pack plugins/addons). Returns unsubscribe.
function ExternalAdminFacade.onRoleChanged(callback: (RoleChangedPayload) -> ()): () -> ()
	table.insert(roleChangedCallbacks, callback)
	return function()
		for index, registered in ipairs(roleChangedCallbacks) do
			if registered == callback then
				table.remove(roleChangedCallbacks, index)
				break
			end
		end
	end
end

local function guardEnabled(): Result<any>?
	if not ExternalAdminFacade.isEnabled() then
		return ResultUtil.Err("[ExternalAdmin] Bridge disabled (ExternalAdmin.Provider = \"None\").")
	end
	if deps == nil then
		return ResultUtil.Err("[ExternalAdmin] Facade not initialised.")
	end
	return nil
end

local function resolvePlayer(userId: number?, label: string): (Player?, Result<any>?)
	-- Note: Studio test players have negative UserIds; only non-numbers are
	-- rejected here — nonsense ids simply resolve to nil below.
	if type(userId) ~= "number" then
		return nil, ResultUtil.Err("[ExternalAdmin] Invalid " .. label .. " userId.")
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil, ResultUtil.Err("[ExternalAdmin] " .. label .. " is not in this server.")
	end
	return player, nil
end

function ExternalAdminFacade.setRole(callerUserId: number, targetUserId: number, roleKey: string): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local caller, callerErr = resolvePlayer(callerUserId, "Caller")
	if not caller then
		return callerErr :: Result<any>
	end
	local target, targetErr = resolvePlayer(targetUserId, "Target")
	if not target then
		return targetErr :: Result<any>
	end
	return (deps :: any).giftService:giveRole(caller, target, roleKey)
end

function ExternalAdminFacade.unsetRole(callerUserId: number, targetUserId: number): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local caller, callerErr = resolvePlayer(callerUserId, "Caller")
	if not caller then
		return callerErr :: Result<any>
	end
	local target, targetErr = resolvePlayer(targetUserId, "Target")
	if not target then
		return targetErr :: Result<any>
	end
	return (deps :: any).giftService:removeRole(caller, target)
end

function ExternalAdminFacade.giftMembership(callerUserId: number, targetUserId: number, tier: string): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local caller, callerErr = resolvePlayer(callerUserId, "Caller")
	if not caller then
		return callerErr :: Result<any>
	end
	local target, targetErr = resolvePlayer(targetUserId, "Target")
	if not target then
		return targetErr :: Result<any>
	end
	return (deps :: any).membershipCommandService:grantMembership(caller, target, tier)
end

function ExternalAdminFacade.ungiftMembership(callerUserId: number, targetUserId: number, tier: string): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local caller, callerErr = resolvePlayer(callerUserId, "Caller")
	if not caller then
		return callerErr :: Result<any>
	end
	local target, targetErr = resolvePlayer(targetUserId, "Target")
	if not target then
		return targetErr :: Result<any>
	end
	return (deps :: any).membershipCommandService:removeMembership(caller, target, tier)
end

function ExternalAdminFacade.announce(callerUserId: number, message: string): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local caller, callerErr = resolvePlayer(callerUserId, "Caller")
	if not caller then
		return callerErr :: Result<any>
	end
	if type(message) ~= "string" or message == "" then
		return ResultUtil.Err("[ExternalAdmin] Empty announce message.")
	end
	-- Resolve announce budget (same logic + legacy fallback as the chat command).
	do
		local budget
		if Config.Announcement.RATE_LIMITS_CONFIGURED == true then
			local roleKey: string? = nil
			local effectiveMembership: string? = nil
			local overhead = (deps :: any).overheadService
			if overhead and type(overhead.getEffectivePayload) == "function" then
				local payloadResult = overhead:getEffectivePayload(caller)
				if payloadResult.ok and type(payloadResult.value) == "table" then
					roleKey = payloadResult.value.role
					effectiveMembership = payloadResult.value.effectiveMembership
				end
			end
			budget = AnnouncementRateLimitDomain.resolve(roleKey, effectiveMembership)
		else
			budget = AnnouncementRateLimitDomain.legacyBudget()
		end
		local limiter = announceLimiters[budget.group]
		if not limiter then
			limiter = RateLimiter.new(budget.max, budget.window)
			announceLimiters[budget.group] = limiter
		end
		local allowed, limitErr = limiter:check(caller.UserId)
		if not allowed then
			return ResultUtil.Err("[ExternalAdmin] " .. tostring(limitErr))
		end
	end
	local ok, err = (deps :: any).genericBroadcastService:broadcastFromPlayer(caller, message)
	if ok then
		return ResultUtil.Ok(true)
	end
	return ResultUtil.Err("[ExternalAdmin] " .. tostring(err))
end

function ExternalAdminFacade.getEffectiveRole(userId: number): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local player, playerErr = resolvePlayer(userId, "Player")
	if not player then
		return playerErr :: Result<any>
	end
	local payloadResult = (deps :: any).overheadService:getEffectivePayload(player)
	if payloadResult.ok then
		return ResultUtil.Ok(payloadResult.value.role)
	end
	return ResultUtil.Err("[ExternalAdmin] " .. tostring(payloadResult.error))
end

-- Effective membership tier ("Guest"/"VIP"/"VVIP"/"Supreme") for bridge-side
-- perk gating (e.g. Kohl's fly/smite). Read-only: never mutates membership.
function ExternalAdminFacade.getMembership(userId: number): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local player, playerErr = resolvePlayer(userId, "Player")
	if not player then
		return playerErr :: Result<any>
	end
	local payloadResult = (deps :: any).overheadService:getEffectivePayload(player)
	if payloadResult.ok then
		return ResultUtil.Ok(payloadResult.value.effectiveMembership)
	end
	return ResultUtil.Err("[ExternalAdmin] " .. tostring(payloadResult.error))
end

-- ============================================================
-- EXTERNAL-ADMIN PERKS (bridge-side gating: Kohl's fly/smite)
-- ============================================================

export type PerkGate = ExternalAdminPerksDomain.PerkGate

local function resolveStaffBypass(): boolean
	local config = externalAdminConfig()
	if not (config and type(config.Perks) == "table") then
		return true -- default: staff keep native admin power
	end
	local staffBypass = (config.Perks :: any).StaffBypass
	if staffBypass == nil then
		return true
	end
	return staffBypass == true
end

local function resolveRoleAndMembership(player: Player): (string?, string?)
	local overhead = (deps :: any).overheadService
	if not (overhead and type(overhead.getEffectivePayload) == "function") then
		return nil, nil
	end
	local payloadResult = overhead:getEffectivePayload(player)
	if not (payloadResult.ok and type(payloadResult.value) == "table") then
		return nil, nil
	end
	return payloadResult.value.role, payloadResult.value.effectiveMembership
end

--- Can this player use the named perk right now? Pure read — consume separately.
--- perkConfig nil (section absent) = perk disabled engine-side (addon must not grant it).
function ExternalAdminFacade.checkPerk(userId: number, perk: string): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	local config = externalAdminConfig()
	local perksSection = if config and type(config.Perks) == "table" then (config.Perks :: any) else nil
	if perksSection == nil or perksSection.Enabled == false then
		return ResultUtil.Err("perk_not_configured")
	end
	local perks = perksSection[perk]
	if perks == nil then
		return ResultUtil.Err("perk_not_configured")
	end
	local player, playerErr = resolvePlayer(userId, "Player")
	if not player then
		return playerErr :: Result<any>
	end
	local roleKey, effectiveMembership = resolveRoleAndMembership(player)
	local gate = ExternalAdminPerksDomain.resolvePerk(perks, {
		isStaff = RolesDomain.isStaffPlus(roleKey),
		staffBypass = resolveStaffBypass(),
		hasAtLeast = function(tier: string)
			return OverheadDomain.hasMembershipAtLeast(effectiveMembership, tier)
		end,
		tierValue = function(tier: string)
			return OverheadDomain.getMembershipValue(tier)
		end,
	})
	return ResultUtil.Ok(gate)
end

--- Consume one unit of a capped perk (e.g. weekly smite quota). Unlimited
--- perks (quota nil) pass straight through.
function ExternalAdminFacade.consumePerkQuota(userId: number, perk: string, quota: number?): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	if not perkQuotaRepository then
		return ResultUtil.Err("perk_quota_unavailable")
	end
	if quota == nil then
		return ResultUtil.Ok(true) -- unlimited (fly-style): nothing to consume
	end
	return perkQuotaRepository:consume(perk, userId, quota)
end

--- Remaining uses this ISO week for a capped perk.
function ExternalAdminFacade.peekPerkQuota(userId: number, perk: string, quota: number): Result<any>
	local disabled = guardEnabled()
	if disabled then
		return disabled
	end
	if not perkQuotaRepository then
		return ResultUtil.Err("perk_quota_unavailable")
	end
	return perkQuotaRepository:peek(perk, userId, quota)
end

--- Subscribe to effective-membership changes (join + live gift/revoke via
--- Overhead:Payload). Returns unsubscribe. Fired ONLY when Provider matches —
--- bridge addons use this to mirror perk roles.
function ExternalAdminFacade.onMembershipChanged(callback: (payload: any) -> ()): () -> ()
	if provider ~= "Kohls" then
		-- Other providers have no perk mirror; keep the API shape stable.
	end
	table.insert(membershipChangedCallbacks, callback)
	return function()
		local index = table.find(membershipChangedCallbacks, callback)
		if index then
			table.remove(membershipChangedCallbacks, index)
		end
	end
end

return ExternalAdminFacade
