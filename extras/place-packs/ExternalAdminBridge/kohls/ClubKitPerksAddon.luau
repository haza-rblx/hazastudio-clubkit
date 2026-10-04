--!strict
--[[
	Club Kit ↔ Kohl's Admin member-perk addon (External Admin Bridge pack).

	Install: ModuleScript named "ClubKitPerksAddon" inside Kohl's Admin
	"Config > Addons". Do NOT put "Client" or "Server" in the name — command
	definitions must register in BOTH contexts (client Registry needs them for
	visibility/arg parsing; the gated run() only ever executes on the server).

	Requires the sibling ClubKitAddon (bridge pack) and
	ClubKitConfig.ExternalAdmin.Provider = "Kohls" with a Perks section.

	What it does:
	- Overrides Kohl's native fly/unfly/smite with member-gated versions
	  (group "ClubPerks"). Staff (kit staff roles + Perks.StaffBypass) delegate
	  to the original command implementations — native power preserved.
	- fly: Perks.Fly tiers (default VVIP+), self-target only for members.
	- smite: Perks.Smite tiers (default Exclusive) — number = weekly quota
	  (ISO week, resets Mon 00:00 UTC) enforced server-side through the Club
	  Kit DataStore via ExternalAdminFacade.consumePerkQuota. Members may smite
	  other players; each use consumes one unit.
	- Mirrors effective membership into ephemeral Kohl's perk roles
	  (perkTier2 / perkTier3) so onlyShowUsableCommands hides the commands from
	  players without the tier. Roles must exist in Config > Settings
	  (Settings.snippet.luau section 5).
	- Gating re-checks live on every run: a revoked/gifted member flips as soon
	  as the kit's overhead payload updates.
]]

local RunService = game:GetService("RunService")

local PERK_ROLE = { Tier2 = "perkTier2", Tier3 = "perkTier3" }

local function getFacade(): any?
	if not RunService:IsServer() then
		return nil -- client never gates; definitions still register below
	end
	local kit = game:GetService("ServerScriptService"):FindFirstChild("Hazastudio_ClubKit")
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

return function(_K)
	local facade = getFacade()
	if RunService:IsServer() and not facade then
		_K.log("[ClubKitPerks] ExternalAdminFacade not found - Club Kit engine missing or outdated; perks inactive", "ERROR")
		return
	end

	local function getPerksConfig(): any
		if not facade then
			return nil
		end
		local ok, result = pcall(facade.getPerksConfig)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	local function notify(player: Player, text: string)
		_K.Remote.Notify:Fire(player, { Text = text })
	end

	-- ------------------------------------------------------------------
	-- Membership -> perk-role mirror (visibility only; gating is live)
	-- ------------------------------------------------------------------
	if RunService:IsServer() and facade then
		task.spawn(function()
			-- Self-report so kit startup detection sees the perks addon too.
			if type(facade.reportAdminPresent) == "function" then
				facade.reportAdminPresent("Kohls")
			end
			-- Kohl's loaders boot well before the kit (observed: facade initialises
			-- about 70 s after this addon). An immediate isEnabled() check exits early and
			-- the mirror dies permanently -> members never get their perk role and
			-- Kohl's answers "command restricted" before our gated run() ever fires.
			-- Poll until the facade is live (or give up after ~2 minutes).
			local MIRROR_POLL_SECONDS = 2
			local MIRROR_POLL_ATTEMPTS = 60
			for _ = 1, MIRROR_POLL_ATTEMPTS do
				if facade.isEnabled() then
					break
				end
				task.wait(MIRROR_POLL_SECONDS)
			end
			if not facade.isEnabled() or facade.getProvider() ~= "Kohls" then
				_K.log("[ClubKitPerks] Provider is not \"Kohls\" (or facade stayed disabled) - perk roles inactive (commands still gate live)", "INFO")
				return
			end
			local tierForMembership = facade.tierForMembershipKey
			local desiredRole: { [number]: string? } = {}
			local function applyRole(userId: number, membership: any)
				local tier = tierForMembership(membership)
				local want = if tier == "Tier3" then PERK_ROLE.Tier3 elseif tier == "Tier2" then PERK_ROLE.Tier2 else nil
				local had = desiredRole[userId]
				if want ~= had then
					if had then
						_K.Auth.userRoleRemove(userId, had)
					end
					if want then
						local added = _K.Auth.userRoleAdd(userId, want, false)
						if not added then
							_K.log(`[ClubKitPerks] userRoleAdd({userId}, {want}) returned false - role missing from Settings roles?`, "ERROR")
						end
					end
					desiredRole[userId] = want
				end
			end
			if type(facade.onMembershipChanged) == "function" then
				facade.onMembershipChanged(function(payload)
					applyRole(payload.userId, payload.effectiveMembership)
				end)
			end
			-- Seed players already in server (late kit boot after this poll).
			for _, player in ipairs(_K.Service.Players:GetPlayers()) do
				local result = facade.getMembership(player.UserId)
				if result and result.ok then
					applyRole(player.UserId, result.value)
				end
			end
			_K.log("[ClubKitPerks] Membership mirror active (Kohls)", "INFO")
		end)
	end

	-- ------------------------------------------------------------------
	-- Gated command wrappers (registered in both contexts)
	-- ------------------------------------------------------------------
	local function native(name: string)
		return _K.Registry.commands[name]
	end

	-- Returns pass, info. info.staff = delegate to native run for ALL targets.
	local function gate(context: any, perk: string): (boolean, any?)
		if not facade then
			return false, nil
		end
		-- Kohl's gates the command BEFORE run() (Auth.hasCommand via role groups).
		-- If the membership mirror has not applied this player's perk role yet
		-- (early window after boot, or the payload feed missed a change), apply it
		-- right now so hasCommand passes; our own checkPerk below is the real
		-- authority either way.
		if facade.isEnabled() and facade.getProvider() == "Kohls" then
			local tierForMembership = facade.tierForMembershipKey
			local membershipResult = facade.getMembership(context.from)
			if membershipResult and membershipResult.ok then
				local tier = tierForMembership(membershipResult.value)
				local want = if tier == "Tier3" then PERK_ROLE.Tier3 elseif tier == "Tier2" then PERK_ROLE.Tier2 else nil
				if want and not _K.Auth.hasCommand(context.from, _K.Registry.commands[if perk == "Fly" then "fly" else "smite"]) then
					local rank = _K.Auth.getRank(context.from)
					if rank == 0 or _K.Auth.userRoleAdd(context.from, want, false) then
						-- role applied (or already implied by another held role)
					end
				end
			end
		end
		local perks = getPerksConfig()
		if perks == nil or perks.Enabled == false then
			notify(context.fromPlayer, `<font color="#f66">Club perks are currently disabled.</font>`)
			return false, nil
		end
		local gateResult = facade.checkPerk(context.from, perk)
		if not (gateResult.ok and type(gateResult.value) == "table") then
			notify(context.fromPlayer, `<font color="#f66">The {perk} perk is not available right now.</font>`)
			return false, nil
		end
		local perkGate = gateResult.value
		if not perkGate.allowed then
			if perkGate.reason == "staff_bypass" then
				return true, { staff = true }
			end
			if perkGate.reason == "below_tier" then
				local minTier = if perkGate.minTier then ` ({tostring(perkGate.minTier)}+)` else ""
				notify(context.fromPlayer, `<font color="#fc6">The <b>{perk}</b> perk needs a higher membership tier{minTier}.</font>`)
				return false, nil
			end
			notify(context.fromPlayer, `<font color="#f66">The {perk} perk is not available right now.</font>`)
			return false, nil
		end
		return true, { staff = false, tier = perkGate.tier, quota = perkGate.quota }
	end

	local function runAsSelf(context: any, nativeCommand: any, players: { Player }, ...: any)
		local me = context.fromPlayer
		for _, player in ipairs(players) do
			if player == me then
				return nativeCommand.run(context, { me }, ...)
			end
		end
	end

	local function wrapFly(unfly: boolean)
		local name = if unfly then "unfly" else "fly"
		local nativeCommand = native(name)
		return {
			name = name,
			description = if unfly then "Disables flight (member perk)." else "Enables flight (member perk, VVIP+).",
			group = "ClubPerks",
			args = if nativeCommand
				then nativeCommand.args
				else {
					{
						type = "players",
						name = "Player(s)",
						description = "The player(s) to toggle flight for.",
					},
				},
			run = function(context, players, speed, constant)
				local pass, info = gate(context, "Fly")
				if not pass then
					return
				end
				if info.staff then
					return nativeCommand.run(context, players, speed, constant)
				end
				-- Members: self only. unfly on self stays free (fair exit).
				return runAsSelf(context, nativeCommand, players, speed, constant)
			end,
		}
	end

	_K.Registry.registerCommand(_K, wrapFly(false))
	_K.Registry.registerCommand(_K, wrapFly(true))

	local nativeSmite = native("smite")
	_K.Registry.registerCommand(_K, {
		name = "smite",
		description = "Smite a player (member perk: Exclusive, free weekly uses).",
		group = "ClubPerks",
		args = if nativeSmite
			then nativeSmite.args
			else {
				{
					type = "players",
					name = "Player(s)",
					description = "The player(s) to smite.",
					shouldRequest = true,
				},
			},
		run = function(context, players)
			local pass, info = gate(context, "Smite")
			if not pass then
				return
			end
			if info.staff then
				return nativeSmite.run(context, players)
			end
			-- Members may smite anyone; capped perks consume one unit first.
			local quota = info.quota
			if type(quota) == "number" then
				local consume = facade.consumePerkQuota(context.from, "Smite", quota)
				if not (consume.ok and type(consume.value) == "number") then
					if consume.error == "perk_quota_exhausted" then
						notify(context.fromPlayer, `<font color="#f66">⚠ Weekly smite quota used up ({quota}/{quota}). Resets Monday 00:00 UTC.</font>`)
					else
						notify(context.fromPlayer, `<font color="#f66">Could not check your smite quota - try again in a moment.</font>`)
					end
					return
				end
				local remaining = consume.value :: number
				if remaining > 0 then
					notify(context.fromPlayer, `<font color="#6f6">⚡ Smite used — <b>{quota - remaining}/{quota} this week</b> · {remaining} free smite(s) left.</font>`)
				else
					notify(context.fromPlayer, `<font color="#fc6">⚡ Smite used — <b>{quota}/{quota} this week</b> · that was your last free smite! Weekly quota resets Monday 00:00 UTC.</font>`)
				end
			end
			return nativeSmite.run(context, players)
		end,
	})
end
