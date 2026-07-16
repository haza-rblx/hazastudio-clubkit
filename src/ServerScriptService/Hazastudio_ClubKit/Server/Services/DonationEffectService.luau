--!strict

local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)
local DonationEffectTierResolver = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationEffectTierResolver)

type ILogger = Types.ILogger
type Result<T> = Types.Result<T>

type DonationEffectTier = DonationEffectTierResolver.AuraTier

export type DonationEffectService = {
	playRobuxDonation: (self: DonationEffectService, player: Player, amount: number) -> Result<nil>,
	playCashDonation: (self: DonationEffectService, player: Player, idrAmount: number) -> Result<nil>,
	playSaweriaDonation: (self: DonationEffectService, player: Player, idrAmount: number) -> Result<nil>,
	onPlayerRemoving: (self: DonationEffectService, player: Player) -> (),
}

local function createDonationEffectService(deps: {
	logger: ILogger,
	-- Optional camera trigger. Called for tiers with `cameraDuration > 0`.
	-- Wired to CinematicDockController in Main.server.
	cameraTrigger: ((targetPlayer: Player, durationSeconds: number) -> ())?,
}): DonationEffectService
	local log = deps.logger
	local cameraTrigger = deps.cameraTrigger
	-- Per-player FIFO queue. Prevents donation N+1 effects from overlapping
	-- the full cycle (aura + camera + notif) of donation N.
	local queueByUserId: { [number]: { any } } = {}
	local workerThreadByUserId: { [number]: thread } = {}
	local MAX_QUEUE_DEPTH = 16
	local QUEUE_BUFFER = 0.5 -- extra gap between cycles for clean transitions

	-- Global nuke queue: cap concurrent world-position Nuke/Smite/BlackHole VFX
	-- via Config.NetworkPerf.DONATION_VFX_MAX_CONCURRENT (0 = disable enqueue).
	-- Duration = WORLD_EFFECT_DURATIONS[effect] matching client EffectDonate
	-- lifetimes; fallback NUKE_DEFAULT_DURATION. Client also single-flights.
	-- Do NOT enable NukeEffectController alongside EffectDonate (double VFX).
	local nukeQueue: { { player: Player, source: string, amount: number } } = {}
	local activeWorldVfx = 0

	local function getWorldVfxMaxConcurrent(): number
		local np = Config.NetworkPerf
		if type(np) == "table" and type(np.DONATION_VFX_MAX_CONCURRENT) == "number" then
			return math.max(0, math.floor(np.DONATION_VFX_MAX_CONCURRENT))
		end
		return 1
	end

	local function getWorldEffectDuration(effectName: string): number
		local donation = Config.Donation :: any
		local map = donation.WORLD_EFFECT_DURATIONS
		if type(map) == "table" then
			local configured = map[effectName]
			if type(configured) == "number" and configured > 0 then
				return configured
			end
		end
		local fallback = donation.NUKE_DEFAULT_DURATION
		if type(fallback) == "number" and fallback > 0 then
			return fallback
		end
		return 90
	end

	local function getDonationConfig(): { [string]: any }
		return Config.Donation :: any
	end

	local function getStringConfig(name: string, fallback: string): string
		local value = getDonationConfig()[name]
		if type(value) ~= "string" or value == "" then
			return fallback
		end
		return value
	end

	local function findAssetFolder(folderName: string): Instance?
		local direct = ServerStorage:FindFirstChild(folderName)
		if direct then
			return direct
		end

		for _, child in ipairs(ServerStorage:GetChildren()) do
			local nested = child:FindFirstChild(folderName)
			if nested then
				return nested
			end
		end

		return nil
	end

	local function getTierByRobux(amount: number): DonationEffectTier?
		return DonationEffectTierResolver.resolveAuraByRobux(amount)
	end

	local function getTierByIdr(idrAmount: number): DonationEffectTier?
		return DonationEffectTierResolver.resolveAuraByIdr(idrAmount)
	end

	local function getCharacterRoot(player: Player): (Model?, BasePart?)
		local character = player.Character
		if not character then
			return nil, nil
		end

		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			return character, humanoidRootPart
		end

		local upperTorso = character:FindFirstChild("UpperTorso")
		if upperTorso and upperTorso:IsA("BasePart") then
			return character, upperTorso
		end

		local torso = character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			return character, torso
		end

		return character, nil
	end

	local function findFirstBasePart(instance: Instance): BasePart?
		if instance:IsA("BasePart") then
			return instance
		end

		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end

		return nil
	end

	local function getBaseParts(instance: Instance): { BasePart }
		local parts = {}
		if instance:IsA("BasePart") then
			table.insert(parts, instance)
		end

		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end

		return parts
	end

	-- Anchor/placeholder parts in legacy aura models (often named "BasePart")
	-- must stay welded for positioning but should never render on the character.
	local HIDDEN_EFFECT_PART_NAMES: { [string]: boolean } = {
		basepart = true,
		anchor = true,
		root = true,
		hitbox = true,
		collision = true,
		primary = true,
	}

	local function partHasRenderableVisual(part: BasePart): boolean
		if part:IsA("MeshPart") and part.MeshId ~= "" and part.Transparency < 1 then
			return true
		end

		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") or child:IsA("Beam") or child:IsA("Trail") then
				return true
			end
			if child:IsA("Decal") or child:IsA("Texture") then
				return true
			end
			if child:IsA("SpecialMesh") and child.MeshId ~= "" then
				return true
			end
		end

		for _, descendant in ipairs(part:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
				return true
			end
			if descendant:IsA("Decal") or descendant:IsA("Texture") then
				return true
			end
			if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
				return true
			end
		end

		return false
	end

	local function shouldHideEffectPart(part: BasePart): boolean
		if HIDDEN_EFFECT_PART_NAMES[string.lower(part.Name)] then
			return true
		end
		return not partHasRenderableVisual(part)
	end

	local function normalizeEffectParts(effect: Instance, attachPart: BasePart)
		for _, part in ipairs(getBaseParts(effect)) do
			if shouldHideEffectPart(part) then
				part.Transparency = 1
				part.CastShadow = false
			end

			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Name = "HazastudioDonationEffectWeld"
			weld.Part0 = attachPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local function positionEffect(effect: Instance, character: Model, attachPart: BasePart)
		local effectPart = findFirstBasePart(effect)
		if not effectPart then
			effect.Parent = character
			return
		end

		if effect:IsA("Model") then
			effect:PivotTo(attachPart.CFrame)
		elseif effect:IsA("BasePart") then
			effect.CFrame = attachPart.CFrame
		else
			local transform = attachPart.CFrame * effectPart.CFrame:Inverse()
			for _, part in ipairs(getBaseParts(effect)) do
				part.CFrame = transform * part.CFrame
			end
		end

		effect.Parent = character
		normalizeEffectParts(effect, attachPart)
	end

	local function findSoundTemplate(soundsFolder: Instance, soundName: string): Sound?
		local direct = soundsFolder:FindFirstChild(soundName)
		if direct and direct:IsA("Sound") then
			return direct
		end

		if direct then
			local nested = direct:FindFirstChildWhichIsA("Sound", true)
			if nested then
				return nested
			end
		end

		return nil
	end

	local function playSound(
		soundsFolder: Instance,
		soundName: string,
		attachPart: BasePart,
		duration: number
	): Result<nil>
		local soundTemplate = findSoundTemplate(soundsFolder, soundName)
		if not soundTemplate then
			return Result.Err("sound_not_found")
		end

		if soundTemplate:IsA("Sound") and SoundAssetSanitizer.isBlockedSoundId(soundTemplate.SoundId) then
			return Result.Ok(nil)
		end

		local sound = soundTemplate:Clone()
		SoundAssetSanitizer.removeBlockedSounds(sound)
		if sound:IsA("Sound") and SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
			sound:Destroy()
			return Result.Ok(nil)
		end
		sound.Name = "HazastudioDonationSound"
		sound.Parent = attachPart
		sound:Play()
		Debris:AddItem(sound, math.max(duration, sound.TimeLength + 1))

		return Result.Ok(nil)
	end

	-- Nuke broadcast UnreliableRemoteEvent (global world-position VFX). Created here so
	-- the service is self-contained: it works whether or not Main.server
	-- pre-created the remote. Lookup order matches where Main.server puts
	-- it (ReplicatedStorage.Remotes.<name>), with a root-level fallback.
	local nukeRemote: UnreliableRemoteEvent
	do
		local remoteName = getStringConfig("NUKE_REMOTE", "DonationEffect")
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		local existing: Instance? = nil
		if remotesFolder then
			existing = remotesFolder:FindFirstChild(remoteName)
		end
		if not existing then
			existing = ReplicatedStorage:FindFirstChild(remoteName)
		end
		if existing and existing:IsA("UnreliableRemoteEvent") then
			nukeRemote = existing
		else
			if existing then
				existing:Destroy()
			end
			nukeRemote = Instance.new("UnreliableRemoteEvent")
			nukeRemote.Name = remoteName
			-- Default to ReplicatedStorage.Remotes so the convention matches
			-- other remotes; create the folder if absent.
			local parent = remotesFolder
			if not parent then
				parent = Instance.new("Folder")
				parent.Name = "Remotes"
				parent.Parent = ReplicatedStorage
			end
			nukeRemote.Parent = parent
		end
	end

	local function isCashDonationSource(source: string): boolean
		return source == "cash" or source == "saweria" or source == "bagibagi"
	end

	-- Resolves which world-position nuke VFX (Nuke / Smite / BlackHole) to play
	-- for the given amount. Returns nil if no tier matches (sub-threshold).
	local function resolveNukeEffect(source: string, amount: number): string?
		if not isCashDonationSource(source) then
			return nil
		end
		return DonationEffectTierResolver.resolveWorldByIdr(amount)
	end

	-- Fires the world-position nuke VFX to all clients. Queued via enqueueNuke
	-- with DONATION_VFX_MAX_CONCURRENT budget (default 1).
	local function getWorldVfxRecipientLabel(): string
		if type(Config.Branding) == "table" and type(Config.Branding.GAME_NAME) == "string" and Config.Branding.GAME_NAME ~= "" then
			return Config.Branding.GAME_NAME
		end
		local clubKit = Config.ClubKit
		local branding = if type(clubKit) == "table" then clubKit.Branding else nil
		if type(branding) == "table" and type(branding.GameName) == "string" and branding.GameName ~= "" then
			return branding.GameName
		end
		return "Club"
	end

	local function broadcastNuke(creditedPlayer: Player, source: string, amount: number)
		if not nukeRemote then
			return
		end
		local effect = resolveNukeEffect(source, amount)
		if not effect then
			return
		end
		-- World VFX billboard: credited Roblox player donated to the game.
		local donatorName = creditedPlayer.Name
		local recipientName = getWorldVfxRecipientLabel()
		nukeRemote:FireAllClients(effect, donatorName, recipientName, amount, creditedPlayer.UserId)
		log:info("Nuke broadcast", {
			player = creditedPlayer.Name,
			donor = donatorName,
			recipient = recipientName,
			source = source,
			amount = amount,
			effect = effect,
			activeWorldVfx = activeWorldVfx,
		})
	end

	local drainNukeQueue: () -> ()

	drainNukeQueue = function()
		local maxConcurrent = getWorldVfxMaxConcurrent()
		if maxConcurrent <= 0 then
			table.clear(nukeQueue)
			return
		end
		while #nukeQueue > 0 and activeWorldVfx < maxConcurrent do
			local item = table.remove(nukeQueue, 1)
			if not item then
				break
			end
			local player = item.player
			local effect = resolveNukeEffect(item.source, item.amount)
			if not (player and player.Parent and effect) then
				continue
			end
			activeWorldVfx += 1
			task.spawn(function()
				broadcastNuke(player, item.source, item.amount)
				task.wait(getWorldEffectDuration(effect))
				activeWorldVfx = math.max(0, activeWorldVfx - 1)
				drainNukeQueue()
			end)
		end
	end

	local function enqueueNuke(player: Player, source: string, amount: number)
		local maxConcurrent = getWorldVfxMaxConcurrent()
		if maxConcurrent <= 0 then
			return
		end
		-- Skip kalau tidak ada effect untuk amount ini (resolveNukeEffect returns nil)
		local effect = resolveNukeEffect(source, amount)
		if not effect then
			return
		end
		table.insert(nukeQueue, { player = player, source = source, amount = amount })
		drainNukeQueue()
	end

	local service = {} :: DonationEffectService

	-- Internal: spawns the effect, plays the sound, and triggers the camera.
	-- Public methods handle queueing and cooldown before calling this.
	local function playTierEffect(
		player: Player,
		tier: DonationEffectTier,
		amount: number,
		source: string
	): Result<nil>
		-- Camera trigger is independent of the aura/sound effects: it should fire
		-- as long as the tier opts in, regardless of whether aura assets exist or
		-- the character is ready. Cinematic camera only needs the player.
		local camDuration = tier.cameraDuration or 0
		if camDuration > 0 and cameraTrigger then
			local okCam, errCam = pcall(cameraTrigger, player, camDuration)
			if not okCam then
				log:warn("Donation camera trigger failed", {
					player = player.Name,
					error = tostring(errCam),
				})
			end
		end

		local character, attachPart = getCharacterRoot(player)
		if not character or not attachPart then
			return Result.Err("character_not_ready")
		end

		local effectsFolderName = getStringConfig("ROBUX_EFFECTS_FOLDER", "DonationEffects")
		local soundsFolderName = getStringConfig("ROBUX_EFFECT_SOUNDS_FOLDER", "DonationSounds")
		-- Defensive fallback if tier.duration is missing from config.
		local duration = tier.duration or 12

		local effectsFolder = findAssetFolder(effectsFolderName)
		if not effectsFolder then
			return Result.Err("effects_folder_not_found")
		end

		-- Recursive lookup handles nested wrappers (Model > Folder > LevelN).
		local effectTemplate = effectsFolder:FindFirstChild(tier.effect, true)
		if not effectTemplate then
			return Result.Err("effect_not_found")
		end

		local effect = effectTemplate:Clone()
		SoundAssetSanitizer.removeBlockedSounds(effect)
		-- Clients scale/disable emitters locally via Settings (SettingsDonationVfxScale).
		effect.Name = "HazastudioDonationEffect_" .. tier.effect
		CollectionService:AddTag(effect, "DonationEffect")
		positionEffect(effect, character, attachPart)
		Debris:AddItem(effect, duration)

		local soundsFolder = findAssetFolder(soundsFolderName)
		if soundsFolder and tier.sound then
			local soundResult = playSound(soundsFolder, tier.sound, attachPart, duration)
			if not soundResult.ok then
				log:warn("Donation effect sound skipped", {
					player = player.Name,
					sound = tier.sound,
					error = soundResult.error,
				})
			end
		end

		log:info("Donation effect played", {
			player = player.Name,
			source = source,
			amount = amount,
			level = tier.level,
			effect = tier.effect,
			cameraDuration = camDuration,
		})

		return Result.Ok(nil)
	end

	-- Total cycle time so the next donation cannot overlap.
	-- Aura/notif share `tier.duration`; camera uses `tier.cameraDuration`.
	local function getCycleDuration(tier: DonationEffectTier): number
		local auraDuration = tier.duration or 12
		local camDuration = tier.cameraDuration or 0
		local maxCycle = math.max(auraDuration, camDuration)
		return maxCycle + QUEUE_BUFFER
	end

	local function processQueue(userId: number)
		while true do
			local queue = queueByUserId[userId]
			if not queue or #queue == 0 then
				break
			end

			local item = table.remove(queue, 1)
			if not item then
				break
			end

			-- Player may have left while queued; bail if so.
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				break
			end

			local effectResult = playTierEffect(player, item.tier, item.amount, item.source)
			if not effectResult.ok then
				log:warn("Queued donation effect failed", {
					player = player.Name,
					source = item.source,
					error = effectResult.error,
				})
			end

			-- Hold the full cycle before processing the next item.
			task.wait(getCycleDuration(item.tier))
		end

		workerThreadByUserId[userId] = nil
		queueByUserId[userId] = nil
	end

	local function enqueueDonation(
		player: Player,
		source: string,
		amount: number,
		tier: DonationEffectTier
	): Result<nil>
		local userId = player.UserId
		local queue = queueByUserId[userId]
		if not queue then
			queue = {}
			queueByUserId[userId] = queue
		end

		if #queue >= MAX_QUEUE_DEPTH then
			-- Priority drop: find and remove lowest-tier item to make room
			local lowestIdx = nil
			local lowestLevel = math.huge
			for i, item in ipairs(queue) do
				local itemLevel = item.tier and item.tier.level or 0
				if itemLevel < lowestLevel then
					lowestLevel = itemLevel
					lowestIdx = i
				end
			end
			local newLevel = tier.level or 0
			if lowestIdx and newLevel > lowestLevel then
				-- New donation is higher tier, drop the lowest
				table.remove(queue, lowestIdx)
				log:info("Donation queue full, dropped lower-tier effect", {
					player = player.Name,
					droppedLevel = lowestLevel,
					keptLevel = newLevel,
				})
			else
				log:warn("Donation queue full, dropping new", {
					player = player.Name,
					depth = #queue,
					newLevel = newLevel,
				})
				return Result.Err("queue_full")
			end
		end

		table.insert(queue, {
			source = source,
			amount = amount,
			tier = tier,
		})

		-- Spawn the worker on demand. FIFO order is preserved by table.insert.
		if not workerThreadByUserId[userId] then
			workerThreadByUserId[userId] = task.spawn(processQueue, userId)
		end

		return Result.Ok(nil)
	end

	function service:playRobuxDonation(player: Player, amount: number): Result<nil>
		if amount <= 0 then
			return Result.Err("invalid_amount")
		end

		-- Robux: per-player aura only (no world-position Rocket/Hammer/Blackhole).

		local tier = getTierByRobux(amount)
		if not tier then
			return Result.Err("tier_not_found")
		end

		return enqueueDonation(player, "robux", amount, tier)
	end

	function service:playCashDonation(player: Player, idrAmount: number): Result<nil>
		if idrAmount <= 0 then
			return Result.Err("invalid_amount")
		end

		enqueueNuke(player, "cash", idrAmount)

		local tier = getTierByIdr(idrAmount)
		if not tier then
			return Result.Err("tier_not_found")
		end

		return enqueueDonation(player, "cash", idrAmount, tier)
	end

	function service:playSaweriaDonation(player: Player, idrAmount: number): Result<nil>
		return self:playCashDonation(player, idrAmount)
	end

	function service:onPlayerRemoving(player: Player)
		-- Worker exits on its next iteration via the Players:GetPlayerByUserId guard.
		queueByUserId[player.UserId] = nil
		workerThreadByUserId[player.UserId] = nil
	end

	return service
end

return createDonationEffectService
