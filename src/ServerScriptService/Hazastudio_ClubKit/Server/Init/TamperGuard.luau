--!strict
-- Live-exploiter response (ADR 0006 Pillar 5, ADR 0012), server half.
--
-- Creates a low-profile RemoteEvent the client detectors fire. On a report: log it,
-- beacon home (best-effort), and — for the saveinstance signal only — optionally kick
-- the reporting player. The reporter is always the sender, so this can never be used to
-- kick another player. This is a speed bump for lazy exploiters — the durable
-- protection is server-authoritative logic + the license/beacon.
--
-- Two signals share the remote:
--   "saveinstance" — UGCValidationService probe (ADR 0006). May kick, if the owner opted in.
--   "foreign_gui"  — a GUI that was not in PlayerGui at boot (ADR 0012). LOG ONLY, always.
-- Each kind carries its own per-player budget, so a foreign-GUI report can no longer be
-- swallowed by an earlier saveinstance hit (and vice versa), and its own per-server
-- budget, so one exploiter cannot flood the owner's Discord feed.
--
-- EVERYTHING IN THE PAYLOAD IS HOSTILE. An exploiter can fire this remote directly with
-- any table at all, so the detail is re-parsed, re-capped and re-sanitised here through
-- ForeignGuiPolicy — the client's own pass is courtesy, not a guarantee.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ForeignGuiPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ForeignGuiPolicy)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local TamperGuard = {}

local REMOTE_NAME = "ReportTamper"
-- Hard stop on remote traffic per player per session, whatever the payload says. Every
-- check after this one costs work; this one costs a table lookup.
local MAX_FIRES_PER_PLAYER = 20
-- An unrecognised reason string (only a forged client sends one) gets a tiny budget of
-- its own rather than being counted against a real signal.
local OTHER_PLAYER_BUDGET = 1
local OTHER_SERVER_BUDGET = 4

local KIND_BY_REASON: { [string]: string } = {
	saveinstance = "saveinstance",
	foreign_gui = "foreign_gui",
}

local _started = false

function TamperGuard.start(licenseService: any?)
	if _started then
		return
	end
	_started = true

	local at = Config.AntiTamper or {}
	local saveInstanceEnabled = at.SAVEINSTANCE_DETECT_ENABLED == true
	local foreignGuiEnabled = at.FOREIGN_GUI_DETECT_ENABLED == true
	if not saveInstanceEnabled and not foreignGuiEnabled then
		return
	end
	local log = Logger.new("TamperGuard")

	local foreignPerPlayer = math.min(
		tonumber(at.FOREIGN_GUI_MAX_REPORTS_PER_PLAYER) or ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER,
		ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER
	)
	local foreignPerServer = math.min(
		tonumber(at.FOREIGN_GUI_MAX_REPORTS_PER_SERVER) or ForeignGuiPolicy.MAX_REPORTS_PER_SERVER,
		ForeignGuiPolicy.MAX_REPORTS_PER_SERVER
	)

	local kitFolder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	if not kitFolder then
		return
	end
	local secFolder = kitFolder:FindFirstChild("SecuritySignals")
	if not secFolder then
		secFolder = Instance.new("Folder")
		secFolder.Name = "SecuritySignals"
		secFolder.Parent = kitFolder
	end
	local remote = secFolder:FindFirstChild(REMOTE_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = secFolder
	end

	-- Per player: how many times they fired at all, how much of each kind's budget they
	-- have spent, and which GUI names they already named (one report per name). Keyed by
	-- userId for the life of the server and never cleared on leave, so rejoining does not
	-- hand an exploiter a fresh budget.
	local fires: { [number]: number } = {}
	local usedByKind: { [number]: { [string]: number } } = {}
	local namedGuis: { [number]: { [string]: boolean } } = {}
	-- Per server, so the feed stays readable no matter how many players are involved.
	local serverUsed: { [string]: number } = {}

	local function playerBudget(kind: string): number
		if kind == "saveinstance" then
			return 1
		elseif kind == "foreign_gui" then
			return foreignPerPlayer
		end
		return OTHER_PLAYER_BUDGET
	end

	-- saveinstance is already one-per-player, so its server bound is the player count.
	local function serverBudget(kind: string): number?
		if kind == "foreign_gui" then
			return foreignPerServer
		elseif kind == "saveinstance" then
			return nil
		end
		return OTHER_SERVER_BUDGET
	end

	local function beacon(reason: string, extra: { [string]: any })
		if licenseService and type(licenseService.reportTamper) == "function" then
			pcall(function()
				licenseService.reportTamper(reason, extra)
			end)
		end
	end

	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, reason: any, payload: any)
		local userId = player.UserId

		local fired = (fires[userId] or 0) + 1
		fires[userId] = fired
		if fired > MAX_FIRES_PER_PLAYER then
			return
		end

		local kind = KIND_BY_REASON[if type(reason) == "string" then reason else ""] or "other"
		if kind == "saveinstance" and not saveInstanceEnabled then
			return
		end
		if kind == "foreign_gui" and not foreignGuiEnabled then
			return
		end

		local used = usedByKind[userId]
		if not used then
			used = {}
			usedByKind[userId] = used
		end
		local spent = used[kind] or 0
		if spent >= playerBudget(kind) then
			return
		end
		local cap = serverBudget(kind)
		local serverSpent = serverUsed[kind] or 0
		if cap and serverSpent >= cap then
			return
		end

		if kind == "foreign_gui" then
			local info = ForeignGuiPolicy.normalize(payload)
			if not info then
				return
			end
			local named = namedGuis[userId]
			if not named then
				named = {}
				namedGuis[userId] = named
			end
			if named[info.name] then
				return
			end
			named[info.name] = true
			used[kind] = spent + 1
			serverUsed[kind] = serverSpent + 1

			local detail = ForeignGuiPolicy.buildDetail(info)
			log:warn("Foreign GUI reported", {
				player = player.Name,
				userId = userId,
				gui = info.name,
				className = info.className,
				scripts = info.scriptCount,
				descendants = info.descendants,
				detail = detail,
			})
			-- Key per GUI name so two different tools beacon separately; the budgets above
			-- (and LicenseService's own key ceiling) bound how many that can ever be.
			beacon(ForeignGuiPolicy.reasonKey(info.name), {
				actor_id = userId,
				actor_name = player.Name,
				detail = detail,
			})
			return
		end

		used[kind] = spent + 1
		serverUsed[kind] = serverSpent + 1

		log:warn("Exploit signal reported", {
			player = player.Name,
			userId = userId,
			reason = tostring(reason),
			kind = kind,
		})

		beacon(if kind == "saveinstance" then "saveinstance" else "unknown_signal", {
			actor_id = userId,
			actor_name = player.Name,
		})

		-- Kick belongs to the saveinstance signal only. The foreign-GUI signal never
		-- ejects anyone (ADR 0012): it has no field data yet and a false positive costs
		-- a paying guest.
		if kind == "saveinstance" and at.KICK_ON_DETECT == true then
			pcall(function()
				player:Kick(
					"Exploit tool detected. This kit is licensed software; asset extraction is not permitted."
				)
			end)
		end
	end)

	log:info("TamperGuard armed", {
		saveinstance = saveInstanceEnabled,
		foreignGui = foreignGuiEnabled,
		kick = at.KICK_ON_DETECT == true,
		brick = at.BRICK_ON_DETECT == true,
		foreignPerPlayer = foreignPerPlayer,
		foreignPerServer = foreignPerServer,
	})
end

return TamperGuard
