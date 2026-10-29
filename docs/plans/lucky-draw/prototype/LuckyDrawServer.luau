--!strict
-- ServerScriptService.LuckyDrawServer (Script)
-- Lucky Draw: admin-gated random player pick, broadcast to every client.
-- Standalone: does not touch the kit's Main.server.
--
-- Admin gate: the kit's overheadService is only reachable inside Main, so this script
-- rebuilds the role from the group rank (Player:GetRankInGroup -> OverheadDomain.resolveRole),
-- then PermissionDomain.canUseAdminPanel (which also covers Config.AdminUserIds and the owner).
-- In Studio the place owner (game.CreatorId) is always allowed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KIT = ReplicatedStorage:WaitForChild("Hazastudio_ClubKit")
local Config = require(KIT.Shared.Constants.Config)
local OverheadDomain = require(KIT.Shared.Domain.OverheadDomain)
local PermissionDomain = require(KIT.Shared.Domain.PermissionDomain)

local SPIN_LEAD = 0.35
local SPIN_DURATION = 4.6
local COOLDOWN = 1.0
local STUDIO_MIN_POOL = 12

local remotesFolder = ReplicatedStorage:FindFirstChild("LuckyDrawRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "LuckyDrawRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureEvent(name: string): RemoteEvent
	local ev = remotesFolder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotesFolder
	end
	return ev :: any
end

local requestEvent = ensureEvent("Request")
local broadcastEvent = ensureEvent("Broadcast")

local busyUntil = 0

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return true
	end
	local rank = 0
	local groupId = tonumber(Config.Group.GROUP_ID) or 0
	if groupId > 0 then
		local ok, value = pcall(function()
			return player:GetRankInGroup(groupId)
		end)
		if ok and type(value) == "number" then
			rank = value
		end
	end
	local role = OverheadDomain.resolveRole(rank, player.UserId)
	return PermissionDomain.canUseAdminPanel(role, player.UserId)
end

local function buildPool(host: Player): { any }
	local pool: { any } = {}
	local seen: { [number]: boolean } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		seen[p.UserId] = true
		table.insert(pool, { userId = p.UserId, displayName = p.DisplayName, username = p.Name, fake = false })
	end
	-- TEST PADDING (Studio only): fill up to 12 with the host's friends, page 1.
	if RunService:IsStudio() and #pool < STUDIO_MIN_POOL then
		local ok, pages = pcall(function()
			return Players:GetFriendsAsync(host.UserId)
		end)
		if ok and pages then
			local okPage, list = pcall(function()
				return pages:GetCurrentPage()
			end)
			if okPage and type(list) == "table" then
				for _, f in ipairs(list) do
					if #pool >= STUDIO_MIN_POOL then
						break
					end
					if not seen[f.Id] then
						seen[f.Id] = true
						table.insert(pool, { userId = f.Id, displayName = f.DisplayName, username = f.Username, fake = true })
					end
				end
			end
		end
	end
	return pool
end

requestEvent.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" or payload.type ~= "spin" then
		return
	end
	if not isAdmin(player) then
		print("[LuckyDraw] spin rejected (not admin): " .. player.Name)
		return
	end
	local now = os.clock()
	if now < busyUntil then
		print("[LuckyDraw] spin rejected (in flight or cooling down)")
		return
	end

	local pool = buildPool(player)
	if #pool == 0 then
		return
	end
	local rng = Random.new()
	local seed = rng:NextInteger(1, 2147483646)
	local winnerIndex = rng:NextInteger(1, #pool)
	local startAt = workspace:GetServerTimeNow() + SPIN_LEAD
	busyUntil = now + SPIN_LEAD + SPIN_DURATION + COOLDOWN

	broadcastEvent:FireAllClients({
		type = "spin",
		host = { userId = player.UserId, displayName = player.DisplayName },
		pool = pool,
		winnerIndex = winnerIndex,
		seed = seed,
		startAt = startAt,
		duration = SPIN_DURATION,
	})
	print("[LuckyDraw] spin started by " .. player.Name .. " (pool " .. tostring(#pool) .. ")")
end)
