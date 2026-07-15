--!strict
-- Server/Init/MusicBootstrap.luau
--
-- Wires MusicService + MusicController + ZoneTracker + favorites ProfileLoader
-- outside Main.server's top-level local register set (Luau limit 200).
-- Main only keeps hoisted musicFavoritesRepo / _musicService handles.

local Players = game:GetService("Players")

export type MusicBootstrapDeps = {
	musicConfig: any,
	groupId: number,
	overheadRepository: any,
	eventBus: any,
	remotes: Folder,
	notify: any,
	sharedProfileLoader: any,
	connectionCleaner: any,
	trackLifecycle: (name: string, module: any) -> any,
	Result: any,
	Logger: any,
	log: any,
}

export type MusicBootstrapResult = {
	musicService: any,
	musicFavoritesRepo: any,
}

local MusicBootstrap = {}

function MusicBootstrap.start(deps: MusicBootstrapDeps): MusicBootstrapResult
	local createMusicService = require(script.Parent.Parent.Services.MusicService)
	local createZoneTrackerService = require(script.Parent.Parent.Services.ZoneTrackerService)
	local createMusicController = require(script.Parent.Parent.Controllers.MusicController)
	local MusicRepository = require(script.Parent.Parent.Repositories.MusicRepository)
	local MusicFavoritesRepository = require(script.Parent.Parent.Repositories.MusicFavoritesRepository)

	local musicConfig = deps.musicConfig
	local Logger = deps.Logger
	local Result = deps.Result
	local log = deps.log
	local sharedProfileLoader = deps.sharedProfileLoader
	local connectionCleaner = deps.connectionCleaner

	local musicRepo = MusicRepository.new({
		config = musicConfig,
		logger = Logger.new("MusicRepository"),
	})
	local musicFavoritesRepo = MusicFavoritesRepository.new({
		config = musicConfig,
		logger = Logger.new("MusicFavoritesRepository"),
	})

	-- Fold music favorites GetAsync into SharedProfileLoader (separate from
	-- SyncDance FavoritesRepository). MusicService.onPlayerAdded still runs
	-- for session/rank; repo onPlayerAdded is idempotent if already loaded.
	sharedProfileLoader:register("music_favorites", function(player: Player)
		musicFavoritesRepo:onPlayerAdded(player)
		return Result.Ok(true)
	end)
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		sharedProfileLoader:enqueueKindDeferred(existingPlayer, "music_favorites")
	end
	connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
		sharedProfileLoader:enqueueKindDeferred(player, "music_favorites")
	end))

	local musicService = createMusicService({
		repo = musicRepo,
		favoritesRepository = musicFavoritesRepo,
		overheadRepository = deps.overheadRepository,
		eventBus = deps.eventBus,
		logger = Logger.new("MusicService"),
		config = musicConfig,
		groupId = deps.groupId,
		loadFavoritesOnJoin = false,
	})

	local musicInitOk, musicInitErr = pcall(function()
		musicService:init()
	end)
	if not musicInitOk then
		log:error("MusicService init failed", { error = tostring(musicInitErr) })
	end

	local musicControllerOk, musicControllerErr = pcall(function()
		createMusicController({
			service = musicService,
			remotes = deps.remotes,
			logger = Logger.new("MusicController"),
			config = musicConfig,
			notify = deps.notify,
		}):init()
	end)
	if not musicControllerOk then
		log:error("MusicController init failed", { error = tostring(musicControllerErr) })
	end

	-- Zone tracker: detects which tagged BasePart each player is inside and
	-- routes them to the matching MusicSession. No-op when Music.MODE = "global".
	deps.trackLifecycle(
		"ZoneTrackerService",
		createZoneTrackerService.create({
			musicService = musicService,
			logger = Logger.new("ZoneTrackerService"),
		})
	)

	-- Session/rank sync only — favorites load via SharedProfileLoader above.
	connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if player and player.Parent then
				musicService:onPlayerAdded(player)
			end
		end)
	end))
	for _, existingPlayer in Players:GetPlayers() do
		task.defer(function()
			if existingPlayer and existingPlayer.Parent then
				musicService:onPlayerAdded(existingPlayer)
			end
		end)
	end

	return {
		musicService = musicService,
		musicFavoritesRepo = musicFavoritesRepo,
	}
end

return MusicBootstrap
