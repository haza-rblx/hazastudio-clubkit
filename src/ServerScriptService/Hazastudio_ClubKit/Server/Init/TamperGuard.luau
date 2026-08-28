--!strict
-- Live-exploiter response (ADR 0006 Pillar 5), server half.
--
-- Creates a low-profile RemoteEvent the client saveinstance detector fires. On a
-- report: log it, optionally kick the reporting player, and beacon home
-- (best-effort). The reporter is always the sender, so this can never be used to
-- kick another player. This is a speed bump for lazy exploiters — the durable
-- protection is server-authoritative logic + the license/beacon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local TamperGuard = {}

local REMOTE_NAME = "ReportTamper"
local _started = false

function TamperGuard.start(licenseService: any?)
	if _started then
		return
	end
	_started = true

	local at = Config.AntiTamper or {}
	if at.SAVEINSTANCE_DETECT_ENABLED ~= true then
		return
	end
	local log = Logger.new("TamperGuard")

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

	local seen: { [number]: boolean } = {}
	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, reason: any)
		local userId = player.UserId
		if seen[userId] then
			return
		end
		seen[userId] = true

		log:warn("Exploit signal reported", {
			player = player.Name,
			userId = userId,
			reason = tostring(reason),
		})

		if licenseService and type(licenseService.reportTamper) == "function" then
			pcall(function()
				licenseService.reportTamper("saveinstance", { actor_id = userId, actor_name = player.Name })
			end)
		end

		if at.KICK_ON_DETECT == true then
			pcall(function()
				player:Kick(
					"Exploit tool detected. This kit is licensed software; asset extraction is not permitted."
				)
			end)
		end
	end)

	log:info("TamperGuard armed", {
		kick = at.KICK_ON_DETECT == true,
		brick = at.BRICK_ON_DETECT == true,
	})
end

return TamperGuard
