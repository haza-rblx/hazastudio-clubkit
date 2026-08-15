--!strict
--[[
	Club Kit ↔ Adonis bridge (External Admin Bridge pack).

	Install: ModuleScript named exactly "Server-ClubKitBridge" inside
	Adonis_Loader > Config > Plugins (server plugin names MUST start with
	"Server:" or "Server-"). Official Adonis loader only:
	https://www.roblox.com/library/7510622625/

	Behaviour:
	- Adds :cksetrole / :ckunsetrole / :ckgift / :ckungift / :ckannounce
	  (AdminLevel "Admins") which call the Club Kit ExternalAdminFacade.
	  Club Kit permission gates still apply — an Adonis admin without a
	  kit-side privileged role gets "no_perm" (by design).
	- Mirrors Club Kit staff role changes into Adonis ranks (session/temp
	  only — Club Kit's DataStore stays the source of truth).
	- No-op when ClubKitConfig.ExternalAdmin.Provider ~= "Adonis" or the
	  facade is missing (engine too old / not installed).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local SYNC_POLL_SECONDS = 2
local SYNC_POLL_ATTEMPTS = 30 -- ~1 minute: Club Kit Main may boot after Adonis

return function(Vargs)
	local server, service = Vargs.Server, Vargs.Service

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

	local facade = getFacadeModule()
	if not facade then
		warn("[ClubKitBridge] ExternalAdminFacade not found — Club Kit engine missing or outdated; bridge disabled")
		return
	end
	-- Self-report presence so facade startup detection works even when the
	-- loader renamed itself and G_API is off.
	if type(facade.reportAdminPresent) == "function" then
		facade.reportAdminPresent("Adonis")
	end

	local function notify(plr: Player, text: string)
		if server.Functions and type(server.Functions.Hint) == "function" then
			server.Functions.Hint(text, { plr })
		end
	end

	local function report(plr: Player, result: any)
		if type(result) == "table" and result.ok then
			notify(plr, "[ClubKit] Done.")
			print("[ClubKitBridge] command ok by " .. plr.Name)
		else
			local err = type(result) == "table" and tostring(result.error) or "unknown error"
			notify(plr, "[ClubKit] Failed: " .. err)
			print("[ClubKitBridge] command failed for " .. plr.Name .. ": " .. err)
		end
	end

	local function resolveTarget(plr: Player, arg: any): Player?
		if typeof(arg) == "Instance" and arg:IsA("Player") then
			return arg :: Player
		end
		if type(arg) ~= "string" or arg == "" then
			return nil
		end
		local targets = server.Functions.GetPlayers(plr, arg)
		if type(targets) == "table" and #targets > 0 then
			return targets[1]
		end
		return nil
	end

	local prefix = server.Settings.Prefix

	server.Commands.ClubKitSetRole = {
		Prefix = prefix,
		Commands = { "cksetrole" },
		Args = { "player", "role" },
		Description = "Give a Club Kit role (Staff, Moderator, DJ, ...) via Club Kit",
		Hidden = false,
		Fun = false,
		AdminLevel = "Admins",
		Function = function(plr: Player, args: { any })
			local target = resolveTarget(plr, args[1])
			if not target then
				notify(plr, "[ClubKit] Player not found: " .. tostring(args[1]))
				return
			end
			report(plr, facade.setRole(plr.UserId, target.UserId, args[2]))
		end,
	}

	server.Commands.ClubKitUnsetRole = {
		Prefix = prefix,
		Commands = { "ckunsetrole" },
		Args = { "player" },
		Description = "Remove a player's gifted Club Kit role",
		Hidden = false,
		Fun = false,
		AdminLevel = "Admins",
		Function = function(plr: Player, args: { any })
			local target = resolveTarget(plr, args[1])
			if not target then
				notify(plr, "[ClubKit] Player not found: " .. tostring(args[1]))
				return
			end
			report(plr, facade.unsetRole(plr.UserId, target.UserId))
		end,
	}

	server.Commands.ClubKitGift = {
		Prefix = prefix,
		Commands = { "ckgift" },
		Args = { "player", "tier" },
		Description = "Gift Club Kit membership (vip / vvip / supreme)",
		Hidden = false,
		Fun = false,
		AdminLevel = "Admins",
		Function = function(plr: Player, args: { any })
			local target = resolveTarget(plr, args[1])
			if not target then
				notify(plr, "[ClubKit] Player not found: " .. tostring(args[1]))
				return
			end
			report(plr, facade.giftMembership(plr.UserId, target.UserId, args[2]))
		end,
	}

	server.Commands.ClubKitUngift = {
		Prefix = prefix,
		Commands = { "ckungift" },
		Args = { "player", "tier" },
		Description = "Remove a gifted Club Kit membership tier",
		Hidden = false,
		Fun = false,
		AdminLevel = "Admins",
		Function = function(plr: Player, args: { any })
			local target = resolveTarget(plr, args[1])
			if not target then
				notify(plr, "[ClubKit] Player not found: " .. tostring(args[1]))
				return
			end
			report(plr, facade.ungiftMembership(plr.UserId, target.UserId, args[2]))
		end,
	}

	server.Commands.ClubKitAnnounce = {
		Prefix = prefix,
		Commands = { "ckannounce" },
		Args = { "message" },
		Description = "Send a Club Kit broadcast (uses Club Kit announce gates + rate limit)",
		Hidden = false,
		Fun = false,
		AdminLevel = "Admins",
		Function = function(plr: Player, args: { any })
			report(plr, facade.announce(plr.UserId, args[1]))
		end,
	}

	-- Live rank sync: Club Kit /setrole → Adonis temp rank (session mirror only).
	task.spawn(function()
		for _ = 1, SYNC_POLL_ATTEMPTS do
			if facade.isEnabled() and facade.getProvider() == "Adonis" then
				facade.onRoleChanged(function(payload: any)
					if payload.provider ~= "Adonis" or type(payload.target) ~= "number" then
						return
					end
					local target = Players:GetPlayerByUserId(payload.userId)
					if not target then
						return
					end
					if payload.action == "give" then
						server.Admin.AddAdmin(target, payload.target, true)
					elseif payload.action == "remove" then
						server.Admin.RemoveAdmin(target, true)
					end
					local level = server.Admin.GetLevel(target)
					print(`[ClubKitBridge] sync {payload.action} {tostring(payload.roleKey)} -> {tostring(payload.target)} for {target.Name}; adonis level now {tostring(level)}`)
				end)
				print("[ClubKitBridge] Rank sync active (Adonis)")
				return
			end
			task.wait(SYNC_POLL_SECONDS)
		end
		warn("[ClubKitBridge] Provider is not \"Adonis\" (or facade stayed disabled) — rank sync inactive; commands still work when enabled")
	end)
end
