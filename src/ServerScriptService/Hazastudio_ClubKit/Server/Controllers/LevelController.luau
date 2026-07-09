--!strict
-- Server/Controllers/LevelController.lua
-- Listen sumber XP (chat + timer online), dispatch ke LevelService.
-- Juga handle command /setlevel untuk admin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local RateLimiter    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local function createLevelController(deps: {
	levelService       : any,
	overheadService    : any,
	overheadController : any,
	repo               : any,
})
	local levelService       = deps.levelService
	local overheadService    = deps.overheadService
	local overheadController = deps.overheadController
	local log                = Logger.new("LevelController")
	-- Cooldown chat per player untuk anti-spam XP
	local lastChatXp: {[number]: number} = {}
	-- Rate limiter untuk /setlevel command
	local setLevelLimiter = RateLimiter.new(10, 60)
	-- ----------------------------------------------------------
	-- Proses XP gain dan refresh overhead jika level up
	-- ----------------------------------------------------------
	local function giveXp(player: Player, amount: number)
		task.spawn(function()
			local result = levelService:addXp(player.UserId, amount)
			if not result.ok then
				return
			end
			local levelResult = result.value
			if levelResult ~= nil then
				overheadController:refreshPlayer(player)
				if levelResult.didLevelUp then
					log:debug("Overhead refreshed after level up", {
						player = player.Name,
						level = levelResult.newLevel,
					})
				else
					log:debug("Overhead refreshed after XP save", {
						player = player.Name,
						xp = levelResult.newXp,
					})
				end
			end
		end)
	end
	-- ----------------------------------------------------------
	-- XP dari chat
	-- ----------------------------------------------------------
	local function onPlayerChatted(player: Player, message: string)
		-- Cek apakah command - skip XP untuk command
		local lower = message:lower():match("^%s*(.-)%s*$") or ""
		if lower:match("^/") then
			-- Cek /setlevel command dulu
			local username, levelStr = lower:match("^/setlevel%s+(%S+)%s+(%d+)$")
			if username and levelStr then
				-- Auth check sebelum rate limit - cegah unauthorized waste rate limit slots
				local giverRole = overheadService:getRawGroupRole(player)
				if not OverheadDomain.canGift(giverRole) then
					return
				end
				if not setLevelLimiter:check(player.UserId) then return end
				local targetLevel = tonumber(levelStr)
				-- validasi range level (min 1, max MAX_LEVEL)
				if not targetLevel or targetLevel < 1 then return end
				if targetLevel > Config.Level.MAX_LEVEL then return end
				local target = (function()
					local uname = username:lower()
					for _, p in ipairs(Players:GetPlayers()) do
						if p.Name:lower() == uname then return p end
					end
					return nil
				end)()
				if not target then return end
				task.spawn(function()
					local result = levelService:setLevel(target.UserId, targetLevel)
					if result.ok then
						overheadController:refreshPlayer(target)
						log:info("Level set", {
							by     = player.Name,
							target = target.Name,
							level  = targetLevel,
						})
					end
				end)
			end
			return -- semua command skip XP
		end
		-- Cooldown anti-spam
		local now  = os.time()
		local last = lastChatXp[player.UserId] or 0
		if now - last < Config.Level.CHAT_COOLDOWN then return end
		lastChatXp[player.UserId] = now
		giveXp(player, Config.Level.XP_PER_CHAT)
	end
	-- ----------------------------------------------------------
	-- XP dari waktu online - timer per player
	-- ----------------------------------------------------------
	local function startOnlineTimer(player: Player)
		task.spawn(function()
			while player and player.Parent do
				task.wait(Config.Level.ONLINE_INTERVAL)
				if not player or not player.Parent then break end
				giveXp(player, Config.Level.XP_PER_MINUTE)
			end
		end)
	end
	-- ----------------------------------------------------------
	-- Flush XP saat player leave agar tidak hilang
	-- ----------------------------------------------------------
	local function onPlayerRemoving(player: Player)
		lastChatXp[player.UserId] = nil
		local result = levelService:flushPlayer(player.UserId)
		if result.ok and result.value and result.value.didLevelUp then
			log:debug("Level up on leave saved", { player = player.Name })
		elseif not result.ok then
			log:warn("Level XP flush failed on leave", {
				player = player.Name,
				error = result.error,
			})
		end
	end
	-- ----------------------------------------------------------
	-- Wire semua player
	-- ----------------------------------------------------------
	local function wirePlayer(player: Player)
		player.Chatted:Connect(function(msg)
			onPlayerChatted(player, msg)
		end)
		startOnlineTimer(player)
	end
	Players.PlayerAdded:Connect(wirePlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		wirePlayer(player)
	end
	log:info("LevelController initialized")
	return {}
end
return createLevelController
