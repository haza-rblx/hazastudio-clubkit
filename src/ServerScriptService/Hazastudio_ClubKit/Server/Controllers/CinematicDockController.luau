--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local CinematicCameraModes = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CinematicCameraModes)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)

local function createCinematicDockController(deps: {
	remotes: Folder,
	notify: any,
	overheadService: any,
})
	local remotes = deps.remotes
	local notify = deps.notify
	local overheadService = deps.overheadService
	local log = Logger.new("CinematicDockController")
	local cfg = Config.CinematicDock

	-- Build movement lookup once. Map: value -> { value, label, targetType }
	local movementByValue: { [string]: any } = {}
	for _, option in ipairs(cfg.MOVEMENT_OPTIONS) do
		movementByValue[option.value] = option
	end

	local requestRemote = remotes:FindFirstChild(cfg.REMOTE_REQUEST)
	if not requestRemote or not requestRemote:IsA("RemoteEvent") then
		requestRemote = Instance.new("RemoteEvent")
		requestRemote.Name = cfg.REMOTE_REQUEST
		requestRemote.Parent = remotes
	end

	local broadcastRemote = remotes:FindFirstChild(cfg.REMOTE_BROADCAST)
	if not broadcastRemote or not broadcastRemote:IsA("RemoteEvent") then
		broadcastRemote = Instance.new("RemoteEvent")
		broadcastRemote.Name = cfg.REMOTE_BROADCAST
		broadcastRemote.Parent = remotes
	end

	local targetsRemote = remotes:FindFirstChild(cfg.REMOTE_TARGETS)
	if not targetsRemote or not targetsRemote:IsA("RemoteEvent") then
		targetsRemote = Instance.new("RemoteEvent")
		targetsRemote.Name = cfg.REMOTE_TARGETS
		targetsRemote.Parent = remotes
	end
	local requestRemoteEvent = requestRemote :: RemoteEvent
	local broadcastRemoteEvent = broadcastRemote :: RemoteEvent
	local targetsRemoteEvent = targetsRemote :: RemoteEvent

	-- NetworkManagers batch per-Heartbeat. Donation cinematics fire play +
	-- auto-stop in the same frame as overhead refreshes; batching coalesces
	-- those into one wire flush per recipient.
	local broadcastNetwork = NetworkManager.create({
		reliable = broadcastRemoteEvent,
		logger = log,
		isServer = true,
	})
	local targetsNetwork = NetworkManager.create({
		reliable = targetsRemoteEvent,
		logger = log,
		isServer = true,
	})

	local controller = {}

	-- Track the active target player. Auto-stops the cinematic when they leave.
	local activeTargetUserId: number? = nil
	-- Monotonic token used to invalidate stale auto-stop timers when a new
	-- donation arrives before the previous timer expires.
	local activeFocusToken: number = 0

	-- Server-side API: focuses the camera on a specific player. Called from
	-- DonationEffectService when a tier has `cameraDuration > 0`.
	function controller.focusOnPlayer(targetPlayer: Player, durationSeconds: number)
		if not targetPlayer or not targetPlayer.Parent then
			return
		end
		local duration = math.clamp(durationSeconds, cfg.MIN_DURATION, cfg.MAX_DURATION)
		activeTargetUserId = targetPlayer.UserId
		activeFocusToken += 1
		local token = activeFocusToken
		broadcastNetwork:fireAllClients({
			type = "play",
			target = {
				type = "player",
				userId = targetPlayer.UserId,
				name = targetPlayer.DisplayName .. " @" .. targetPlayer.Name,
			},
			movement = "DonationOrbit",
			speed = 1,
			duration = duration,
			startedAt = os.clock(),
			by = "[Donation]",
		})
		log:info("Donation cinematic broadcast", {
			target = targetPlayer.Name,
			duration = duration,
		})
		-- Auto-stop after duration. Token check prevents a stale timer from
		-- cancelling a camera that a newer donation has already taken over.
		task.delay(duration, function()
			if activeFocusToken ~= token then
				return
			end
			activeTargetUserId = nil
			broadcastNetwork:fireAllClients({
				type = "stop",
				by = "[Donation] Auto-restore",
			})
		end)
	end

	local function isAdmin(player: Player): boolean
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok and payloadResult.value then
				return PermissionDomain.canUseAdminPanel(payloadResult.value.role, player.UserId)
			end
		end
		return PermissionDomain.canUseAdminPanel(overheadService:getRawGroupRole(player), player.UserId)
	end

	local function resolvePath(path: any): Instance?
		if type(path) ~= "table" then
			return nil
		end

		local current: Instance = workspace
		for _, segment in ipairs(path) do
			if type(segment) ~= "string" or segment == "" then
				return nil
			end
			local nextChild = current:FindFirstChild(segment)
			if not nextChild then
				return nil
			end
			current = nextChild
		end
		return current
	end

	local cctvFolderNames: { [string]: boolean } = {}
	for _, folderName in ipairs(cfg.CCTV_FOLDER_NAMES or { "CCTV" }) do
		if type(folderName) == "string" and folderName ~= "" then
			cctvFolderNames[folderName] = true
		end
	end

	local function isUnderCCTVFolder(instance: Instance): boolean
		local parent = instance.Parent
		while parent and parent ~= workspace do
			if cctvFolderNames[parent.Name] then
				return true
			end
			parent = parent.Parent
		end
		return false
	end

	local function isCCTVPart(instance: Instance?): boolean
		if not instance or not instance:IsA("BasePart") then
			return false
		end
		if instance:GetAttribute(cfg.CCTV_ATTRIBUTE) == true or instance:GetAttribute("IsCCTV") == true then
			return true
		end
		return isUnderCCTVFolder(instance)
	end

	local function applyCCTVRuntimeVisual(instance: Instance)
		if not instance:IsA("BasePart") or not isCCTVPart(instance) then
			return
		end
		instance.Transparency = math.clamp(tonumber(cfg.CCTV_RUNTIME_TRANSPARENCY) or 1, 0, 1)
	end

	local function enforceCCTVRuntimeVisuals()
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("BasePart") and isCCTVPart(descendant) then
				applyCCTVRuntimeVisual(descendant)
			end
		end
	end

	local function buildCCTVTarget(instance: BasePart, path: { string }): { [string]: any }
		local displayName = instance:GetAttribute(cfg.CCTV_NAME_ATTRIBUTE)
		return {
			type = "cctv",
			id = tostring(instance:GetAttribute(cfg.CCTV_ID_ATTRIBUTE) or table.concat(path, "/")),
			name = if type(displayName) == "string" and displayName ~= "" then displayName else instance.Name,
			path = path,
		}
	end

	local function getCCTVTargets(): { any }
		local targets = {}
		local seenPaths: { [string]: boolean } = {}

		local function pathFromWorkspace(instance: Instance): { string }?
			local segments: { string } = {}
			local current: Instance? = instance
			while current and current ~= workspace do
				table.insert(segments, 1, current.Name)
				current = current.Parent
			end
			if #segments == 0 then
				return nil
			end
			return segments
		end

		local function addTarget(instance: BasePart, path: { string })
			local key = table.concat(path, "/")
			if seenPaths[key] then
				return
			end
			seenPaths[key] = true
			table.insert(targets, buildCCTVTarget(instance, path))
		end

		local function collectPartsUnderFolder(folder: Instance)
			for _, descendant in ipairs(folder:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local partPath = pathFromWorkspace(descendant)
					if partPath then
						addTarget(descendant, partPath)
					end
				end
			end
		end

		local function visit(instance: Instance, path: { string })
			if cctvFolderNames[instance.Name] then
				collectPartsUnderFolder(instance)
			end
			if isCCTVPart(instance) and instance:IsA("BasePart") then
				addTarget(instance, path)
			end
			for _, child in ipairs(instance:GetChildren()) do
				local childPath = table.clone(path)
				table.insert(childPath, child.Name)
				visit(child, childPath)
			end
		end

		for _, child in ipairs(workspace:GetChildren()) do
			visit(child, { child.Name })
		end

		table.sort(targets, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)
		return targets
	end

	local function normalizeSpeed(raw: any): number
		local value = tonumber(raw) or cfg.DEFAULT_SPEED
		local allowed = cfg.ALLOWED_SPEEDS
		if type(allowed) == "table" then
			local best = cfg.DEFAULT_SPEED
			local bestDistance = math.huge
			for _, candidate in ipairs(allowed) do
				local numeric = tonumber(candidate)
				if numeric then
					local distance = math.abs(numeric - value)
					if distance < bestDistance then
						bestDistance = distance
						best = numeric
					end
				end
			end
			return best
		end
		return math.clamp(value, 0.5, 2)
	end

	local function buildTargetsPayload(): { any }
		local targets = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(targets, {
				type = "player",
				id = tostring(player.UserId),
				userId = player.UserId,
				name = player.DisplayName .. " @" .. player.Name,
			})
		end
		for _, cctv in ipairs(getCCTVTargets()) do
			table.insert(targets, cctv)
		end
		return targets
	end

	targetsRemoteEvent.OnServerEvent:Connect(function(player: Player)
		if not isAdmin(player) then
			notify.player(player, cfg.MSG_NO_PERM, "WARNING")
			return
		end
		targetsNetwork:fireClient(player, {
			type = "targets",
			targets = buildTargetsPayload(),
		})
	end)

	-- Keep CCTV rigs hidden at runtime.
	enforceCCTVRuntimeVisuals()
	workspace.DescendantAdded:Connect(function(descendant)
		applyCCTVRuntimeVisual(descendant)
	end)

	requestRemoteEvent.OnServerEvent:Connect(function(player: Player, raw: any)
		if not isAdmin(player) then
			notify.player(player, cfg.MSG_NO_PERM, "WARNING")
			return
		end
		if type(raw) ~= "table" then
			return
		end
		-- Soft open-check from custom topbar: toast-only path for non-admins already
		-- handled above; admins get a no-op ACK so the dock can open client-side.
		if raw.action == "authorize" then
			return
		end
		if raw.action == "stop" then
			activeTargetUserId = nil
			broadcastNetwork:fireAllClients({
				type = "stop",
				by = player.Name,
			})
			return
		end

		local targetType = tostring(raw.targetType or raw.type or "")
		local targetPayload: { [string]: any }? = nil
		if targetType == "player" then
			local userId = tonumber(raw.userId)
			local targetPlayer = if userId then Players:GetPlayerByUserId(userId) else nil
			if not targetPlayer then
				notify.player(player, cfg.MSG_INVALID_TARGET, "ERROR")
				return
			end
			targetPayload = {
				type = "player",
				userId = targetPlayer.UserId,
				name = targetPlayer.DisplayName .. " @" .. targetPlayer.Name,
			}
		elseif targetType == "cctv" then
			local instance = resolvePath(raw.path)
			if not isCCTVPart(instance) then
				notify.player(player, cfg.MSG_INVALID_TARGET, "ERROR")
				return
			end
			targetPayload = buildCCTVTarget(instance :: BasePart, raw.path)
		else
			notify.player(player, cfg.MSG_INVALID_TARGET, "ERROR")
			return
		end

		local duration = math.clamp(tonumber(raw.duration) or cfg.DEFAULT_DURATION, cfg.MIN_DURATION, cfg.MAX_DURATION)
		local speed = normalizeSpeed(raw.speed)

		-- Movement validation
		local rawMovement = tostring(raw.movement or "")
		local movementOption = movementByValue[rawMovement]
		if not movementOption then
			notify.player(player, cfg.MSG_INVALID_MOVEMENT, "ERROR")
			return
		end
		local mappedTargetType = targetType
		if mappedTargetType == "player" then
			mappedTargetType = "character"
		elseif mappedTargetType == "cctv" then
			if CinematicCameraModes.is360CctvTarget(targetPayload) then
				mappedTargetType = "part360"
			else
				mappedTargetType = "part"
			end
		end
		if movementOption.targetType ~= "any" and movementOption.targetType ~= mappedTargetType then
			notify.player(player, cfg.MSG_INVALID_MOVEMENT, "ERROR")
			return
		end
		local movement = movementOption.value

		-- Update tracked target
		if targetType == "player" and targetPayload then
			activeTargetUserId = tonumber(targetPayload.userId)
		else
			activeTargetUserId = nil
		end

		broadcastNetwork:fireAllClients({
			type = "play",
			target = targetPayload,
			movement = movement,
			speed = speed,
			duration = duration,
			startedAt = os.clock(),
			by = player.Name,
		})

		notify.player(player, cfg.MSG_SENT, "SUCCESS")
		log:info("Cinematic broadcast", {
			player = player.Name,
			targetType = targetType,
			movement = movement,
			speed = speed,
			duration = duration,
		})
	end)

	Players.PlayerRemoving:Connect(function(leavingPlayer: Player)
		if activeTargetUserId and leavingPlayer.UserId == activeTargetUserId then
			activeTargetUserId = nil
			broadcastNetwork:fireAllClients({
				type = "stop",
				by = "[System] Target left",
			})
			log:info("Auto-stop: target player left", { userId = leavingPlayer.UserId, name = leavingPlayer.Name })
		end
	end)

	log:info("CinematicDockController initialized")
	return controller
end

return createCinematicDockController
