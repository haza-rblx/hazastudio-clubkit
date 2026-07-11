--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>

type SavedHumanoidState = {
	platformStand: boolean,
	walkSpeed: number,
	jumpPower: number,
	autoRotate: boolean,
}

type ActiveGravityState = {
	speed: number,
	savedHumanoid: SavedHumanoidState?,
	linearVelocity: LinearVelocity?,
	attachment: Attachment?,
	stateConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

local function createGravityService(deps: {
	carryService: any?,
	notify: any,
})
	local carryService = deps.carryService
	local notify = deps.notify
	local gravityConfig = Config.Gravity
	local log = Logger.new("GravityService")
	local limiter = RateLimiter.new(gravityConfig.RATE_MAX, gravityConfig.RATE_WINDOW)

	local activeStates: { [number]: ActiveGravityState } = {}
	local characterConnections: { [number]: RBXScriptConnection } = {}
	-- Server-wide float mode: while active, all current + joining players float.
	local serverModeSpeed = 0
	local service = {}

	local function getHumanoid(player: Player): Humanoid?
		local character = player.Character
		if character == nil then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid")
	end

	local function getRootPart(player: Player): BasePart?
		local character = player.Character
		if character == nil then
			return nil
		end
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	local function isBlocked(player: Player): (boolean, string?)
		if carryService and type(carryService.getPartnerId) == "function" then
			if carryService:getPartnerId(player.UserId) ~= nil then
				return true, "carry_active"
			end
		end
		return false, nil
	end

	local function speedToFloatVelocity(speed: number): number
		local minSpeed = gravityConfig.MIN_SPEED
		local maxSpeed = gravityConfig.MAX_SPEED
		local clamped = math.clamp(speed, minSpeed, maxSpeed)
		local span = math.max(maxSpeed - minSpeed, 1)
		local t = (clamped - minSpeed) / span
		return gravityConfig.FLOAT_SPEED_AT_MIN + t * (gravityConfig.FLOAT_SPEED_AT_MAX - gravityConfig.FLOAT_SPEED_AT_MIN)
	end

	local function stopFallTracks(humanoid: Humanoid): ()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator == nil then
			return
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			local name = string.lower(track.Name)
			if string.find(name, "fall", 1, true) then
				track:Stop(0)
			end
		end
	end

	local function clearPhysics(state: ActiveGravityState): ()
		if state.heartbeatConnection then
			state.heartbeatConnection:Disconnect()
			state.heartbeatConnection = nil
		end
		if state.stateConnection then
			state.stateConnection:Disconnect()
			state.stateConnection = nil
		end
		if state.linearVelocity then
			state.linearVelocity:Destroy()
			state.linearVelocity = nil
		end
		if state.attachment then
			state.attachment:Destroy()
			state.attachment = nil
		end
	end

	local function restoreHumanoid(player: Player, state: ActiveGravityState): ()
		local humanoid = getHumanoid(player)
		if humanoid and state.savedHumanoid then
			humanoid.PlatformStand = state.savedHumanoid.platformStand
			humanoid.WalkSpeed = state.savedHumanoid.walkSpeed
			humanoid.JumpPower = state.savedHumanoid.jumpPower
			humanoid.AutoRotate = state.savedHumanoid.autoRotate
		end
		state.savedHumanoid = nil
	end

	local function disableUngravity(player: Player, silent: boolean?): Result<nil>
		local state = activeStates[player.UserId]
		if state == nil or state.speed <= 0 then
			return Result.Ok(nil)
		end

		clearPhysics(state)
		restoreHumanoid(player, state)
		state.speed = 0

		local humanoid = getHumanoid(player)
		local hrp = getRootPart(player)
		if hrp then
			local velocity = hrp.AssemblyLinearVelocity
			local damp = math.clamp(tonumber(gravityConfig.RESTORE_HORIZONTAL_DAMP) or 0.35, 0, 1)
			local dropY = tonumber(gravityConfig.RESTORE_DOWNWARD_VELOCITY) or -45
			-- Snap out of float: damp horizontal drift + immediate downward kick.
			hrp.AssemblyLinearVelocity = Vector3.new(velocity.X * damp, math.min(velocity.Y, dropY), velocity.Z * damp)
		end
		if humanoid then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end)
		end

		if not silent then
			notify.player(player, gravityConfig.MSG_DISABLED, "SUCCESS")
		end
		return Result.Ok(nil)
	end

	local function applyUngravity(player: Player, speed: number, silent: boolean?): Result<nil>
		local blocked, reason = isBlocked(player)
		if blocked then
			if reason == "carry_active" and not silent then
				notify.player(player, gravityConfig.MSG_BLOCKED_CARRY, "WARNING")
			end
			return Result.Err(reason or "blocked")
		end

		local humanoid = getHumanoid(player)
		local hrp = getRootPart(player)
		if humanoid == nil or hrp == nil then
			return Result.Err("character_not_ready")
		end

		local state = activeStates[player.UserId]
		if state == nil then
			state = { speed = 0 }
			activeStates[player.UserId] = state
		end

		if state.speed <= 0 then
			state.savedHumanoid = {
				platformStand = humanoid.PlatformStand,
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				autoRotate = humanoid.AutoRotate,
			}
		end

		clearPhysics(state)
		state.speed = speed

		humanoid.PlatformStand = true
		humanoid.AutoRotate = true
		stopFallTracks(humanoid)

		local attachment = Instance.new("Attachment")
		attachment.Name = "ClubKitGravityAttachment"
		attachment.Parent = hrp

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "ClubKitGravityFloat"
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.VectorVelocity = Vector3.new(0, speedToFloatVelocity(speed), 0)
		linearVelocity.MaxForce = math.huge
		linearVelocity.Parent = hrp

		state.attachment = attachment
		state.linearVelocity = linearVelocity

		state.stateConnection = humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Freefall or newState == Enum.HumanoidStateType.FallingDown then
				stopFallTracks(humanoid)
			end
		end)

		state.heartbeatConnection = RunService.Heartbeat:Connect(function()
			if not player.Parent or player.Character ~= humanoid.Parent then
				return
			end
			stopFallTracks(humanoid)
			if state.linearVelocity and state.linearVelocity.Parent then
				state.linearVelocity.VectorVelocity = Vector3.new(0, speedToFloatVelocity(state.speed), 0)
			end
		end)

		if not silent then
			notify.player(player, string.format(gravityConfig.MSG_ENABLED, speed), "SUCCESS")
			log:info("ungravity_enabled", { player = player.Name, speed = speed })
		end
		return Result.Ok(nil)
	end

	local function applyServerModeToPlayer(player: Player): ()
		if serverModeSpeed <= 0 then
			return
		end
		applyUngravity(player, serverModeSpeed, true)
	end

	function service:getSpeed(userId: number): number
		local state = activeStates[userId]
		if state == nil then
			return 0
		end
		return state.speed
	end

	function service:isActive(userId: number): boolean
		return service:getSpeed(userId) > 0
	end

	function service:isServerModeActive(): boolean
		return serverModeSpeed > 0
	end

	function service:getServerModeSpeed(): number
		return serverModeSpeed
	end

	--- Toggle server-wide float. speed <= 0 restores gravity for everyone.
	function service:setServerMode(actor: Player, speed: number, options: { silent: boolean?, skipRateLimit: boolean? }?): Result<nil>
		if Config.FeatureFlags.GravityEnabled ~= true then
			return Result.Err("feature_disabled")
		end
		local silent = options and options.silent == true
		local skipRateLimit = options and options.skipRateLimit == true
		if not skipRateLimit and not limiter:check(actor.UserId) then
			notify.player(actor, gravityConfig.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		if speed <= 0 then
			serverModeSpeed = 0
			for _, player in ipairs(Players:GetPlayers()) do
				disableUngravity(player, true)
			end
			if not silent then
				notify.all(gravityConfig.MSG_DISABLED, "SUCCESS")
			end
			log:info("gravity_restored_all", { actor = actor.Name })
			return Result.Ok(nil)
		end

		local clamped = math.clamp(math.floor(speed + 0.5), gravityConfig.MIN_SPEED, gravityConfig.MAX_SPEED)
		serverModeSpeed = clamped
		for _, player in ipairs(Players:GetPlayers()) do
			applyUngravity(player, clamped, true)
		end
		if not silent then
			notify.all(string.format(gravityConfig.MSG_ENABLED, clamped), "SUCCESS")
		end
		log:info("ungravity_enabled_all", { actor = actor.Name, speed = clamped })
		return Result.Ok(nil)
	end

	-- Back-compat wrappers used by controller / character re-apply paths.
	function service:setSpeed(player: Player, speed: number, options: { silent: boolean?, skipRateLimit: boolean? }?): Result<nil>
		return service:setServerMode(player, speed, options)
	end

	function service:enableDefault(player: Player): Result<nil>
		return service:setServerMode(player, gravityConfig.DEFAULT_SPEED)
	end

	function service:disable(player: Player): Result<nil>
		return service:setServerMode(player, 0)
	end

	function service:handleCommand(player: Player, args: string): Result<nil>
		local trimmed = args:match("^%s*(.-)%s*$") or ""
		if trimmed == "" then
			if serverModeSpeed > 0 then
				notify.player(player, string.format(gravityConfig.MSG_STATUS, serverModeSpeed), "INFO")
			else
				notify.player(player, gravityConfig.MSG_USAGE, "WARNING")
			end
			return Result.Ok(nil)
		end

		local speed = tonumber(trimmed)
		if speed == nil then
			notify.player(player, gravityConfig.MSG_INVALID_SPEED, "WARNING")
			return Result.Err("invalid_speed")
		end

		return service:setServerMode(player, speed)
	end

	function service:onPlayerAdded(player: Player): ()
		if player.Character ~= nil then
			service:onCharacterAdded(player)
		end

		if characterConnections[player.UserId] ~= nil then
			characterConnections[player.UserId]:Disconnect()
		end
		characterConnections[player.UserId] = player.CharacterAdded:Connect(function()
			service:onCharacterAdded(player)
		end)
	end

	function service:onCharacterAdded(player: Player): ()
		local state = activeStates[player.UserId]
		if state then
			state.speed = 0
			state.savedHumanoid = nil
			clearPhysics(state)
		end

		if serverModeSpeed <= 0 then
			return
		end

		task.defer(function()
			if not player.Parent or serverModeSpeed <= 0 then
				return
			end
			applyServerModeToPlayer(player)
		end)
	end

	function service:onPlayerRemoving(player: Player): ()
		if characterConnections[player.UserId] ~= nil then
			characterConnections[player.UserId]:Disconnect()
			characterConnections[player.UserId] = nil
		end

		local state = activeStates[player.UserId]
		if state then
			clearPhysics(state)
			activeStates[player.UserId] = nil
		end
	end

	function service:destroy(): ()
		serverModeSpeed = 0
		for userId, conn in pairs(characterConnections) do
			conn:Disconnect()
			characterConnections[userId] = nil
		end
		for userId, state in pairs(activeStates) do
			clearPhysics(state)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				restoreHumanoid(player, state)
			end
		end
		table.clear(activeStates)
	end

	return service
end

return createGravityService
