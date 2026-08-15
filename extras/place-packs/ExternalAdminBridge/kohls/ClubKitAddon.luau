--!strict
--[[
	Club Kit ↔ Kohl's Admin (new loader) bridge (External Admin Bridge pack).

	Install: ModuleScript named "ClubKitAddon" inside the Kohl's Admin
	"Addons" folder (docs.kohl.gg/docs/custom_commands). Do NOT put "Client"
	or "Server" in the name — the command must register in both contexts.
	New loader only (kohl.gg), NOT the Legacy loader.

	Behaviour:
	- Adds ;cksetrole / ;ckunsetrole / ;ckgift / ;ckungift / ;ckannounce
	  (group "Administration") which call the Club Kit ExternalAdminFacade.
	  Club Kit permission gates still apply — a Kohl's admin without a
	  kit-side privileged role gets "no_perm" (by design).
	- Mirrors Club Kit staff role changes into Kohl's roles via
	  _K.Auth.userRoleAdd/userRoleRemove (non-persistent — Club Kit's
	  DataStore stays the source of truth).
	- No-op when ClubKitConfig.ExternalAdmin.Provider ~= "Kohls" or the
	  facade is missing (engine too old / not installed).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local SYNC_POLL_SECONDS = 2
local SYNC_POLL_ATTEMPTS = 30 -- ~1 minute: Club Kit Main may boot after Kohl's

return function(_K)
	local function getFacadeModule(): any?
		local kit = ServerScriptService:FindFirstChild("Hazastudio_ClubKit")
		local kitServer = kit and kit:FindFirstChild("Server")
		local mod = kitServer and kitServer:FindFirstChild("ExternalAdminFacade")
		if not (mod and mod:IsA("ModuleScript")) then
			return nil
		end
		local ok, facade = pcall(require, mod)
		if not ok or type(facade) ~= "table" or type(facade.isEnabled) ~= "function" then
			return nil
		end
		return facade
	end

	local function log(message: string)
		_K.log(message, "INFO")
	end

	local function runFacade(context: any, method: string, ...: any)
		local facade = getFacadeModule()
		if not facade then
			_K.log("[ClubKit] ExternalAdminFacade not found — Club Kit engine missing or outdated", "ERROR")
			return
		end
		local result = facade[method](...)
		if type(result) == "table" and result.ok then
			log(`[ClubKit] {method} ok (by {context.from})`)
			print(`[ClubKitAddon] command {method} ok by {tostring(context.from)}`)
		else
			local err = type(result) == "table" and tostring(result.error) or "unknown error"
			_K.log(`[ClubKit] {method} failed: {err}`, "ERROR")
			print(`[ClubKitAddon] command {method} failed: {err}`)
		end
	end

	_K.Registry.registerCommand(_K, {
		name = "cksetrole",
		description = "Give a Club Kit role (Staff, Moderator, DJ, ...) via Club Kit",
		group = "Administration",
		args = {
			{ type = "player", name = "Target", description = "Player to receive the role." },
			{ type = "string", name = "Role", description = "Club Kit role key, e.g. Staff." },
		},
		run = function(context, targetPlayer: Player, role: string)
			runFacade(context, "setRole", context.from, targetPlayer.UserId, role)
		end,
	})

	_K.Registry.registerCommand(_K, {
		name = "ckunsetrole",
		description = "Remove a player's gifted Club Kit role",
		group = "Administration",
		args = {
			{ type = "player", name = "Target", description = "Player whose role is removed." },
		},
		run = function(context, targetPlayer: Player)
			runFacade(context, "unsetRole", context.from, targetPlayer.UserId)
		end,
	})

	_K.Registry.registerCommand(_K, {
		name = "ckgift",
		description = "Gift Club Kit membership (vip / vvip / supreme)",
		group = "Administration",
		args = {
			{ type = "player", name = "Target", description = "Player to gift." },
			{ type = "string", name = "Tier", description = "vip, vvip, or supreme." },
		},
		run = function(context, targetPlayer: Player, tier: string)
			runFacade(context, "giftMembership", context.from, targetPlayer.UserId, tier)
		end,
	})

	_K.Registry.registerCommand(_K, {
		name = "ckungift",
		description = "Remove a gifted Club Kit membership tier",
		group = "Administration",
		args = {
			{ type = "player", name = "Target", description = "Player whose membership is removed." },
			{ type = "string", name = "Tier", description = "vip, vvip, or supreme." },
		},
		run = function(context, targetPlayer: Player, tier: string)
			runFacade(context, "ungiftMembership", context.from, targetPlayer.UserId, tier)
		end,
	})

	_K.Registry.registerCommand(_K, {
		name = "ckannounce",
		description = "Send a Club Kit broadcast (uses Club Kit announce gates + rate limit)",
		group = "Administration",
		args = {
			{ type = "string", name = "Message", description = "Broadcast message (filtered)." },
		},
		run = function(context, message: string)
			runFacade(context, "announce", context.from, message)
		end,
	})

	-- Override Kohl's native announcement commands so both route through the
	-- Club Kit broadcast (styled UI + canAnnounce gate + rate limit).
	-- Registry officially supports this: registering the same lowercase name
	-- replaces the native command (logs "Overriding Kohl's Admin command").
	-- Aliases MUST be re-declared: the override clears the native alias map,
	-- so omitting them would kill ";m"/";msg" entirely.
	--
	--  - "message" (aliases m, msg) — transient broadcast: exact semantic
	--    match for the Club Kit broadcast.
	--  - "announce" — Kohl's persistent banner (saved until cleared) is
	--    replaced by the Club Kit broadcast; the persistent-native behavior
	--    is intentionally dropped for one consistent broadcast UX.
	-- Delete either block to restore that command's native behavior.
	_K.Registry.registerCommand(_K, {
		name = "message",
		aliases = { "m", "msg" },
		description = "Broadcast via Club Kit (club styling, gates + rate limit apply)",
		group = "General",
		args = {
			{ type = "string", name = "Message", description = "Broadcast message (filtered)." },
		},
		run = function(context, message: string)
			runFacade(context, "announce", context.from, message)
		end,
	})

	_K.Registry.registerCommand(_K, {
		name = "announce",
		description = "Broadcast via Club Kit (club styling, gates + rate limit apply)",
		group = "Administration",
		args = {
			{ type = "string", name = "Message", description = "Broadcast message (filtered)." },
		},
		run = function(context, message: string)
			runFacade(context, "announce", context.from, message)
		end,
	})

	-- Live rank sync: Club Kit /setrole → Kohl's role (session mirror only).
	if RunService:IsServer() then
		task.spawn(function()
			local facade = getFacadeModule()
			if not facade then
				_K.log("[ClubKit] ExternalAdminFacade not found — rank sync inactive", "ERROR")
				return
			end
			-- Self-report presence so facade startup detection works regardless
			-- of Kohl's globals/version.
			if type(facade.reportAdminPresent) == "function" then
				facade.reportAdminPresent("Kohls")
			end
			for _ = 1, SYNC_POLL_ATTEMPTS do
				if facade.isEnabled() and facade.getProvider() == "Kohls" then
					facade.onRoleChanged(function(payload: any)
						if payload.provider ~= "Kohls" or type(payload.target) ~= "string" then
							return
						end
						local applied = false
						if payload.action == "give" then
							applied = _K.Auth.userRoleAdd(payload.userId, payload.target, false)
						elseif payload.action == "remove" then
							applied = _K.Auth.userRoleRemove(payload.userId, payload.target)
						end
						local rank = _K.Auth.getRank(payload.userId)
						print(`[ClubKitAddon] sync {payload.action} {tostring(payload.roleKey)} -> {tostring(payload.target)} for {tostring(payload.userId)} (applied={tostring(applied)}); kohls rank now {tostring(rank)}`)
					end)
					log("[ClubKit] Rank sync active (Kohls)")
					return
				end
				task.wait(SYNC_POLL_SECONDS)
			end
			log('[ClubKit] Provider is not "Kohls" (or facade stayed disabled) — rank sync inactive; commands still work when enabled')
		end)
	end
end
