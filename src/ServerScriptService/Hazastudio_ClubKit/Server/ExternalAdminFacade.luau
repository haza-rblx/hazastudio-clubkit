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
local announceLimiter: any = nil
-- Self-reported presence from place-pack bridge modules (most reliable signal:
-- if our Adonis plugin / Kohl's addon ran, that admin is installed by definition).
local reportedAdmins: { Adonis: boolean, Kohls: boolean } = { Adonis = false, Kohls = false }

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

	-- Facade announce bypasses CommandExecutionService, so it carries its own
	-- limiter (same budget as /announce: Config.Announcement.RATE_MAX/RATE_WINDOW).
	local announceConfig = Config.Announcement
	if type(announceConfig) == "table" then
		announceLimiter = RateLimiter.new(announceConfig.RATE_MAX or 2, announceConfig.RATE_WINDOW or 30)
	end

	if provider ~= "None" and newDeps.eventBus and type(newDeps.eventBus.on) == "function" then
		eventBusUnsubscribe = newDeps.eventBus:on("Gift:RoleChanged", relayRoleChanged)
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
	if announceLimiter then
		announceLimiter:destroy()
		announceLimiter = nil
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
	if announceLimiter then
		local allowed, limitErr = announceLimiter:check(caller.UserId)
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

return ExternalAdminFacade
