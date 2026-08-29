--!strict
-- Runtime integrity guards (ADR 0008 Layer 2 + 2c), server half.
--
-- Watches EFFECTS rather than code, so it does not care how a backdoor is obfuscated:
--   SoundGuard   — a Sound appearing at runtime whose SoundId was not in the place at boot
--   ScriptGuard  — a Script/LocalScript/ModuleScript created at runtime outside the kit
--   RemoteStorm  — one player firing RemoteEvents far faster than any UI can
--   AvatarGuard  — oversized / effect-spamming accessories (server-owned appearance → trim)
-- Everything beacons through LicenseService.reportTamper("runtime:<kind>") so evidence lands
-- in the same VPS table + Discord channel as ADR 0006. Speed bump + evidence, not a wall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AvatarPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AvatarPolicy)

local RuntimeGuard = {}

local KIT_ROOT_NAMES: { [string]: boolean } = {
	Hazastudio_ClubKit = true,
	Hazastudio_ClubKitConfig = true,
	Hazastudio_ClubKitSecrets = true,
	Icon = true,
}

local _started = false
local log = Logger.new("RuntimeGuard")

type Deps = {
	licenseService: any?,
	notify: any?,
}

local function isKitOwned(inst: Instance): boolean
	local cur: Instance? = inst
	while cur and cur ~= game do
		if KIT_ROOT_NAMES[cur.Name] then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function beacon(deps: Deps, kind: string, extra: { [string]: any }?)
	local ls = deps.licenseService
	if ls and type(ls.reportTamper) == "function" then
		pcall(function()
			ls.reportTamper("runtime:" .. kind, extra)
		end)
	end
end

local function notifyPlayer(deps: Deps, player: Player, message: string)
	if Config.RuntimeGuard.NOTIFY_PLAYER ~= true then
		return
	end
	local notify = deps.notify
	if notify and type(notify.player) == "function" then
		pcall(function()
			notify.player(player, message, "WARNING")
		end)
	end
end

-- Find the Player whose character (if any) contains the instance.
local function ownerOf(inst: Instance): Player?
	local cur: Instance? = inst
	while cur and cur ~= game do
		if cur:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(cur)
			if player then
				return player
			end
		end
		cur = cur.Parent
	end
	return nil
end

local function forEachServiceDescendant(fn: (Instance) -> ())
	for _, service in ipairs(game:GetChildren()) do
		local ok, descendants = pcall(function()
			return service:GetDescendants()
		end)
		if ok then
			for _, inst in ipairs(descendants) do
				fn(inst)
			end
		end
	end
end

-- ============================================================
-- SoundGuard
-- ============================================================
local function startSoundGuard(deps: Deps)
	local mode = Config.RuntimeGuard.SOUND_ENFORCE
	if mode ~= "log" and mode ~= "block" then
		return
	end
	local allowedIds: { [string]: boolean } = {}
	local snapshotCount = 0
	forEachServiceDescendant(function(inst)
		if inst:IsA("Sound") and inst.SoundId ~= "" then
			allowedIds[inst.SoundId] = true
			snapshotCount += 1
		end
	end)
	local seen: { [string]: boolean } = {}
	local rogueCount = 0

	local function judge(sound: Sound)
		if not sound.Parent or isKitOwned(sound) then
			return
		end
		local id = sound.SoundId
		if id == "" or allowedIds[id] then
			return
		end
		rogueCount += 1
		local actor = ownerOf(sound)
		local path = sound:GetFullName()
		log:warn("Rogue sound", { soundId = id, path = path, actor = actor and actor.Name, mode = mode })
		if not seen[id] then
			seen[id] = true
			beacon(deps, "rogue_sound", { sound_id = id, path = string.sub(path, 1, 200), actor_id = actor and actor.UserId })
		end
		if mode == "block" then
			pcall(function()
				sound:Stop()
				sound:Destroy()
			end)
		end
	end

	game.DescendantAdded:Connect(function(inst)
		if inst:IsA("Sound") then
			-- SoundId is often set right after Instance.new; judge on the next step.
			task.defer(judge, inst)
			inst:GetPropertyChangedSignal("SoundId"):Connect(function()
				judge(inst)
			end)
		end
	end)
	log:info("SoundGuard armed", { mode = mode, allowlisted = snapshotCount })
	return function()
		return rogueCount
	end
end

-- ============================================================
-- ScriptGuard
-- ============================================================
local function startScriptGuard(deps: Deps)
	local mode = Config.RuntimeGuard.SCRIPT_GUARD
	if mode ~= "beacon" and mode ~= "destroy" then
		return
	end
	local allowNames: { [string]: boolean } = {}
	for _, name in ipairs(Config.RuntimeGuard.SCRIPT_ALLOW_PARENT_NAMES or {}) do
		allowNames[name] = true
	end
	local bootDone = false
	task.delay(5, function()
		bootDone = true
	end)
	local reported = 0

	-- Tools carry their own scripts and are cloned into Backpack / StarterGear / the
	-- character on every equip (kit RoleToolService does exactly this) — never a dropper.
	local function hasAllowedAncestor(inst: Instance): boolean
		local cur: Instance? = inst.Parent
		while cur and cur ~= game do
			if allowNames[cur.Name] or cur:IsA("Tool") or cur:IsA("Backpack") or cur:IsA("StarterGear") then
				return true
			end
			cur = cur.Parent
		end
		return false
	end

	local seenPaths: { [string]: boolean } = {}
	game.DescendantAdded:Connect(function(inst)
		if not bootDone or not inst:IsA("LuaSourceContainer") then
			return
		end
		-- Judge on the next step: droppers parent first and name/move later.
		task.defer(function()
			if not inst.Parent or isKitOwned(inst) or hasAllowedAncestor(inst) then
				return
			end
			if string.sub(inst.Name, 1, 6) == "__MCP_" then
				return -- Studio MCP bridges (dev only)
			end
			-- Characters get Animate/Health scripts on spawn; those are Roblox's.
			local owner = ownerOf(inst)
			if owner and (inst.Name == "Animate" or inst.Name == "Health") then
				return
			end
			local path = inst:GetFullName()
			if seenPaths[path] then
				return
			end
			seenPaths[path] = true
			reported += 1
			local head = ""
			pcall(function()
				head = string.sub((inst :: any).Source or "", 1, 200)
			end)
			log:warn("Runtime script created outside kit", { path = path, class = inst.ClassName, head = head })
			if reported <= 5 then
				beacon(deps, "script_injected", { path = string.sub(path, 1, 200), class = inst.ClassName, head = head })
			end
			if mode == "destroy" then
				pcall(function()
					inst:Destroy()
				end)
			end
		end)
	end)
	log:info("ScriptGuard armed", { mode = mode })
end

-- ============================================================
-- RemoteStorm
-- ============================================================
local function startRemoteStorm(deps: Deps)
	local perSec = tonumber(Config.RuntimeGuard.REMOTE_STORM_PER_SEC) or 0
	if perSec <= 0 then
		return
	end
	local window = tonumber(Config.RuntimeGuard.REMOTE_STORM_WINDOW) or 3
	local action = Config.RuntimeGuard.REMOTE_STORM_ACTION
	local counts: { [number]: number } = {}
	local hotSeconds: { [number]: number } = {}
	local hooked: { [Instance]: boolean } = {}

	local function hook(remote: Instance)
		if hooked[remote] or not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
			return
		end
		hooked[remote] = true
		;(remote :: any).OnServerEvent:Connect(function(player: Player)
			counts[player.UserId] = (counts[player.UserId] or 0) + 1
		end)
	end
	for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
		hook(inst)
	end
	ReplicatedStorage.DescendantAdded:Connect(hook)

	task.spawn(function()
		while true do
			task.wait(1)
			for userId, n in pairs(counts) do
				if n > perSec then
					hotSeconds[userId] = (hotSeconds[userId] or 0) + 1
					if hotSeconds[userId] >= window then
						hotSeconds[userId] = 0
						local player = Players:GetPlayerByUserId(userId)
						log:warn("Remote storm", { userId = userId, perSec = n, action = action })
						beacon(deps, "remote_storm", { actor_id = userId, per_sec = n })
						if player and action == "kick" then
							pcall(function()
								player:Kick("Removed: too many requests per second.")
							end)
						end
					end
				else
					hotSeconds[userId] = 0
				end
			end
			table.clear(counts)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		counts[player.UserId] = nil
		hotSeconds[player.UserId] = nil
	end)
	log:info("RemoteStorm armed", { perSec = perSec, window = window, action = action })
end

-- ============================================================
-- AvatarGuard
-- ============================================================
local function describeAccessory(accessory: Accessory): AvatarPolicy.AccessoryDesc?
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end
	local size = handle.Size
	local mesh = handle:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		size = Vector3.new(size.X * mesh.Scale.X, size.Y * mesh.Scale.Y, size.Z * mesh.Scale.Z)
	end
	local effects: { AvatarPolicy.EffectDesc } = {}
	local particles: { AvatarPolicy.ParticleDesc } = {}
	for _, d in ipairs(accessory:GetDescendants()) do
		if d:IsA("Beam") then
			table.insert(effects, { class = "Beam", width = math.max(d.Width0, d.Width1) })
		elseif d:IsA("Trail") then
			table.insert(effects, { class = "Trail", width = d.Lifetime })
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			table.insert(effects, { class = d.ClassName, range = (d :: any).Range, brightness = (d :: any).Brightness })
		elseif d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			table.insert(effects, { class = d.ClassName })
		elseif d:IsA("ParticleEmitter") then
			local maxSize = 0
			for _, kp in ipairs(d.Size.Keypoints) do
				maxSize = math.max(maxSize, kp.Value)
			end
			table.insert(particles, { rate = d.Rate, size = maxSize, lifetime = d.Lifetime.Max })
		end
	end
	return { size = { size.X, size.Y, size.Z }, effects = effects, particles = particles }
end

local function collectEffectInstances(accessory: Accessory): ({ Instance }, { ParticleEmitter })
	local effects, particles = {}, {}
	for _, d in ipairs(accessory:GetDescendants()) do
		if d:IsA("Beam") or d:IsA("Trail") or d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			table.insert(effects, d)
		elseif d:IsA("ParticleEmitter") then
			table.insert(particles, d)
		end
	end
	return effects, particles
end

local function startAvatarGuard(deps: Deps)
	local cfg = Config.AvatarGuard
	if cfg.ENABLED ~= true then
		return
	end
	local trims: { [number]: number } = {}
	local notified: { [number]: boolean } = {}

	local function recordTrim(player: Player?, reason: string, detail: { [string]: any })
		if not player then
			return
		end
		local userId = player.UserId
		trims[userId] = (trims[userId] or 0) + 1
		local fields: { [string]: any } = { player = player.Name, reason = reason }
		for k, v in pairs(detail) do
			fields[k] = if type(v) == "table" then table.concat(v :: any, "x") else v
		end
		log:warn("Avatar trimmed", fields)
		if not notified[userId] then
			notified[userId] = true
			notifyPlayer(deps, player, cfg.MSG_TRIMMED)
			beacon(deps, "avatar_trimmed", { actor_id = userId, reason = reason })
		end
		local kickAfter = tonumber(cfg.KICK_AFTER_TRIMS) or 0
		if kickAfter > 0 and trims[userId] >= kickAfter then
			pcall(function()
				player:Kick("Removed: repeatedly equipping accessories that are not allowed in this venue.")
			end)
		end
	end

	local function judgeAccessory(accessory: Accessory, player: Player?)
		if not accessory.Parent then
			return
		end
		local desc = describeAccessory(accessory)
		if not desc then
			return
		end
		local verdict = AvatarPolicy.judgeAccessory(desc, cfg)
		if verdict.remove then
			recordTrim(player, verdict.reason or "oversized", { accessory = accessory.Name, size = desc.size })
			accessory:Destroy()
			return
		end
		local effects, particles = collectEffectInstances(accessory)
		for _, strip in ipairs(verdict.stripEffects) do
			local target = if strip.kind == "particle" then particles[strip.index] else effects[strip.index]
			if target then
				recordTrim(player, "effect_" .. strip.kind, { accessory = accessory.Name, class = target.ClassName })
				target:Destroy()
			end
		end
		for _, capItem in ipairs(verdict.effectCaps) do
			local target = effects[capItem.index]
			if target then
				if target:IsA("Beam") and capItem.width then
					target.Width0 = math.min(target.Width0, capItem.width)
					target.Width1 = math.min(target.Width1, capItem.width)
				elseif target:IsA("Trail") and capItem.width then
					target.Lifetime = math.min(target.Lifetime, capItem.width)
				elseif capItem.range then
					(target :: any).Range = capItem.range
					if capItem.brightness then
						(target :: any).Brightness = capItem.brightness
					end
				end
				recordTrim(player, "effect_capped", { accessory = accessory.Name, class = target.ClassName })
			end
		end
		for _, capItem in ipairs(verdict.particleCaps) do
			local target = particles[capItem.index]
			if target then
				target.Rate = capItem.rate
				target.Size = NumberSequence.new(math.min(capItem.size, 1), capItem.size)
				target.Lifetime = NumberRange.new(math.min(target.Lifetime.Min, capItem.lifetime), capItem.lifetime)
				recordTrim(player, "particle_capped", { accessory = accessory.Name })
			end
		end
	end

	local function judgeCharacter(player: Player, character: Model)
		local accessories: { Accessory } = {}
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Accessory") then
				table.insert(accessories, child)
			end
		end
		for _, accessory in ipairs(accessories) do
			judgeAccessory(accessory, player)
		end
		-- Whole-character bounds: drop the largest remaining accessory until under the cap.
		for _ = 1, 6 do
			local ok, extents = pcall(function()
				return character:GetExtentsSize()
			end)
			if not ok or not AvatarPolicy.characterTooBig({ extents.X, extents.Y, extents.Z }, cfg) then
				break
			end
			local candidates = {}
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Accessory") then
					local d = describeAccessory(child)
					if d then
						table.insert(candidates, { inst = child, size = d.size })
					end
				end
			end
			local largest = AvatarPolicy.pickLargest(candidates)
			if not largest then
				break
			end
			recordTrim(player, "character_too_big", { accessory = (largest :: any).inst.Name, extents = { extents.X, extents.Y, extents.Z } })
			;(largest :: any).inst:Destroy()
		end
		-- Count cap: newest beyond the limit.
		local maxCount = tonumber(cfg.MAX_ACCESSORIES) or 0
		if maxCount > 0 then
			local remaining = {}
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Accessory") then
					table.insert(remaining, child)
				end
			end
			for i = #remaining, maxCount + 1, -1 do
				recordTrim(player, "too_many_accessories", { accessory = remaining[i].Name, count = #remaining })
				remaining[i]:Destroy()
			end
		end
	end

	local function bindCharacter(player: Player, character: Model)
		task.defer(judgeCharacter, player, character)
		character.DescendantAdded:Connect(function(inst)
			if inst:IsA("Accessory") then
				task.defer(function()
					judgeAccessory(inst, player)
					judgeCharacter(player, character)
				end)
			end
		end)
	end

	local function bindPlayer(player: Player)
		player.CharacterAppearanceLoaded:Connect(function(character)
			bindCharacter(player, character)
		end)
		if player.Character then
			bindCharacter(player, player.Character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		trims[player.UserId] = nil
		notified[player.UserId] = nil
	end)
	log:info("AvatarGuard armed", { effects = cfg.EFFECTS, maxStuds = cfg.MAX_ACCESSORY_STUDS })
end

function RuntimeGuard.start(deps: Deps)
	if _started then
		return
	end
	_started = true
	if Config.RuntimeGuard.ENABLED ~= true then
		return
	end
	startSoundGuard(deps)
	startScriptGuard(deps)
	startRemoteStorm(deps)
	startAvatarGuard(deps)
end

return RuntimeGuard
