--!strict

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local Result = require(game:GetService("ReplicatedStorage").Hazastudio_ClubKit.Shared.Utils.Result)
local Types = require(game:GetService("ReplicatedStorage").Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>
type CarryRequest = Types.CarryRequest

export type CarryService = {
	requestCarry: (self: CarryService, carrier: Player, target: Player, style: string) -> Result<nil>,
	acceptCarry: (self: CarryService, targetPlayer: Player) -> Result<nil>,
	rejectCarry: (self: CarryService, targetPlayer: Player) -> Result<nil>,
	endCarry: (self: CarryService, player: Player) -> Result<nil>,
	getPendingRequest: (self: CarryService, userId: number) -> CarryRequest?,
	getPartnerId: (self: CarryService, userId: number) -> number?,
	onPlayerAdded: (self: CarryService, player: Player) -> (),
	onPlayerRemoving: (self: CarryService, player: Player) -> (),
}

type HumanoidSnapshot = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	platformStand: boolean,
}

type PartSnapshot = {
	canCollide: boolean,
	massless: boolean,
	collisionGroup: string,
}

type CarryAnimationEntry = {
	track: AnimationTrack,
	animation: Animation,
}

type CarryCalibration = {
	style: string,
	offset: { number },
	rotation: { number },
	inverse: boolean,
}

local function create(deps: {
	config: any,
	domain: any,
	logger: any,
}): CarryService
	local config = deps.config
	local carryConfig = config.Carry
	local domain = deps.domain
	local logger = deps.logger

	local pendingRequests: { [number]: CarryRequest } = {}
	local activeCarries: { [number]: number } = {}
	local savedHumanoidStates: { [number]: HumanoidSnapshot } = {}
	local savedPartStates: { [number]: { [BasePart]: PartSnapshot } } = {}
	local activeTracks: { [number]: { CarryAnimationEntry } } = {}
	local activeCalibrations: { [number]: CarryCalibration } = {}
	local carriedNetworkOwnerParts: { [number]: BasePart } = {}
	local characterConnections: { [number]: RBXScriptConnection } = {}
	local characterPartConnections: { [number]: RBXScriptConnection } = {}
	local self = {} :: any
	local PLAYER_COLLISION_GROUP = "PlayerCharacter"
	local CARRY_COLLISION_GROUP = "CarryNoPlayerCollision"

	local function ensureCollisionGroup(name: string): ()
		local ok = pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
		if not ok then
			return
		end
	end

	local function configureCollisionGroups(): ()
		ensureCollisionGroup(PLAYER_COLLISION_GROUP)
		ensureCollisionGroup(CARRY_COLLISION_GROUP)

		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(CARRY_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(CARRY_COLLISION_GROUP, CARRY_COLLISION_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(CARRY_COLLISION_GROUP, "Default", true)
			PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, "Default", true)
			-- Players pass through each other (no character-vs-character collision).
			PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
		end)
	end

	configureCollisionGroups()

	local function saveHumanoidState(userId: number, humanoid: Humanoid): ()
		if savedHumanoidStates[userId] ~= nil then
			return
		end
		savedHumanoidStates[userId] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			autoRotate = humanoid.AutoRotate,
			platformStand = humanoid.PlatformStand,
		}
	end

	local function restoreHumanoidState(userId: number, humanoid: Humanoid): ()
		local state = savedHumanoidStates[userId]
		if state == nil then
			return
		end
		humanoid.WalkSpeed = state.walkSpeed
		humanoid.JumpPower = state.jumpPower
		humanoid.JumpHeight = state.jumpHeight
		humanoid.AutoRotate = state.autoRotate
		humanoid.PlatformStand = state.platformStand
		savedHumanoidStates[userId] = nil
	end

	local function savePartStates(userId: number, character: Model): ()
		if savedPartStates[userId] ~= nil then
			return
		end

		local snapshots: { [BasePart]: PartSnapshot } = {}
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				snapshots[descendant] = {
					canCollide = descendant.CanCollide,
					massless = descendant.Massless,
					collisionGroup = descendant.CollisionGroup,
				}
			end
		end
		savedPartStates[userId] = snapshots
	end

	local function applyCarryCollisionGroup(character: Model): ()
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = CARRY_COLLISION_GROUP
			end
		end
	end

	local function applyCarriedPartState(character: Model): ()
		-- Full Massless (including HRP) + no world collision so the weld does not
		-- drag the carrier assembly. Carried stays visually stuck via Weld + PlatformStand.
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = CARRY_COLLISION_GROUP
				descendant.Massless = true
				descendant.CanCollide = false
			end
		end
	end

	local function zeroCharacterVelocity(character: Model): ()
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end

	local function snapCarriedToWeld(carrierPart: BasePart, carriedPart: BasePart): ()
		local weld = carriedPart:FindFirstChild(carryConfig.WELD_NAME)
		if weld and weld:IsA("Weld") then
			carriedPart.CFrame = carrierPart.CFrame * weld.C0
		end
	end

	local function restorePartStates(userId: number): ()
		local snapshots = savedPartStates[userId]
		if snapshots == nil then
			return
		end

		for part, snapshot in pairs(snapshots) do
			if part.Parent ~= nil then
				part.CanCollide = snapshot.canCollide
				part.Massless = snapshot.massless
				part.CollisionGroup = snapshot.collisionGroup
			end
		end
		savedPartStates[userId] = nil
	end

	local function applyPlayerCollisionGroup(character: Model): ()
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = PLAYER_COLLISION_GROUP
			end
		end
	end

	local function disconnectCharacterPartWatcher(userId: number): ()
		if characterPartConnections[userId] ~= nil then
			characterPartConnections[userId]:Disconnect()
			characterPartConnections[userId] = nil
		end
	end

	local function watchCharacterParts(player: Player, character: Model): ()
		disconnectCharacterPartWatcher(player.UserId)
		applyPlayerCollisionGroup(character)
		characterPartConnections[player.UserId] = character.DescendantAdded:Connect(function(descendant)
			if not descendant:IsA("BasePart") then
				return
			end
			if activeCarries[player.UserId] ~= nil then
				descendant.CollisionGroup = CARRY_COLLISION_GROUP
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				-- Carried = PlatformStand; keep late-added parts massless + non-colliding.
				if humanoid and humanoid.PlatformStand then
					descendant.Massless = true
					descendant.CanCollide = false
				end
			else
				descendant.CollisionGroup = PLAYER_COLLISION_GROUP
			end
		end)
	end

	local function getOrCreateAnimator(humanoid: Humanoid): Animator
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator ~= nil then
			return animator
		end

		local created = Instance.new("Animator")
		created.Parent = humanoid
		return created
	end

	local function getHumanoid(player: Player): Humanoid?
		local character = player.Character
		if character == nil then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid")
	end

	local function getRoot(player: Player): BasePart?
		local character = player.Character
		if character == nil then
			return nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
		return nil
	end

	local function findWeldOnPart(part: BasePart): Weld?
		local weld = part:FindFirstChild(carryConfig.WELD_NAME)
		if weld ~= nil and weld:IsA("Weld") then
			return weld
		end
		return nil
	end

	local function removeWeld(character: Model): ()
		for _, partName in ipairs({ "HumanoidRootPart", "UpperTorso", "Torso" }) do
			local part = character:FindFirstChild(partName)
			if part ~= nil and part:IsA("BasePart") then
				local weld = findWeldOnPart(part)
				if weld ~= nil then
					weld:Destroy()
				end
			end
		end
	end

	local function clearCarriedNetworkOwner(carriedUserId: number): ()
		local part = carriedNetworkOwnerParts[carriedUserId]
		carriedNetworkOwnerParts[carriedUserId] = nil
		if part == nil or part.Parent == nil then
			return
		end
		local carried = Players:GetPlayerByUserId(carriedUserId)
		pcall(function()
			if carried ~= nil then
				part:SetNetworkOwner(carried)
			else
				part:SetNetworkOwner(nil)
			end
		end)
	end

	local function stopCarryTracks(userId: number): ()
		local tracks = activeTracks[userId]
		if tracks == nil then
			return
		end
		for _, entry in ipairs(tracks) do
			local ok, err = pcall(function()
				entry.track:Stop(config.Sync.FADE_OUT)
				entry.track:Destroy()
				entry.animation:Destroy()
			end)
			if not ok then
				logger:warn("Failed to stop carry track", {
					userId = userId,
					error = tostring(err),
				})
			end
		end
		activeTracks[userId] = nil
	end

	local function playCarryAnimation(player: Player, style: string, role: "carrier" | "carried"): ()
		local character = player.Character
		local humanoid = getHumanoid(player)
		if character == nil or humanoid == nil then
			return
		end
		local animator = getOrCreateAnimator(humanoid)

		local rigType = if humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15"
		local animId = domain.getAnimationId(style, role, rigType)
		if animId <= 0 then
			logger:warn("Carry animation missing (check Config.Carry.STYLES animations)", {
				player = player.Name,
				style = style,
				role = role,
				rigType = rigType,
			})
			return
		end

		local animation = Instance.new("Animation")
		animation.Name = "Carry_" .. style .. "_" .. role
		animation.AnimationId = "rbxassetid://" .. tostring(animId)
		animation.Parent = character
		local ok, trackOrErr = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not trackOrErr then
			animation:Destroy()
			logger:warn("Failed to load carry animation", {
				player = player.Name,
				style = style,
				role = role,
				error = tostring(trackOrErr),
			})
			return
		end

		local track = trackOrErr :: AnimationTrack
		-- Carrier: keep priority below Sync dance (Action4) so carrier can dance freely.
		-- Carried: Action4 so the limp/stick pose stays glued while welded.
		-- Hard-stop any existing Action4 tracks first — otherwise a looping dance at the
		-- same priority blends with the carry pose for ~fade window ("broken arms").
		if role == "carried" then
			local playing
			local listOk = pcall(function()
				playing = animator:GetPlayingAnimationTracks()
			end)
			if listOk and type(playing) == "table" then
				for _, existing in ipairs(playing) do
					if existing.Priority == Enum.AnimationPriority.Action4 then
						pcall(function()
							existing:Stop(0)
						end)
					end
				end
			end
		end
		if role == "carrier" then
			track.Priority = Enum.AnimationPriority.Action
		else
			track.Priority = config.Sync.ANIM_PRIORITY
		end
		track.Looped = true
		track:Play(0)
		logger:info("Carry animation started", {
			player = player.Name,
			style = style,
			role = role,
			rigType = rigType,
			animId = animId,
		})
		activeTracks[player.UserId] = activeTracks[player.UserId] or {}
		table.insert(activeTracks[player.UserId], {
			track = track,
			animation = animation,
		})
	end

	local function createCarryWeld(carrier: Player, carried: Player, style: string): boolean
		local carrierCharacter = carrier.Character
		local carriedCharacter = carried.Character
		if carrierCharacter == nil or carriedCharacter == nil then
			return false
		end

		local attachPartName = domain.getAttachPartName()
		local carrierPart = domain.findCharacterAttachPart(carrierCharacter, attachPartName)
		local carriedPart = domain.findCharacterAttachPart(carriedCharacter, attachPartName)
		if carrierPart == nil or carriedPart == nil then
			return false
		end

		removeWeld(carriedCharacter)
		removeWeld(carrierCharacter)

		local offset, rotation, inverse = domain.getCarryOffsetParts(style)
		local calibration: CarryCalibration = {
			style = style,
			offset = offset,
			rotation = rotation,
			inverse = inverse,
		}

		local weld = Instance.new("Weld")
		weld.Name = carryConfig.WELD_NAME
		weld.Part0 = carrierPart
		weld.Part1 = carriedPart
		weld.C0 = domain.getCarryWeldC0(style, calibration.offset, calibration.rotation, calibration.inverse)
		weld.C1 = CFrame.new()
		weld.Parent = carriedPart

		if domain.shouldSetNetworkOwner() then
			clearCarriedNetworkOwner(carried.UserId)
			local ok = pcall(function()
				carriedPart:SetNetworkOwner(carrier)
			end)
			if ok then
				carriedNetworkOwnerParts[carried.UserId] = carriedPart
			else
				logger:warn("Carry SetNetworkOwner failed", {
					carrier = carrier.Name,
					carried = carried.Name,
					style = style,
				})
			end
		end

		activeCalibrations[carrier.UserId] = calibration
		activeCalibrations[carried.UserId] = calibration
		return true
	end

	local function getActiveWeld(player: Player): Weld?
		local partnerId = activeCarries[player.UserId]
		if partnerId == nil then
			return nil
		end

		local partner = Players:GetPlayerByUserId(partnerId)
		local candidates = { player, partner }
		for _, participant in ipairs(candidates) do
			if participant == nil or participant.Character == nil then
				continue
			end
			for _, partName in ipairs({ "UpperTorso", "HumanoidRootPart", "Torso" }) do
				local part = participant.Character:FindFirstChild(partName)
				if part ~= nil and part:IsA("BasePart") then
					local weld = findWeldOnPart(part)
					if weld ~= nil then
						return weld
					end
				end
			end
		end
		return nil
	end

	local function getActiveCalibration(player: Player): CarryCalibration?
		return activeCalibrations[player.UserId]
	end

	local function applyCalibration(player: Player): CarryCalibration?
		local calibration = getActiveCalibration(player)
		local weld = getActiveWeld(player)
		if calibration == nil or weld == nil then
			return nil
		end

		local offsetCFrame = domain.getCarryWeldC0(
			calibration.style,
			calibration.offset,
			calibration.rotation,
			calibration.inverse
		)
		weld.C0 = offsetCFrame
		return calibration
	end

	function self:requestCarry(carrier: Player, target: Player, style: string): Result<nil>
		if carrier == target then
			return Result.Err("self_target")
		end
		if not domain.isValidStyle(style) then
			return Result.Err("invalid_style")
		end
		if activeCarries[carrier.UserId] ~= nil or activeCarries[target.UserId] ~= nil then
			return Result.Err("already_carrying")
		end

		local carrierRoot = getRoot(carrier)
		local targetRoot = getRoot(target)
		if carrierRoot == nil or targetRoot == nil then
			return Result.Err("character_not_ready")
		end
		if not domain.isInRange(carrierRoot.Position, targetRoot.Position, carryConfig.MAX_DISTANCE) then
			return Result.Err("target_too_far")
		end

		pendingRequests[target.UserId] = {
			carrierId = carrier.UserId,
			targetId = target.UserId,
			style = style :: any,
			sentAt = os.clock(),
		}
		task.delay(carryConfig.REQUEST_TIMEOUT, function()
			local request = pendingRequests[target.UserId]
			if request ~= nil and request.carrierId == carrier.UserId then
				pendingRequests[target.UserId] = nil
			end
		end)
		return Result.Ok(nil)
	end

	function self:acceptCarry(targetPlayer: Player): Result<nil>
		local request = pendingRequests[targetPlayer.UserId]
		if request == nil then
			return Result.Err("no_pending_request")
		end
		if os.clock() - request.sentAt > carryConfig.REQUEST_TIMEOUT then
			pendingRequests[targetPlayer.UserId] = nil
			return Result.Err("request_expired")
		end

		local carrier = Players:GetPlayerByUserId(request.carrierId)
		if carrier == nil then
			pendingRequests[targetPlayer.UserId] = nil
			return Result.Err("carrier_left")
		end
		if activeCarries[carrier.UserId] ~= nil or activeCarries[targetPlayer.UserId] ~= nil then
			pendingRequests[targetPlayer.UserId] = nil
			return Result.Err("already_carrying")
		end

		local carrierHumanoid = getHumanoid(carrier)
		local targetHumanoid = getHumanoid(targetPlayer)
		local carrierCharacter = carrier.Character
		local targetCharacter = targetPlayer.Character
		if carrierHumanoid == nil or targetHumanoid == nil or carrierCharacter == nil or targetCharacter == nil then
			pendingRequests[targetPlayer.UserId] = nil
			return Result.Err("character_not_ready")
		end

		saveHumanoidState(carrier.UserId, carrierHumanoid)
		saveHumanoidState(targetPlayer.UserId, targetHumanoid)
		savePartStates(carrier.UserId, carrierCharacter)
		savePartStates(targetPlayer.UserId, targetCharacter)

		-- Carrier keeps normal WalkSpeed / JumpPower / JumpHeight so jump + dance feel free.
		carrierHumanoid.AutoRotate = true
		targetHumanoid.WalkSpeed = 0
		targetHumanoid.JumpPower = 0
		targetHumanoid.JumpHeight = 0
		targetHumanoid.AutoRotate = false
		applyCarryCollisionGroup(carrierCharacter)
		applyCarryCollisionGroup(targetCharacter)
		zeroCharacterVelocity(targetCharacter)

		if not createCarryWeld(carrier, targetPlayer, request.style) then
			pendingRequests[targetPlayer.UserId] = nil
			restoreHumanoidState(carrier.UserId, carrierHumanoid)
			restoreHumanoidState(targetPlayer.UserId, targetHumanoid)
			restorePartStates(carrier.UserId)
			restorePartStates(targetPlayer.UserId)
			applyPlayerCollisionGroup(carrierCharacter)
			applyPlayerCollisionGroup(targetCharacter)
			return Result.Err("weld_failed")
		end

		local carrierPart = domain.findCharacterAttachPart(carrierCharacter, domain.getAttachPartName())
		local carriedPart = domain.findCharacterAttachPart(targetCharacter, domain.getAttachPartName())
		if carrierPart and carriedPart then
			snapCarriedToWeld(carrierPart, carriedPart)
		end

		targetHumanoid.PlatformStand = true
		applyCarriedPartState(targetCharacter)

		playCarryAnimation(carrier, request.style, "carrier")
		playCarryAnimation(targetPlayer, request.style, "carried")
		activeCarries[carrier.UserId] = targetPlayer.UserId
		activeCarries[targetPlayer.UserId] = carrier.UserId
		pendingRequests[targetPlayer.UserId] = nil
		return Result.Ok(nil)
	end

	function self:rejectCarry(targetPlayer: Player): Result<nil>
		if pendingRequests[targetPlayer.UserId] == nil then
			return Result.Err("no_pending_request")
		end
		pendingRequests[targetPlayer.UserId] = nil
		return Result.Ok(nil)
	end

	function self:endCarry(player: Player): Result<nil>
		local partnerId = activeCarries[player.UserId]
		if partnerId == nil then
			return Result.Err("not_carrying")
		end

		local partner = Players:GetPlayerByUserId(partnerId)
		clearCarriedNetworkOwner(player.UserId)
		clearCarriedNetworkOwner(partnerId)
		for _, participant in ipairs({ player, partner }) do
			if participant == nil then
				continue
			end
			local character = participant.Character
			local humanoid = getHumanoid(participant)
			stopCarryTracks(participant.UserId)
			if character ~= nil then
				removeWeld(character)
			end
			restorePartStates(participant.UserId)
			if character ~= nil then
				applyPlayerCollisionGroup(character)
			end
			if humanoid ~= nil then
				restoreHumanoidState(participant.UserId, humanoid)
				humanoid.PlatformStand = false
			end
			activeCarries[participant.UserId] = nil
			activeCalibrations[participant.UserId] = nil
		end

		activeCarries[player.UserId] = nil
		activeCarries[partnerId] = nil
		return Result.Ok(nil)
	end

	function self:getPendingRequest(userId: number): CarryRequest?
		return pendingRequests[userId]
	end

	function self:getPartnerId(userId: number): number?
		return activeCarries[userId]
	end

	function self:getCalibration(player: Player): CarryCalibration?
		return getActiveCalibration(player)
	end

	function self:adjustCalibration(player: Player, axis: string, amount: number): CarryCalibration?
		local calibration = getActiveCalibration(player)
		if calibration == nil then
			return nil
		end

		local target = if string.sub(axis, 1, 1) == "r" then calibration.rotation else calibration.offset
		local indexByAxis = {
			x = 1,
			y = 2,
			z = 3,
			rx = 1,
			ry = 2,
			rz = 3,
		}
		local index = indexByAxis[axis]
		if index == nil then
			return calibration
		end

		target[index] = target[index] + amount
		return applyCalibration(player)
	end

	function self:toggleCalibrationInverse(player: Player): CarryCalibration?
		local calibration = getActiveCalibration(player)
		if calibration == nil then
			return nil
		end
		calibration.inverse = not calibration.inverse
		return applyCalibration(player)
	end

	function self:printCalibration(player: Player): CarryCalibration?
		local calibration = getActiveCalibration(player)
		if calibration == nil then
			return nil
		end

		print(
			"[CarryCalibration]\n"
				.. domain.formatCarryConfigSnippet(
					calibration.style,
					calibration.offset,
					calibration.rotation,
					calibration.inverse
				)
		)
		return calibration
	end

	function self:onPlayerAdded(player: Player): ()
		if player.Character ~= nil then
			watchCharacterParts(player, player.Character)
		end

		if characterConnections[player.UserId] ~= nil then
			characterConnections[player.UserId]:Disconnect()
		end
		characterConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			task.defer(function()
				watchCharacterParts(player, character)
			end)
		end)
	end

	function self:onPlayerRemoving(player: Player): ()
		pendingRequests[player.UserId] = nil
		if characterConnections[player.UserId] ~= nil then
			characterConnections[player.UserId]:Disconnect()
			characterConnections[player.UserId] = nil
		end
		disconnectCharacterPartWatcher(player.UserId)
		if activeCarries[player.UserId] ~= nil then
			self:endCarry(player)
		end
		stopCarryTracks(player.UserId)
		clearCarriedNetworkOwner(player.UserId)
		restorePartStates(player.UserId)
		savedHumanoidStates[player.UserId] = nil
		savedPartStates[player.UserId] = nil
		activeTracks[player.UserId] = nil
		activeCalibrations[player.UserId] = nil
	end

	return self :: CarryService
end

return create
