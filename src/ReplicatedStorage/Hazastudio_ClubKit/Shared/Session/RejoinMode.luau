--!strict
-- Detects "this join is an AFK auto-rejoin" from teleport data, once.
-- Consumed by LoadingBootstrap (skip loading), JoinCommunityPromptController
-- (skip prompt), and Main.client (instant dance/music restore) so a rejoin
-- lands seamlessly instead of replaying the first-join interruptions.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local RejoinMode = {}

local cached: boolean? = nil

-- The server writes teleportData = { sessionRestore = { afkRejoin = true, ... } }.
-- Read it from BOTH client surfaces: GetJoinData().TeleportData and
-- TeleportService:GetLocalPlayerTeleportData() (they should carry the same
-- payload, but reading both guards against one being empty on some clients).
local function readAfkRejoinFlag(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local function scan(td: any): boolean
		if type(td) ~= "table" then
			return false
		end
		local restore = (td :: any).sessionRestore
		if type(restore) == "table" and (restore :: any).afkRejoin == true then
			return true
		end
		-- Defensive: some writers may put afkRejoin at the top level.
		if (td :: any).afkRejoin == true then
			return true
		end
		return false
	end

	local okJoin, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if okJoin and type(joinData) == "table" then
		if scan((joinData :: any).TeleportData) then
			return true
		end
	end

	local okTd, localTd = pcall(function()
		return TeleportService:GetLocalPlayerTeleportData()
	end)
	if okTd and scan(localTd) then
		return true
	end

	return false
end

function RejoinMode.isAfkRejoin(): boolean
	if cached ~= nil then
		return cached
	end
	cached = readAfkRejoinFlag()
	return cached
end

return RejoinMode
