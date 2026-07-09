--!strict
-- Reusable cinematic camera module (no UI).
-- Dispatches to mode definitions in Shared/Utils/CinematicCameraModes.
--
-- Usage:
--   CinematicCameraSystem.startCinematic(character, "PendulumOrbit", 1)
--   CinematicCameraSystem.switchCinematic(character, "FastOrbit", 1) -- hot-swap, spring transition
--   CinematicCameraSystem.startPartCinematic(part, "CCTVView", 1)
--   CinematicCameraSystem.stopCinematic()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Modes = require(script.Parent.CinematicCameraModes)

local CinematicCameraSystem = {}

local function getLocalGraphicsTier(): number
	local player = Players.LocalPlayer
	if not player then
		return 1
	end
	local tier = player:GetAttribute("SettingsGraphicsTier")
	if type(tier) == "number" then
		return math.clamp(math.floor(tier), 0, 2)
	end
	return 1
end

local function cinematicExtrasEnabled(): boolean
	local player = Players.LocalPlayer
	if not player then
		return true
	end
	local extras = player:GetAttribute("SettingsCinematicExtras")
	if type(extras) == "boolean" then
		return extras
	end
	return true
end

local function shouldUseExteriorCctvPath(): boolean
	return cinematicExtrasEnabled() and getLocalGraphicsTier() > 0
end

-- ── State ──────────────────────────────────────────────────
local isActive = false
local renderConn: RBXScriptConnection? = nil
local currentCFrame = CFrame.new()
local currentFOV = 70
local restoreToken = 0

local DEFAULT_TRANSITION_TIME = 0.45
local DEFAULT_LERP_SPEED = 8
local SPRING_LERP_SPEED = 0.55
local SPRING_TIME_MIN = 5.0
local SPRING_TIME_MAX = 12
local SPRING_TRAVEL_RATE = 20
-- Donation / punchy handoff: spring tetap, durasi pendek supaya donator terlihat cepat.
local SNAPPY_SPRING_LERP_SPEED = 0.62
local SNAPPY_SPRING_TIME_MIN = 0.32
local SNAPPY_SPRING_TIME_MAX = 0.72
local SNAPPY_SPRING_TRAVEL_RATE = 55

export type TransitionProfile = "default" | "snappy"
export type CinematicOptions = {
	transitionProfile: TransitionProfile?,
}
local PART_TRANSITION_TIME = 0.30
local PART_LERP_SPEED = 6.5
-- Below this travel distance: quick rig-local blend (movement change). Above: spring glide.
local PART_RIG_SWITCH_TRAVEL_THRESHOLD = 6
local EXTERIOR_APPROACH_ALPHA = 0.82
local SPEED_MIN = 0.25
local SPEED_MAX = 3

local restoreState: {
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	cframe: CFrame,
	fieldOfView: number,
}? = nil

type CharacterParts = { root: BasePart, head: BasePart }
local targetParts: CharacterParts? = nil
local fixedTargetPart: BasePart? = nil

type ActiveCharacterMode = {
	kind: "character",
	def: Modes.CharacterMode,
	state: Modes.ModeState,
}
type ActivePartMode = {
	kind: "part",
	def: Modes.PartMode,
	state: Modes.ModeState,
}
local activeMode: (ActiveCharacterMode | ActivePartMode)? = nil

-- Transition state (shared between render loop iterations)
local transitioning = false
local transitionAlpha = 0
local transitionTime = DEFAULT_TRANSITION_TIME
local transitionLerpSpeed = DEFAULT_LERP_SPEED
local useSpringEasing = false
local transitionStartCFrame: CFrame? = nil
local transitionStartFOV: number? = nil
local transitionUseExteriorPath = false

-- ── Easing helpers ────────────────────────────────────────────
local function easeInOutSine(x: number): number
	return -(math.cos(math.pi * x) - 1) / 2
end

-- Glide pelan: smoothstep (start/end lambat) + tail eksponensial monoton ke 1.
local function easeSpring(x: number): number
	if x >= 1 then
		return 1
	end
	local smooth = x * x * (3 - 2 * x)
	if x < 0.9 then
		return smooth
	end
	local tail = (x - 0.9) / 0.1
	local atNine = 0.9 * 0.9 * (3 - 2 * 0.9)
	local settle = 1 - math.exp(-4 * tail)
	return atNine + (1 - atNine) * settle
end

local function springTransitionTimeForTravel(travel: number, profile: TransitionProfile): number
	if profile == "snappy" then
		return math.clamp(travel / SNAPPY_SPRING_TRAVEL_RATE, SNAPPY_SPRING_TIME_MIN, SNAPPY_SPRING_TIME_MAX)
	end
	return math.clamp(travel / SPRING_TRAVEL_RATE, SPRING_TIME_MIN, SPRING_TIME_MAX)
end

local function beginSpringTransition(travel: number?, useExteriorPath: boolean?, profile: TransitionProfile?)
	local resolvedProfile: TransitionProfile = if profile == "snappy" then "snappy" else "default"
	transitionStartCFrame = currentCFrame
	transitionStartFOV = currentFOV
	if travel then
		transitionTime = springTransitionTimeForTravel(travel, resolvedProfile)
	else
		transitionTime = if resolvedProfile == "snappy" then SNAPPY_SPRING_TIME_MAX else SPRING_TIME_MAX
	end
	transitionLerpSpeed = if resolvedProfile == "snappy" then SNAPPY_SPRING_LERP_SPEED else SPRING_LERP_SPEED
	useSpringEasing = true
	transitionUseExteriorPath = useExteriorPath == true
	transitioning = true
	transitionAlpha = 0
end

local function sampleCharacterTargetFrame(def: Modes.CharacterMode, state: Modes.ModeState, parts: CharacterParts): (CFrame, number)
	local cf, fov = def.update(state, 0, parts.root, parts.head)
	return cf, tonumber(fov) or 70
end

local function beginPartTransition()
	transitionStartCFrame = currentCFrame
	transitionStartFOV = currentFOV
	transitionTime = PART_TRANSITION_TIME
	transitionLerpSpeed = PART_LERP_SPEED
	useSpringEasing = false
	transitionUseExteriorPath = false
	transitioning = true
	transitionAlpha = 0
end

local function beginCctvTargetTransition(targetCF: CFrame, targetFOV: number)
	local startCF = currentCFrame
	local travel = (targetCF.Position - startCF.Position).Magnitude
	if travel >= PART_RIG_SWITCH_TRAVEL_THRESHOLD then
		beginSpringTransition(travel, fixedTargetPart ~= nil and shouldUseExteriorCctvPath())
	else
		beginPartTransition()
	end
end

local function snapPartTarget(targetCF: CFrame, targetFOV: number)
	transitioning = false
	transitionUseExteriorPath = false
	transitionStartCFrame = nil
	transitionStartFOV = nil
	currentCFrame = targetCF
	currentFOV = targetFOV
end

local function isInsidePartBounds(part: BasePart, worldPos: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function blendExteriorCFrame(startCF: CFrame, targetCF: CFrame, part: BasePart, alpha: number): CFrame
	local travel = (targetCF.Position - startCF.Position).Magnitude
	local directPos = startCF.Position:Lerp(targetCF.Position, alpha)
	local up = part.CFrame.UpVector
	if up.Y < 0.35 then
		up = Vector3.yAxis:Lerp(up, 0.35).Unit
	end
	local lift = math.max(part.Size.Magnitude, 2.5) + math.min(travel * 0.06, 10)
	local arcPos = directPos + up * (math.sin(alpha * math.pi) * lift)
	local lookDist = math.clamp(travel * 0.45, 24, 80)
	local startLook = startCF.Position + startCF.LookVector * lookDist
	local endLook = targetCF.Position + targetCF.LookVector * 40
	local lookPoint = startLook:Lerp(endLook, alpha)
	local exteriorCF = CFrame.lookAt(arcPos, lookPoint, up)
	if alpha <= EXTERIOR_APPROACH_ALPHA then
		return exteriorCF
	end
	local settleT = (alpha - EXTERIOR_APPROACH_ALPHA) / (1 - EXTERIOR_APPROACH_ALPHA)
	local settle = settleT * settleT * (3 - 2 * settleT)
	return exteriorCF:Lerp(targetCF, settle)
end

-- CCTV transitions should not linearly lerp through the rig volume (causes pass-through glitch).
local function blendTransitionCFrame(
	startCF: CFrame,
	targetCF: CFrame,
	part: BasePart?,
	alpha: number,
	useExteriorPath: boolean
): CFrame
	if part and useExteriorPath then
		return blendExteriorCFrame(startCF, targetCF, part, alpha)
	end

	local directPos = startCF.Position:Lerp(targetCF.Position, alpha)

	if part then
		local startInside = isInsidePartBounds(part, startCF.Position)
		local endInside = isInsidePartBounds(part, targetCF.Position)
		local directInside = isInsidePartBounds(part, directPos)

		-- Same rig, different movement: stay on destination mount, blend view direction only.
		if not startInside and not endInside then
			local travel = (targetCF.Position - startCF.Position).Magnitude
			if travel < math.max(part.Size.Magnitude, 4) then
				-- Kalau mount posisi sama (mis. cuma movement mengubah look/rotasi),
				-- gunakan interpolasi CFrame langsung supaya tidak degenerative
				-- (CFrame.lookAt butuh arah non-nol).
				if travel < 0.05 then
					return startCF:Lerp(targetCF, alpha)
				end
				local lookPoint = startCF.Position:Lerp(targetCF.Position + targetCF.LookVector, alpha)
				local pose = CFrame.lookAt(targetCF.Position, lookPoint, targetCF.UpVector)
				if alpha >= 0.9 then
					local handoff = (alpha - 0.9) / 0.1
					local handoffEase = handoff * handoff * (3 - 2 * handoff)
					return pose:Lerp(targetCF, handoffEase)
				end
				return pose
			end
		end

		-- Short hop that still clips through rig volume.
		if directInside then
			-- Kalau ini hanya perubahan movement di rig yang sama (travel kecil),
			-- jangan pakai exterior arc karena bisa bikin "pop" saat hampir masuk volume.
			-- Cukup blend arah lihat di mount tujuan.
			local travel = (targetCF.Position - startCF.Position).Magnitude
			if travel < PART_RIG_SWITCH_TRAVEL_THRESHOLD then
				local lookPoint = startCF.Position:Lerp(targetCF.Position + targetCF.LookVector, alpha)
				local pose = CFrame.lookAt(targetCF.Position, lookPoint, targetCF.UpVector)
				if alpha >= 0.9 then
					local handoff = (alpha - 0.9) / 0.1
					local handoffEase = handoff * handoff * (3 - 2 * handoff)
					return pose:Lerp(targetCF, handoffEase)
				end
				return pose
			end

			-- Untuk rig switch (travel besar), gunakan exterior arc agar transisi tidak pass-through.
			return blendExteriorCFrame(startCF, targetCF, part, alpha)
		end
	end

	return startCF:Lerp(targetCF, alpha)
end

local function applyPlayerCameraRestore(camera: Camera)
	camera.CameraType = Enum.CameraType.Custom
	local player = Players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function captureRestoreState(camera: Camera)
	if restoreState then
		return
	end
	if camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	restoreState = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		fieldOfView = camera.FieldOfView,
	}
end

local function disconnectRender()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function resolveCharacterParts(character: Model): CharacterParts?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			root = torso
		end
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		head = root
	end
	if not root then
		return nil
	end
	return { root = root :: BasePart, head = head :: BasePart }
end

-- ── Render loop (single shared connection) ─────────────────
local function startRenderLoop()
	disconnectRender()

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not isActive or not activeMode then
			return
		end

		local targetCF: CFrame
		local targetFOV: number

		if activeMode.kind == "character" then
			if not targetParts or not targetParts.root.Parent or not targetParts.head.Parent then
				CinematicCameraSystem.stopCinematic()
				return
			end
			local cf, fov = activeMode.def.update(activeMode.state, dt, targetParts.root, targetParts.head)
			targetCF = cf
			targetFOV = tonumber(fov) or 70
		elseif activeMode.kind == "part" then
			if not fixedTargetPart or not fixedTargetPart.Parent then
				CinematicCameraSystem.stopCinematic()
				return
			end
			local cf, fov = activeMode.def.update(activeMode.state, dt, fixedTargetPart)
			targetCF = cf
			targetFOV = tonumber(fov) or 70
		else
			return
		end

		if transitioning then
			transitionAlpha = math.min(transitionAlpha + dt / transitionTime, 1)
			local ease = if useSpringEasing then easeSpring(transitionAlpha) else easeInOutSine(transitionAlpha)
			local startCF = transitionStartCFrame or currentCFrame
			local startFOV = transitionStartFOV or currentFOV
			local partForBlend = if activeMode.kind == "part" then fixedTargetPart else nil
			currentCFrame = blendTransitionCFrame(startCF, targetCF, partForBlend, ease, transitionUseExteriorPath)
			currentFOV = startFOV + (targetFOV - startFOV) * ease

			if transitionAlpha >= 1 then
				transitioning = false
				transitionUseExteriorPath = false
				currentCFrame = targetCF
				currentFOV = targetFOV
				transitionStartCFrame = nil
				transitionStartFOV = nil
			end
		else
			local lerpAlpha = math.min(dt * transitionLerpSpeed, 1)
			currentCFrame = currentCFrame:Lerp(targetCF, lerpAlpha)
			currentFOV = currentFOV + (targetFOV - currentFOV) * lerpAlpha
		end

		local cam = Workspace.CurrentCamera
		if cam then
			cam.CFrame = currentCFrame
			cam.FieldOfView = currentFOV
		end
	end)
end

-- ── Public API ─────────────────────────────────────────────

--- Start a new cinematic on a character. Resets everything (first play).
function CinematicCameraSystem.startCinematic(
	character: Model,
	modeName: string?,
	speed: number?,
	options: CinematicOptions?
)
	if isActive then
		CinematicCameraSystem.switchCinematic(character, modeName, speed, options)
		return
	end
	restoreToken += 1
	local clampedSpeed = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
	fixedTargetPart = nil

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local parts = resolveCharacterParts(character)
	if not parts then
		return
	end
	targetParts = parts

	captureRestoreState(camera)

	currentCFrame = camera.CFrame
	currentFOV = camera.FieldOfView
	isActive = true

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local def = Modes.getCharacterMode(modeName)
	local state: Modes.ModeState = { t = 0, speed = clampedSpeed }
	if def.init then
		def.init(state, targetParts.root, targetParts.head)
	end
	activeMode = { kind = "character", def = def, state = state }

	-- Start broadcast: glide dari kamera player (sama seperti ganti target/movement).
	local profile = options and options.transitionProfile
	local targetCF = sampleCharacterTargetFrame(def, state, targetParts :: CharacterParts)
	local travel = (targetCF.Position - currentCFrame.Position).Magnitude
	beginSpringTransition(travel, false, profile)

	startRenderLoop()
end

--- Hot-swap to a new character target with spring transition (broadcast TV feel).
--- Does NOT reset restore state — cinematic stays active, camera glides to new target.
function CinematicCameraSystem.switchCinematic(
	character: Model,
	modeName: string?,
	speed: number?,
	options: CinematicOptions?
)
	if not isActive then
		-- Fallback: kalau belum aktif, start biasa
		CinematicCameraSystem.startCinematic(character, modeName, speed, options)
		return
	end

	local clampedSpeed = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
	fixedTargetPart = nil

	local parts = resolveCharacterParts(character)
	if not parts then
		return
	end
	targetParts = parts

	local def = Modes.getCharacterMode(modeName)
	local state: Modes.ModeState = { t = 0, speed = clampedSpeed }
	if def.init then
		def.init(state, targetParts.root, targetParts.head)
	end
	activeMode = { kind = "character", def = def, state = state }

	local profile = options and options.transitionProfile
	local targetCF = sampleCharacterTargetFrame(def, state, targetParts :: CharacterParts)
	local travel = (targetCF.Position - currentCFrame.Position).Magnitude
	beginSpringTransition(travel, false, profile)
end

--- Start a new cinematic on a part (CCTV). Resets everything (first play).
function CinematicCameraSystem.startPartCinematic(part: BasePart, modeName: string?, speed: number?)
	if isActive then
		CinematicCameraSystem.switchPartCinematic(part, modeName, speed)
		return
	end
	restoreToken += 1
	local clampedSpeed = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
	targetParts = nil
	fixedTargetPart = part

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	captureRestoreState(camera)

	currentCFrame = camera.CFrame
	currentFOV = camera.FieldOfView
	isActive = true

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local def = Modes.getPartMode(modeName)
	local state: Modes.ModeState = { t = 0, speed = clampedSpeed }
	if def.init then
		def.init(state, part)
	end
	activeMode = { kind = "part", def = def, state = state }

	local targetCF, targetFOV = def.update(state, 0, part)
	beginCctvTargetTransition(targetCF, tonumber(targetFOV) or currentFOV)

	startRenderLoop()
end

--- Hot-swap to a new part target with rig-safe short transition.
--- Pass `instant = true` for CCTV-to-CCTV / movement cuts (no fly glide).
function CinematicCameraSystem.switchPartCinematic(part: BasePart, modeName: string?, speed: number?, instant: boolean?)
	if not isActive then
		CinematicCameraSystem.startPartCinematic(part, modeName, speed)
		return
	end

	local clampedSpeed = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
	targetParts = nil
	fixedTargetPart = part

	local def = Modes.getPartMode(modeName)
	local state: Modes.ModeState = { t = 0, speed = clampedSpeed }
	if def.init then
		def.init(state, part)
	end
	activeMode = { kind = "part", def = def, state = state }

	local targetCF, targetFOV = def.update(state, 0, part)
	local resolvedFOV = tonumber(targetFOV) or currentFOV
	if instant == true then
		snapPartTarget(targetCF, resolvedFOV)
	else
		beginCctvTargetTransition(targetCF, resolvedFOV)
	end
end

function CinematicCameraSystem.stopCinematic()
	if not isActive then
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			applyPlayerCameraRestore(camera)
		end
		return
	end
	isActive = false
	activeMode = nil
	transitioning = false
	transitionUseExteriorPath = false
	transitionStartCFrame = nil
	transitionStartFOV = nil
	restoreToken += 1
	local token = restoreToken

	disconnectRender()

	local camera = Workspace.CurrentCamera
	if camera and restoreState then
		local capturedState = restoreState
		restoreState = nil
		targetParts = nil
		fixedTargetPart = nil

		local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local cfTween = TweenService:Create(camera, tweenInfo, { CFrame = capturedState.cframe })
		local fovTween = TweenService:Create(camera, tweenInfo, { FieldOfView = capturedState.fieldOfView })
		cfTween:Play()
		fovTween:Play()

		local restored = false
		local function finishRestore()
			if restored or restoreToken ~= token then
				if not isActive and camera.CameraType == Enum.CameraType.Scriptable then
					applyPlayerCameraRestore(camera)
				end
				return
			end
			if not camera.Parent then
				return
			end
			restored = true
			local restoreType = capturedState.cameraType
			if restoreType == Enum.CameraType.Scriptable then
				restoreType = Enum.CameraType.Custom
			end
			camera.CameraType = restoreType
			camera.FieldOfView = capturedState.fieldOfView

			if restoreType == Enum.CameraType.Custom then
				local player = Players.LocalPlayer
				local character = player and player.Character
				local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
				camera.CameraSubject = humanoid or capturedState.cameraSubject
			else
				camera.CameraSubject = capturedState.cameraSubject
			end
		end

		cfTween.Completed:Connect(finishRestore)
		task.delay(0.55, finishRestore)
	else
		restoreState = nil
		targetParts = nil
		fixedTargetPart = nil
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			applyPlayerCameraRestore(camera)
		end
	end
end

function CinematicCameraSystem.isActive(): boolean
	return isActive
end

function CinematicCameraSystem.setSpeed(speed: number)
	if not activeMode then
		return
	end
	activeMode.state.speed = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
end

function CinematicCameraSystem.getSpeed(): number?
	if not activeMode then
		return nil
	end
	return activeMode.state.speed
end

return CinematicCameraSystem
