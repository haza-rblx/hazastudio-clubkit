--!strict
-- Hollywood-grade choreographed loading camera (30s timeline, 6 shots, smooth transitions)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Constants.Config)
local CinematicConfig = Config.Loading.CINEMATIC

local LoadingCinematicCamera = {} :: any
LoadingCinematicCamera.__index = LoadingCinematicCamera

local BIND_NAME = CinematicConfig.BIND_NAME
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value + CinematicConfig.BIND_PRIORITY_OFFSET
local CFRAME_LERP = CinematicConfig.CFRAME_LERP
local FOV_LERP = CinematicConfig.FOV_LERP
local EASE_DURATION = CinematicConfig.EASE_DURATION
local BREATHE_AMP = CinematicConfig.BREATHE_AMP
local BHANGRA_ANIM_ID = CinematicConfig.ANIMATION_ID

-- ── Helpers ──────────────────────────────────────────────────

local function easeInQuad(t: number): number
	return t * t
end

local function easeInOutQuad(t: number): number
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - (-2 * t + 2) ^ 2 / 2
end

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function noise(t: number, seed: number): number
	return math.sin(t * 1.7 + seed * 3.14) * 0.4
		+ math.sin(t * 3.1 + seed * 2.18) * 0.3
		+ math.sin(t * 5.3 + seed * 1.41) * 0.15
		+ math.sin(t * 8.7 + seed * 0.77) * 0.08
end

local function findBasePart(character: Model, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local child = character:FindFirstChild(name)
		if child and child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function resolveCharParts(character: Model): (BasePart?, BasePart?)
	local root = findBasePart(character, { "HumanoidRootPart", "UpperTorso", "Torso" })
	if not root then
		local p = character.PrimaryPart
		if p and p:IsA("BasePart") then
			root = p
		end
	end
	return root, findBasePart(character, { "Head" })
end

local function getCamera(): Camera?
	local c = Workspace.CurrentCamera
	if c and c:IsA("Camera") then
		return c
	end
	return nil
end

local function getRootAndHead(self: any): (BasePart?, BasePart?)
	local char = self._character
	if not char or not char.Parent then
		char = self._player.Character
		if char then
			self:_refreshCharacter(char)
		end
	elseif not self._rootPart then
		self:_refreshCharacter(char)
	end

	local root = self._rootPart
	return root, self._headPart or root
end

local function getBehindRevealCFrame(root: BasePart, height: number, distance: number): CFrame
	local look = root.CFrame.LookVector
	local focus = root.Position + Vector3.new(0, 2.1, 0)
	local pos = root.Position - look * distance + Vector3.new(0, height, 0)
	return CFrame.lookAt(pos, focus)
end

-- ── Shot Definitions (6 shots × 5s = 30s total) ─────────────
-- Pattern: Full Body → Close Front → Full Body Low → Close Behind → Full Body Crane → Eagle Descent

type Shot = {
	name: string,
	duration: number,
	fn: any,
}

local SHOTS: { Shot } = {
	-- 1. FULL BODY — Slow wide orbit, pulls in gently. Clear head-to-toe reveal.
	{
		name = "Full Body Orbit",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local angle = t * math.pi * 0.7               -- arc ~126°, not a full circle
			local radius = 11 - t * 1.5                   -- slowly drifts inward
			local camH = 2.5 + math.sin(t * math.pi) * 0.8 -- subtle rise/fall
			local pos = root.Position + Vector3.new(
				math.cos(angle) * radius,
				camH,
				math.sin(angle) * radius
			)
			local bodyCenter = root.Position + Vector3.new(0, 1.5, 0) -- mid-body
			return CFrame.lookAt(pos, bodyCenter), 56
		end,
	},

	-- 2. CLOSE-UP FRONT — Slow gliding approach to face, slight left sway, intimate.
	{
		name = "Close-Up Front",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local look  = root.CFrame.LookVector
			local right = root.CFrame.RightVector
			-- Camera drifts toward face (front = -LookVector side)
			local dist = 4.5 - t * 1.6                    -- 4.5 → 2.9 studs, glide in
			local sway  = math.sin(t * math.pi * 1.2) * 0.35
			local pos = head.Position - look * dist + right * sway + Vector3.new(0, 0.15, 0)
			return CFrame.lookAt(pos, head.Position + Vector3.new(0, 0.05, 0)), 44
		end,
	},

	-- 3. FULL BODY LOW HERO — Worm's-eye slow arc. Dramatic silhouette from below.
	{
		name = "Full Body Low Hero",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local angle = t * math.pi * 0.55
			local radius = 7
			-- Camera below root (below feet level)
			local camY = -3.5 + math.sin(t * math.pi) * 0.4
			local pos = root.Position + Vector3.new(
				math.cos(angle) * radius,
				camY,
				math.sin(angle) * radius
			)
			-- Look up at and past the head — shows full silhouette against sky
			return CFrame.lookAt(pos, head.Position + Vector3.new(0, 0.8, 0)), 50
		end,
	},

	-- 4. CLOSE-UP SIDE PROFILE — Camera off to the side at face height, sees the profile.
	--    Classic Hollywood talking-head / character-study shot.
	{
		name = "Close-Up Profile",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local right = root.CFrame.RightVector
			local look  = root.CFrame.LookVector
			-- Sit 4 studs to the right (can also be left — looks elegant either way)
			-- Slow forward drift gives the shot a sense of movement / breathing
			local sideDist = 4.2
			local fwdDrift  = math.sin(t * math.pi * 0.9) * 0.6  -- gently sways toward/away
			local heightBob = math.sin(t * math.pi * 1.1) * 0.12 -- very subtle vertical life
			local pos = head.Position
				+ right * sideDist
				- look * fwdDrift
				+ Vector3.new(0, 0.1 + heightBob, 0)
			-- Look exactly at the face center — tight profile
			return CFrame.lookAt(pos, head.Position + Vector3.new(0, 0.05, 0)), 46
		end,
	},

	-- 5. FULL BODY CRANE — Rising jib, slowly arcing, shows full body growing smaller.
	{
		name = "Full Body Crane",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local e   = easeInOutQuad(t)
			local h   = 2 + e * 14                      -- rises 2 → 16 above root
			local r   = 8 - e * 2                       -- slight pullback
			local a   = -t * math.pi * 0.45             -- slow clockwise arc
			local pos = root.Position + Vector3.new(
				math.cos(a) * r,
				h,
				math.sin(a) * r
			)
			-- Always frame the full body (look at mid-body, not just head)
			return CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0)), 54
		end,
	},

	-- 6. FRONT REVEAL — Level full-body shot from the front. Camera straight, no tilt.
	{
		name = "Front Reveal",
		duration = 5,
		fn = function(root: BasePart, head: BasePart, elapsed: number, dur: number): (CFrame, number)
			local t = elapsed / dur
			local e     = easeInOutQuad(t)
			local look  = root.CFrame.LookVector
			local right = root.CFrame.RightVector

			-- Push in from 10 → 7 studs
			local dist = 10 - e * 3

			-- Camera and look target at the SAME Y = body midpoint → perfectly level, no tilt
			local bodyMid = 1.2  -- midpoint between waist and head
			local sideFloat = math.sin(t * math.pi * 0.5) * 0.35  -- very gentle drift

			local pos = root.Position
				+ look * dist
				+ right * sideFloat
				+ Vector3.new(0, bodyMid, 0)

			-- Same height for look target → horizontal camera axis
			local target = root.Position + Vector3.new(0, bodyMid, 0)
			return CFrame.lookAt(pos, target), 60 - e * 5
		end,
	},
}


-- ── Timeline Resolver ────────────────────────────────────────

local function getShotAtTime(totalElapsed: number): (number, number)
	local acc = 0
	for i, shot in ipairs(SHOTS) do
		if totalElapsed < acc + shot.duration then
			return i, totalElapsed - acc
		end
		acc += shot.duration
	end
	local last = SHOTS[#SHOTS]
	return #SHOTS, last.duration
end

-- ── Constructor ──────────────────────────────────────────────

function LoadingCinematicCamera.new()
	local self = setmetatable({}, LoadingCinematicCamera) :: any
	self._active = false
	self._bound = false
	self._player = Players.LocalPlayer
	self._character = nil
	self._rootPart = nil
	self._headPart = nil
	self._baseCameraState = nil
	self._fallbackAnchor = nil
	self._totalElapsed = 0
	self._shotIndex = 0
	self._txLastCF = CFrame.identity
	self._txLastFov = CinematicConfig.DEFAULT_FIELD_OF_VIEW
	self._txBlend = 1
	self._avatarReady = false
	self._revealMode = nil :: string?
	self._revealElapsed = 0
	self._revealDuration = 0
	self._revealStartCF = nil :: CFrame?
	self._revealMidCF = nil :: CFrame?
	self._revealEndCF = nil :: CFrame?
	self._revealStartFov = CinematicConfig.DEFAULT_FIELD_OF_VIEW
	self._revealEndFov = CinematicConfig.DEFAULT_FIELD_OF_VIEW
	self._charAddedConn = nil
	self._charRemovingConn = nil
	self._danceTrack = nil   -- AnimationTrack for Bhangra during cinematic
	return self
end

-- ── Character Management ─────────────────────────────────────

function LoadingCinematicCamera:_refreshCharacter(character: Model?)
	self._character = character
	if not character then
		self._rootPart = nil
		self._headPart = nil
		return
	end
	local root, head = resolveCharParts(character)
	self._rootPart = if root then (root :: BasePart) else nil
	self._headPart = if (head or root) then ((head or root) :: BasePart) else nil
	if root and not self._avatarReady then
		self._avatarReady = true
		local cam = getCamera()
		if cam then
			self._txLastCF = cam.CFrame
			self._txLastFov = cam.FieldOfView
			self._txBlend = 0
		end
	end
	-- NOTE: _playDanceAnimation is NOT called here to avoid double-call from start()
end

-- ── Dance Animation ──────────────────────────────────────────

function LoadingCinematicCamera:_playDanceAnimation(character: Model)
	-- Stop any existing track first
	self:_stopDanceAnimation()

	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", CinematicConfig.HUMANOID_WAIT_TIMEOUT) :: Humanoid?
	end
	if not humanoid then
		return
	end

	-- Disable the default Animate script so it doesn't fight with our dance
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Enabled = false
	end

	local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", CinematicConfig.ANIMATOR_WAIT_TIMEOUT) :: Animator?
	end
	if not animator then
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = BHANGRA_ANIM_ID

	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()

	if not ok or not result then
		return
	end

	local track = result :: AnimationTrack
	self._danceTrack = track
	track.Priority = Enum.AnimationPriority.Action4  -- Highest priority, overrides everything
	track.Looped = true
	track:Play()
end

function LoadingCinematicCamera:_stopDanceAnimation()
	if self._danceTrack then
		pcall(function()
				local dt_ = self._danceTrack :: AnimationTrack
				dt_:Stop(CinematicConfig.DANCE_STOP_FADE)
			end)
		self._danceTrack = nil
	end
	-- Re-enable the default Animate script so idle/walk work after loading
	local char = self._player and self._player.Character
	if char then
		local animateScript = char:FindFirstChild("Animate")
		if animateScript and animateScript:IsA("LocalScript") then
			animateScript.Enabled = true
		end
	end
end

function LoadingCinematicCamera:_clearCharacter()
	self._character = nil
	self._rootPart = nil
	self._headPart = nil
end

function LoadingCinematicCamera:_stepReveal(dt: number, camera: Camera): boolean
	if not self._revealMode then
		return false
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local duration = math.max(self._revealDuration, 0.05)
	self._revealElapsed = math.min(self._revealElapsed + dt, duration)
	local alpha = math.clamp(self._revealElapsed / duration, 0, 1)
	local eased = if self._revealMode == "click_lift" then easeInOutQuad(alpha) else easeOutCubic(alpha)

	local root = self._rootPart
	if root and self._revealMode == "gameplay_drop" then
		self._revealEndCF = getBehindRevealCFrame(root, 4.2, 11)
	end

	local startCF = self._revealStartCF or camera.CFrame
	local midCF = self._revealMidCF
	local endCF = self._revealEndCF or startCF
	if self._revealMode == "click_lift" and midCF then
		if alpha < 0.62 then
			local phaseAlpha = easeInOutQuad(math.clamp(alpha / 0.62, 0, 1))
			camera.CFrame = startCF:Lerp(midCF, phaseAlpha)
		else
			local phaseAlpha = easeOutCubic(math.clamp((alpha - 0.62) / 0.38, 0, 1))
			camera.CFrame = midCF:Lerp(endCF, phaseAlpha)
		end
	else
		camera.CFrame = startCF:Lerp(endCF, eased)
	end
	camera.FieldOfView = self._revealStartFov + (self._revealEndFov - self._revealStartFov) * eased

	if alpha >= 1 and self._revealMode == "click_lift" then
		self._revealMode = nil
	end

	return true
end

-- ── Render Step ──────────────────────────────────────────────

function LoadingCinematicCamera:_step(dt: number)
	if not self._active then
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	if self:_stepReveal(dt, camera) then
		return
	end

	if not self._baseCameraState then
		self._baseCameraState = {
			cameraType = camera.CameraType,
			cameraSubject = camera.CameraSubject,
			fieldOfView = camera.FieldOfView,
		}
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	;(self :: any)._totalElapsed += dt

	-- Try to acquire character every frame.
	-- Two cases require refresh:
	-- 1. _character is nil/destroyed → grab it fresh
	-- 2. _character is set but _rootPart is nil (HumanoidRootPart hadn't parented yet on first call)
	local char = self._character
	if not char or not char.Parent then
		char = self._player.Character
		if char then
			self:_refreshCharacter(char)
		end
	elseif not self._rootPart then
		-- Character known but HumanoidRootPart not yet found — keep retrying each frame
		self:_refreshCharacter(char)
	end

	local root = self._rootPart
	local head = self._headPart or root
	local cfAlpha = math.clamp(dt * CFRAME_LERP, 0, 1)
	local fovAlpha = math.clamp(dt * FOV_LERP, 0, 1)

	-- Fallback: no avatar yet → gentle orbit around anchor
	if not root or not head then
			if not self._fallbackAnchor then
				self._fallbackAnchor = camera.CFrame.Position + camera.CFrame.LookVector * CinematicConfig.FALLBACK_DISTANCE
			end
			local te: number = self._totalElapsed
		local angle = te * 0.45
		local bob = math.sin(te * 0.8) * 0.35
		local anchor = self._fallbackAnchor :: Vector3
		local tcf = CFrame.lookAt(
			anchor + Vector3.new(math.cos(angle) * 10, 4.5 + bob, math.sin(angle) * 10),
			anchor + Vector3.new(0, 1.75, 0)
		)
		camera.CFrame = camera.CFrame:Lerp(tcf, cfAlpha)
		camera.FieldOfView = camera.FieldOfView + (60 - camera.FieldOfView) * fovAlpha
		return
	end

	-- Determine current shot from timeline
	local shotIdx, shotElapsed = getShotAtTime(self._totalElapsed)
	local shot = SHOTS[shotIdx]
	if not shot then
		return
	end

	-- Detect shot switch → trigger transition
	if shotIdx ~= self._shotIndex then
		self._txLastCF = camera.CFrame
		self._txLastFov = camera.FieldOfView
		self._txBlend = 0
		self._shotIndex = shotIdx
	end

	-- Advance transition blend
	if self._txBlend < 1 then
		self._txBlend = math.min(1, self._txBlend + dt / EASE_DURATION)
	end

	-- Compute target from shot
	local targetCF, targetFov = shot.fn(root, head, shotElapsed, shot.duration)

	-- Add cinematic breathing (subtle handheld feel)
	local te = self._totalElapsed
	local bx = noise(te, 1) * BREATHE_AMP
	local by = noise(te, 2) * BREATHE_AMP
	local br = noise(te, 3) * BREATHE_AMP * 0.5
	targetCF = targetCF * CFrame.Angles(bx, by, br)

	-- Apply transition blending (EaseIn from last snapshot)
	if self._txBlend < 1 then
		local eased = easeInQuad(self._txBlend)
		targetCF = self._txLastCF:Lerp(targetCF, eased)
		targetFov = self._txLastFov + (targetFov - self._txLastFov) * eased
	end

	-- Smooth follow
	camera.CFrame = camera.CFrame:Lerp(targetCF, cfAlpha)
	camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * fovAlpha
end

-- ── Bind / Unbind ────────────────────────────────────────────

function LoadingCinematicCamera:_bind()
	if self._bound then
		return
	end
	self._bound = true
	RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, function(dt)
		self:_step(dt)
	end)
end

function LoadingCinematicCamera:_unbind()
	if self._bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		self._bound = false
	end
end

-- ── Public API ───────────────────────────────────────────────

function LoadingCinematicCamera:playClickLift(duration: number)
	if not self._active then
		return
	end

	local cam = getCamera()
	if not cam then
		return
	end

	local root = getRootAndHead(self)
	local startCF = cam.CFrame
	local endCF = startCF + Vector3.new(0, 18, 0)
	local midCF = startCF + startCF.LookVector * 8
	if root then
		local focus = root.Position + Vector3.new(0, 2.1, 0)
		local toFocus = focus - startCF.Position
		local distance = toFocus.Magnitude
		local forwardDistance = math.max(math.min(distance * 0.58, 14), 5)
		local forward = if distance > 0.001 then toFocus.Unit else startCF.LookVector
		local midPos = startCF.Position + forward * forwardDistance + Vector3.new(0, 0.6, 0)
		local endPos = midPos + Vector3.new(0, 16, 0)
		midCF = CFrame.lookAt(midPos, focus)
		endCF = CFrame.lookAt(endPos, focus + Vector3.new(0, 1.2, 0))
	end

	self._revealMode = "click_lift"
	self._revealElapsed = 0
	self._revealDuration = math.max(duration, 0.05)
	self._revealStartCF = startCF
	self._revealMidCF = midCF
	self._revealEndCF = endCF
	self._revealStartFov = cam.FieldOfView
	self._revealEndFov = 62
end

function LoadingCinematicCamera:playGameplayDrop(duration: number)
	if not self._active then
		return
	end

	local cam = getCamera()
	if not cam then
		return
	end

	self:_stopDanceAnimation()

	local root = getRootAndHead(self)
	local startCF = cam.CFrame
	local endCF = startCF + Vector3.new(0, -14, 0)
	if root then
		startCF = getBehindRevealCFrame(root, 22, 18)
		endCF = getBehindRevealCFrame(root, 4.2, 11)
		cam.CFrame = startCF
	end

	self._revealMode = "gameplay_drop"
	self._revealElapsed = 0
	self._revealDuration = math.max(duration, 0.05)
	self._revealStartCF = startCF
	self._revealEndCF = endCF
	self._revealStartFov = cam.FieldOfView
	self._revealEndFov = CinematicConfig.DEFAULT_FIELD_OF_VIEW
end

function LoadingCinematicCamera:start()
	if self._active then
		return
	end

	self._active = true
	self._totalElapsed = 0
	self._shotIndex = 0
	self._txBlend = 1
	self._avatarReady = false
	self._revealMode = nil
	self._revealElapsed = 0
	self._revealDuration = 0
	self._revealStartCF = nil
	self._revealMidCF = nil
	self._revealEndCF = nil

	self:_refreshCharacter(self._player.Character)

	-- Play dance in a separate task so WaitForChild("Animator") doesn't block start()
	task.spawn(function()
		if self._player.Character and self._active then
			self:_playDanceAnimation(self._player.Character)
		end
	end)

	if self._charAddedConn then
		self._charAddedConn:Disconnect()
	end
	self._charAddedConn = self._player.CharacterAdded:Connect(function(character)
		if self._active then
			self:_refreshCharacter(character)
			task.spawn(function()
				if self._active then
					self:_playDanceAnimation(character)
				end
			end)
		end
	end)

	if self._charRemovingConn then
		self._charRemovingConn:Disconnect()
	end
	self._charRemovingConn = self._player.CharacterRemoving:Connect(function()
		self:_clearCharacter()
	end)

	local cam = getCamera()
		if cam then
		self._baseCameraState = {
			cameraType = cam.CameraType,
			cameraSubject = cam.CameraSubject,
			fieldOfView = cam.FieldOfView,
		}
			self._fallbackAnchor = cam.CFrame.Position + cam.CFrame.LookVector * CinematicConfig.FALLBACK_DISTANCE
			cam.CameraType = Enum.CameraType.Scriptable
		cam.CameraSubject = nil
	end

	self:_bind()
end

function LoadingCinematicCamera:stop()
	if not self._active and not self._bound then
		return
	end

	self._active = false
	self:_stopDanceAnimation()
	self:_unbind()

	if self._charAddedConn ~= nil then
		(self._charAddedConn :: RBXScriptConnection):Disconnect()
		self._charAddedConn = nil
	end
	if self._charRemovingConn ~= nil then
		(self._charRemovingConn :: RBXScriptConnection):Disconnect()
		self._charRemovingConn = nil
	end

	local cam = getCamera()
	if cam then
		pcall(function()
			-- Always force back to Custom — during loading the camera was already
			-- Scriptable when we captured state, so restoring captured type would
			-- just leave it Scriptable forever.
				cam.FieldOfView = CinematicConfig.DEFAULT_FIELD_OF_VIEW
			cam.CameraType = Enum.CameraType.Custom
			-- Restore Humanoid as CameraSubject so Roblox camera works normally
			local char = self._player and self._player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				cam.CameraSubject = humanoid :: Humanoid
			end
		end)
	end

	self._baseCameraState = nil
	self:_clearCharacter()
	self._totalElapsed = 0
	self._shotIndex = 0
	self._fallbackAnchor = nil
	self._revealMode = nil
	self._revealElapsed = 0
	self._revealDuration = 0
	self._revealStartCF = nil
	self._revealMidCF = nil
	self._revealEndCF = nil
end

function LoadingCinematicCamera:destroy()
	self:stop()
end

return LoadingCinematicCamera
