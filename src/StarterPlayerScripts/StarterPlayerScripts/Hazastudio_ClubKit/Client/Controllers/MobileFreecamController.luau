--!strict
-- MobileFreecamController — System B (touch-screen freecam)
--
-- Logika ini SEBELUMNYA hidup sebagai LocalScript di dalam ScreenGui
-- "MobileFreecam" (FreecamScript + Topbar). Sekarang dipindah ke controller
-- repo-managed supaya ScreenGui-nya jadi asset tanpa script.
--
-- Akses : SEMUA pemain dengan device touch-screen (UserInputService.TouchEnabled).
--         Device non-touch (PC/console murni) pakai System A (FreecamController,
--         Shift+P). Controller ini no-op di device non-touch.
-- Toggle : Topbar icon (mobile) + tombol close di hidecontrols.
-- GUI    : MobileFreecam ScreenGui di PlayerGui (di-clone dari StarterGui).
--
-- Catatan: gating FreecamConfig.AllowedPlayers yang lama dibuang. Gate sekarang
-- murni device touch-screen sesuai desain.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local pi    = math.pi
local abs   = math.abs
local clamp = math.clamp
local exp   = math.exp
local rad   = math.rad
local sign  = math.sign
local sqrt  = math.sqrt
local tan   = math.tan

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local GUI_NAME = "MobileFreecam"
local LEGACY_GUI_NAME = "Freecam"
local FREECAM_ACTIVE_ATTRIBUTE = "FreecamActive"
local ICON_IMAGE = Config.Icons.Topbar.Camera

-- ── Input priorities & tuning (port dari Roblox Freecam module) ───────────────
local INPUT_PRIORITY = Enum.ContextActionPriority.High.Value

local NAV_GAIN = Vector3.new(1, 1, 1) * 64
local PAN_GAIN = Vector2.new(0.75, 1) * 8
local FOV_GAIN = 300

local PITCH_LIMIT = rad(90)

local VEL_STIFFNESS  = 1.5
local PAN_STIFFNESS  = 1.0
local FOV_STIFFNESS  = 4.0
local ROLL_STIFFNESS = 2.0
local ROLL_GAIN      = 0.5

local NAV_GAMEPAD_SPEED  = Vector3.new(1, 1, 1)
local NAV_KEYBOARD_SPEED = Vector3.new(1, 1, 1)
local PAN_MOUSE_SPEED    = Vector2.new(1, 1) * (pi / 64)
local PAN_GAMEPAD_SPEED  = Vector2.new(1, 1) * (pi / 8)
local FOV_WHEEL_SPEED    = 1.0
local FOV_GAMEPAD_SPEED  = 0.25
local NAV_ADJ_SPEED      = 0.75
local NAV_SHIFT_MUL      = 0.25

-- ── Critically-damped spring (port) ──────────────────────────────────────────
type Spring = {
	f: number,
	p: any,
	v: any,
	Update: (self: Spring, dt: number, goal: any) -> any,
	Reset: (self: Spring, pos: any) -> (),
}

local Spring = {} :: any
Spring.__index = Spring

local function newSpring(freq: number, pos: any): Spring
	return setmetatable({ f = freq, p = pos, v = pos * 0 }, Spring)
end

function Spring.Update(self: Spring, dt: number, goal: any): any
	local f = self.f * 2 * pi
	local p0 = self.p
	local v0 = self.v
	local offset = goal - p0
	local decay = exp(-f * dt)
	local p1 = goal + (v0 * dt - offset * (f * dt + 1)) * decay
	local v1 = (f * dt * (offset * f - v0) + v0) * decay
	self.p = p1
	self.v = v1
	return p1
end

function Spring.Reset(self: Spring, pos: any)
	self.p = pos
	self.v = pos * 0
end

-- ── Factory ───────────────────────────────────────────────────────────────────
local function createMobileFreecamController(deps: {
	icon: any?,
	iconFactory: (() -> any)?,
	applyTopbarStyle: ((any) -> ())?,
	logger: any?,
})
	local log = deps.logger or Logger.new("Client.MobileFreecamController")
	local localPlayer = Players.LocalPlayer

	-- Gate: touch-screen only. Device lain pakai System A.
	if not UserInputService.TouchEnabled then
		log:debug("MobileFreecam skipped: device tidak touch-screen")
		return {
			isActive = function(): boolean return false end,
			destroy = function() end,
		}
	end

	local conns: { RBXScriptConnection } = {}
	local function track(conn: RBXScriptConnection?)
		if conn then
			table.insert(conns, conn)
		end
	end

	local camera = Workspace.CurrentCamera
	track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCamera = Workspace.CurrentCamera
		if newCamera then
			camera = newCamera
		end
	end))

	-- Camera state
	local cameraPos  = Vector3.new()
	local cameraRot  = Vector2.new()
	local cameraFov  = 0
	local cameraRoll = 0

	local velSpring  = newSpring(VEL_STIFFNESS, Vector3.new())
	local panSpring  = newSpring(PAN_STIFFNESS, Vector2.new())
	local fovSpring  = newSpring(FOV_STIFFNESS, 0)
	local rollSpring = newSpring(ROLL_STIFFNESS, 0)

	-- ── Input state ───────────────────────────────────────────
	local K_CURVATURE = 2.0
	local K_DEADZONE = 0.15
	local function fCurve(x: number): number
		return (exp(K_CURVATURE * x) - 1) / (exp(K_CURVATURE) - 1)
	end
	local function fDeadzone(x: number): number
		return fCurve((x - K_DEADZONE) / (1 - K_DEADZONE))
	end
	local function thumbstickCurve(x: number): number
		return sign(x) * clamp(fDeadzone(abs(x)), 0, 1)
	end

	local gamepad: any = {
		ButtonX = 0, ButtonY = 0,
		DPadDown = 0, DPadUp = 0,
		ButtonL2 = 0, ButtonR2 = 0,
		Thumbstick1 = Vector2.new(),
		Thumbstick2 = Vector2.new(),
	}
	local keyboard: any = {
		W = 0, A = 0, S = 0, D = 0, E = 0, Q = 0,
		U = 0, H = 0, J = 0, K = 0, I = 0, Y = 0,
		Up = 0, Down = 0,
		LeftShift = 0, RightShift = 0,
		Z = 0, X = 0, C = 0,
	}
	local mouse: any = {
		Delta = Vector2.new(),
		MouseWheel = 0,
	}

	local navSpeed = 1

	local function inputVel(dt: number): Vector3
		navSpeed = clamp(navSpeed + dt * (keyboard.Up - keyboard.Down) * NAV_ADJ_SPEED, 0.01, 4)
		local kGamepad = Vector3.new(
			thumbstickCurve(gamepad.Thumbstick1.X),
			thumbstickCurve(gamepad.ButtonR2) - thumbstickCurve(gamepad.ButtonL2),
			thumbstickCurve(-gamepad.Thumbstick1.Y)
		) * NAV_GAMEPAD_SPEED
		local kKeyboard = Vector3.new(
			keyboard.D - keyboard.A + keyboard.K - keyboard.H,
			keyboard.E - keyboard.Q + keyboard.I - keyboard.Y,
			keyboard.S - keyboard.W + keyboard.J - keyboard.U
		) * NAV_KEYBOARD_SPEED
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		return (kGamepad + kKeyboard) * (navSpeed * (shift and NAV_SHIFT_MUL or 1))
	end

	local function inputPan(_dt: number): Vector2
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			and not UserInputService.MouseEnabled and not UserInputService.GamepadEnabled
			and not GuiService:IsTenFootInterface() then
			local mdx = -UserInputService:GetMouseDelta().X
			local mdy = -UserInputService:GetMouseDelta().Y
			mouse.Delta = Vector2.new(mdy, mdx)
		end
		local kGamepad = Vector2.new(
			thumbstickCurve(gamepad.Thumbstick2.Y),
			thumbstickCurve(-gamepad.Thumbstick2.X)
		) * PAN_GAMEPAD_SPEED
		local kMouse = mouse.Delta * PAN_MOUSE_SPEED
		mouse.Delta = Vector2.new()
		return kGamepad + kMouse
	end

	local function inputFov(_dt: number): number
		local kGamepad = (gamepad.ButtonX - gamepad.ButtonY) * FOV_GAMEPAD_SPEED
		local kMouse = mouse.MouseWheel * FOV_WHEEL_SPEED
		mouse.MouseWheel = 0
		return kGamepad + kMouse
	end

	-- ── CAS capture (keyboard/mouse/gamepad) ──────────────────
	local function keypress(_action, state, input)
		keyboard[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
		return Enum.ContextActionResult.Sink
	end
	local function gpButton(_action, state, input)
		gamepad[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
		return Enum.ContextActionResult.Sink
	end
	local function mousePan(_action, _state, input)
		local delta = input.Delta
		mouse.Delta = Vector2.new(-delta.Y, -delta.X)
		return Enum.ContextActionResult.Sink
	end
	local function thumb(_action, _state, input)
		gamepad[input.KeyCode.Name] = input.Position
		return Enum.ContextActionResult.Sink
	end
	local function trigger(_action, _state, input)
		gamepad[input.KeyCode.Name] = input.Position.Z
		return Enum.ContextActionResult.Sink
	end
	local function mouseWheel(_action, _state, input)
		mouse[input.UserInputType.Name] = -input.Position.Z
		return Enum.ContextActionResult.Sink
	end
	local function zero(t: any)
		for k, v in pairs(t) do
			t[k] = v * 0
		end
	end

	local function startCapture()
		ContextActionService:BindActionAtPriority("MobileFreecamKeyboard", keypress, false, INPUT_PRIORITY,
			Enum.KeyCode.W, Enum.KeyCode.U,
			Enum.KeyCode.A, Enum.KeyCode.H,
			Enum.KeyCode.S, Enum.KeyCode.J,
			Enum.KeyCode.D, Enum.KeyCode.K,
			Enum.KeyCode.E, Enum.KeyCode.I,
			Enum.KeyCode.Q, Enum.KeyCode.Y,
			Enum.KeyCode.Up, Enum.KeyCode.Down,
			Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C)
		ContextActionService:BindActionAtPriority("MobileFreecamMousePan", mousePan, false, INPUT_PRIORITY, Enum.UserInputType.MouseMovement)
		ContextActionService:BindActionAtPriority("MobileFreecamMouseWheel", mouseWheel, false, INPUT_PRIORITY, Enum.UserInputType.MouseWheel)
		ContextActionService:BindActionAtPriority("MobileFreecamGamepadButton", gpButton, false, INPUT_PRIORITY, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)
		ContextActionService:BindActionAtPriority("MobileFreecamGamepadTrigger", trigger, false, INPUT_PRIORITY, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
		ContextActionService:BindActionAtPriority("MobileFreecamGamepadThumbstick", thumb, false, INPUT_PRIORITY, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2)
	end

	local function stopCapture()
		navSpeed = 1
		zero(gamepad)
		zero(keyboard)
		zero(mouse)
		ContextActionService:UnbindAction("MobileFreecamKeyboard")
		ContextActionService:UnbindAction("MobileFreecamMousePan")
		ContextActionService:UnbindAction("MobileFreecamMouseWheel")
		ContextActionService:UnbindAction("MobileFreecamGamepadButton")
		ContextActionService:UnbindAction("MobileFreecamGamepadTrigger")
		ContextActionService:UnbindAction("MobileFreecamGamepadThumbstick")
	end

	-- ── Focus distance (autofocus for DOF) ────────────────────
	local function getFocusDistance(cameraFrame: CFrame): number
		local znear = 0.1
		local viewport = camera.ViewportSize
		local projy = 2 * tan(cameraFov / 2)
		local projx = viewport.X / viewport.Y * projy
		local fx = cameraFrame.RightVector
		local fy = cameraFrame.UpVector
		local fz = cameraFrame.LookVector
		local minVect = Vector3.new()
		local minDist = 512
		for x = 0, 1, 0.5 do
			for y = 0, 1, 0.5 do
				local cx = (x - 0.5) * projx
				local cy = (y - 0.5) * projy
				local offset = fx * cx - fy * cy + fz
				local origin = cameraFrame.Position + offset * znear
				local params = RaycastParams.new()
				local result = Workspace:Raycast(origin, offset.Unit * minDist, params)
				local hit = if result then result.Position else origin + offset.Unit * minDist
				local dist = (hit - origin).Magnitude
				if minDist > dist then
					minDist = dist
					minVect = offset.Unit
				end
			end
		end
		return fz:Dot(minVect) * minDist
	end

	-- ── Per-frame camera step ─────────────────────────────────
	local function stepFreecam(dt: number)
		local vel = velSpring:Update(dt, inputVel(dt))
		local pan = panSpring:Update(dt, inputPan(dt))
		local fov = fovSpring:Update(dt, inputFov(dt))

		local zoomFactor = sqrt(tan(rad(70 / 2)) / tan(rad(cameraFov / 2)))

		cameraFov = clamp(cameraFov + fov * FOV_GAIN * (dt / zoomFactor), 1, 120)
		cameraRot = cameraRot + pan * PAN_GAIN * (dt / zoomFactor)
		cameraRot = Vector2.new(clamp(cameraRot.X, -PITCH_LIMIT, PITCH_LIMIT), cameraRot.Y % (2 * pi))

		-- Roll: Z = tilt kiri, C = tilt kanan, X = reset ke 0 (smooth)
		if keyboard.X == 1 then
			cameraRoll = rollSpring:Update(dt, 0)
		else
			rollSpring:Reset(cameraRoll)
			cameraRoll = cameraRoll + (keyboard.Z - keyboard.C) * ROLL_GAIN * dt
		end

		local cameraCFrame = CFrame.new(cameraPos)
			* CFrame.fromOrientation(cameraRot.X, cameraRot.Y, cameraRoll)
			* CFrame.new(vel * NAV_GAIN * dt)
		cameraPos = cameraCFrame.Position
		camera.CFrame = cameraCFrame
		camera.Focus = cameraCFrame * CFrame.new(0, 0, -getFocusDistance(cameraCFrame))
		camera.FieldOfView = cameraFov
	end

	-- ── Player state push/pop (GUI + camera + mouse) ──────────
	local savedMouseBehavior: Enum.MouseBehavior? = nil
	local savedMouseIconEnabled: boolean? = nil
	local savedCameraType: Enum.CameraType? = nil
	local savedCameraSubject: Instance? = nil
	local hasSavedCameraSubject = false
	local savedCameraFocus: CFrame? = nil
	local savedCameraCFrame: CFrame? = nil
	local savedCameraFov: number? = nil
	local savedHumanoidAutoRotate: boolean? = nil
	local playerControls: any = nil
	local hiddenScreenGuis: { ScreenGui } = {}

	local function getPlayerControls(): any
		local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
		if not playerScripts then
			return nil
		end
		local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
		if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
			return nil
		end
		local ok, playerModule = pcall(require, playerModuleScript)
		if not ok or type(playerModule) ~= "table" or type(playerModule.GetControls) ~= "function" then
			return nil
		end
		local okControls, controls = pcall(function()
			return playerModule:GetControls()
		end)
		if okControls then
			return controls
		end
		return nil
	end

	local function getLocalHumanoid(): Humanoid?
		local character = localPlayer.Character
		if not character then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid")
	end

	local function lockCharacterMovement()
		playerControls = getPlayerControls()
		if playerControls and type(playerControls.Disable) == "function" then
			pcall(function()
				playerControls:Disable()
			end)
		end

		local humanoid = getLocalHumanoid()
		if humanoid then
			savedHumanoidAutoRotate = humanoid.AutoRotate
			humanoid.AutoRotate = false
		else
			savedHumanoidAutoRotate = nil
		end
	end

	local function unlockCharacterMovement()
		if playerControls and type(playerControls.Enable) == "function" then
			pcall(function()
				playerControls:Enable()
			end)
		end
		playerControls = nil

		if savedHumanoidAutoRotate ~= nil then
			local humanoid = getLocalHumanoid()
			if humanoid then
				humanoid.AutoRotate = savedHumanoidAutoRotate
			end
			savedHumanoidAutoRotate = nil
		end
	end

	local coreGuiSaved: { [string]: boolean } = {}
	local HIDDEN_CORE_GUIS = { "Backpack", "Chat", "Health", "PlayerList" }
	local setCoreSaved: { [string]: boolean } = {}
	local HIDDEN_SET_CORES = { "BadgesNotificationsActive", "PointsNotificationsActive" }

	-- ScreenGui yang TIDAK boleh di-hide saat freecam (UI freecam sendiri + topbar).
	local KEEP_VISIBLE: { [string]: boolean } = {
		[GUI_NAME] = true,
		TopbarPlus = true,
		TopbarPlusGui = true,
		TopbarPlusHolder = true,
		TopbarIcons = true,
	}

	local function pushState()
		for _, name in ipairs(HIDDEN_CORE_GUIS) do
			local ok, enabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType[name])
			end)
			if ok then
				coreGuiSaved[name] = enabled
			end
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], false)
			end)
		end
		for _, name in ipairs(HIDDEN_SET_CORES) do
			local ok, value = pcall(function()
				return StarterGui:GetCore(name)
			end)
			if ok then
				setCoreSaved[name] = value
			end
			pcall(function()
				StarterGui:SetCore(name, false)
			end)
		end

		table.clear(hiddenScreenGuis)
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, gui in ipairs(playerGui:GetChildren()) do
				if gui:IsA("ScreenGui") and gui.Enabled and not KEEP_VISIBLE[gui.Name] then
					table.insert(hiddenScreenGuis, gui)
					gui.Enabled = false
				end
			end
		end

		savedCameraFov = camera.FieldOfView
		camera.FieldOfView = 70
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Custom
		savedCameraSubject = camera.CameraSubject
		hasSavedCameraSubject = true
		camera.CameraSubject = nil
		camera:SetAttribute(FREECAM_ACTIVE_ATTRIBUTE, true)
		savedCameraCFrame = camera.CFrame
		savedCameraFocus = camera.Focus
		lockCharacterMovement()
		savedMouseIconEnabled = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		savedMouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	local function popState()
		for name, enabled in pairs(coreGuiSaved) do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], enabled)
			end)
		end
		table.clear(coreGuiSaved)
		for name, value in pairs(setCoreSaved) do
			pcall(function()
				StarterGui:SetCore(name, value)
			end)
		end
		table.clear(setCoreSaved)

		for _, gui in ipairs(hiddenScreenGuis) do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenScreenGuis)

		unlockCharacterMovement()

		if savedCameraFov ~= nil then camera.FieldOfView = savedCameraFov end
		if savedCameraType ~= nil then camera.CameraType = savedCameraType end
		if hasSavedCameraSubject then
			camera.CameraSubject = savedCameraSubject
			hasSavedCameraSubject = false
		end
		if savedCameraCFrame ~= nil then camera.CFrame = savedCameraCFrame end
		if savedCameraFocus ~= nil then camera.Focus = savedCameraFocus end
		camera:SetAttribute(FREECAM_ACTIVE_ATTRIBUTE, false)
		-- Always unlock after freecam (do not restore LockCenter from push / shift-lock).
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		task.defer(function()
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)
		task.delay(0.05, function()
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)

		savedCameraFov = nil
		savedCameraType = nil
		savedCameraSubject = nil
		savedCameraCFrame = nil
		savedCameraFocus = nil
		savedMouseIconEnabled = nil
		savedMouseBehavior = nil
	end

	-- ── Start / stop ──────────────────────────────────────────
	local active = false

	local function startFreecam()
		local cf = camera.CFrame
		cameraRot = Vector2.new(cf:ToEulerAnglesYXZ())
		cameraPos = cf.Position
		cameraFov = camera.FieldOfView
		cameraRoll = 0
		velSpring:Reset(Vector3.new())
		panSpring:Reset(Vector2.new())
		fovSpring:Reset(0)
		rollSpring:Reset(0)
		pushState()
		RunService:BindToRenderStep("MobileFreecam", Enum.RenderPriority.Camera.Value, stepFreecam)
		startCapture()
	end

	local function stopFreecam()
		stopCapture()
		pcall(function()
			RunService:UnbindFromRenderStep("MobileFreecam")
		end)
		popState()
	end

	-- ── GUI resolution ────────────────────────────────────────
	-- ScreenGui MobileFreecam diharapkan ada di PlayerGui (di-clone dari StarterGui
	-- oleh bootstrap). Strukturnya: MobileControls{Movement{forward,back,left,right},
	-- zoomIn, zoomOut}, hidecontrols{shown, hidden, close, TextButton}.
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(GUI_NAME) or playerGui:FindFirstChild(LEGACY_GUI_NAME)
	if not gui then
		gui = playerGui:WaitForChild(GUI_NAME, 8)
		if not gui then
			gui = playerGui:WaitForChild(LEGACY_GUI_NAME, 12)
		end
	end
	if not gui or not gui:IsA("ScreenGui") then
		log:warn("MobileFreecam GUI tidak ditemukan; controller idle")
		return {
			isActive = function(): boolean return false end,
			destroy = function() end,
		}
	end
	local screenGui = gui :: ScreenGui
	screenGui.ResetOnSpawn = false

	local mobileControls = screenGui:FindFirstChild("MobileControls")
	local hideControls = screenGui:FindFirstChild("hidecontrols")

	-- Hold-to-move binding: tekan = set 1, lepas/leave = set 0.
	local function bindHold(button: Instance?, key: string)
		if not button or not button:IsA("GuiButton") then
			return
		end
		local btn = button :: GuiButton
		track(btn.MouseButton1Down:Connect(function()
			keyboard[key] = 1
		end))
		track(btn.MouseButton1Up:Connect(function()
			keyboard[key] = 0
		end))
		track(btn.MouseLeave:Connect(function()
			keyboard[key] = 0
		end))
	end

	local function resolveButton(parent: Instance?, path: { string }): Instance?
		local current: Instance? = parent
		for _, name in ipairs(path) do
			if not current then
				return nil
			end
			current = current:FindFirstChild(name)
		end
		return current
	end

	if mobileControls then
		local movement = mobileControls:FindFirstChild("Movement")
		if movement then
			bindHold(resolveButton(movement, { "forward", "TextButton" }), "W")
			bindHold(resolveButton(movement, { "back", "TextButton" }), "S")
			bindHold(resolveButton(movement, { "right", "TextButton" }), "D")
			bindHold(resolveButton(movement, { "left", "TextButton" }), "A")
		end

		-- Zoom: hold-to-zoom via render loop flag, lebih halus dari while-wait lama.
		local zoomIn = resolveButton(mobileControls, { "zoomIn", "TextButton" })
		local zoomOut = resolveButton(mobileControls, { "zoomOut", "TextButton" })
		local zoomDir = 0
		track(RunService.RenderStepped:Connect(function()
			if zoomDir ~= 0 then
				mouse.MouseWheel += 0.5 * zoomDir
			end
		end))
		if zoomIn and zoomIn:IsA("GuiButton") then
			track((zoomIn :: GuiButton).MouseButton1Down:Connect(function() zoomDir = -1 end))
			track((zoomIn :: GuiButton).MouseButton1Up:Connect(function() zoomDir = 0 end))
			track((zoomIn :: GuiButton).MouseLeave:Connect(function() zoomDir = 0 end))
		end
		if zoomOut and zoomOut:IsA("GuiButton") then
			track((zoomOut :: GuiButton).MouseButton1Down:Connect(function() zoomDir = 1 end))
			track((zoomOut :: GuiButton).MouseButton1Up:Connect(function() zoomDir = 0 end))
			track((zoomOut :: GuiButton).MouseLeave:Connect(function() zoomDir = 0 end))
		end
	end

	-- ── Toggle + visibility ───────────────────────────────────
	local topbarIcon = deps.icon
	local hidden = false

	local function setControlsVisible(isOn: boolean)
		if mobileControls and mobileControls:IsA("GuiObject") then
			(mobileControls :: GuiObject).Visible = isOn
		end
		if hideControls and hideControls:IsA("GuiObject") then
			(hideControls :: GuiObject).Visible = isOn
			local shown = hideControls:FindFirstChild("shown")
			local hiddenFrame = hideControls:FindFirstChild("hidden")
			if shown and shown:IsA("GuiObject") then shown.Visible = isOn end
			if hiddenFrame and hiddenFrame:IsA("GuiObject") then hiddenFrame.Visible = false end
		end
		hidden = false
	end

	local function setActive(isOn: boolean)
		if isOn == active then
			return
		end
		active = isOn
		if isOn then
			startFreecam()
			setControlsVisible(true)
		else
			stopFreecam()
			setControlsVisible(false)
			if topbarIcon and type(topbarIcon.setState) == "function" then
				pcall(function() topbarIcon:setState("deselected") end)
			elseif topbarIcon and type(topbarIcon.deselect) == "function" then
				pcall(function() topbarIcon:deselect() end)
			end
		end
	end

	-- hidecontrols: tombol show/hide untuk mobile controls + tombol close (exit).
	if hideControls then
		local closeBtn = hideControls:FindFirstChild("close")
		if closeBtn and closeBtn:IsA("GuiButton") then
			track((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
				setActive(false)
			end))
		end
		local toggleBtn = hideControls:FindFirstChild("TextButton")
		if toggleBtn and toggleBtn:IsA("GuiButton") then
			track((toggleBtn :: GuiButton).MouseButton1Click:Connect(function()
				hidden = not hidden
				local shown = hideControls:FindFirstChild("shown")
				local hiddenFrame = hideControls:FindFirstChild("hidden")
				if shown and shown:IsA("GuiObject") then shown.Visible = not hidden end
				if hiddenFrame and hiddenFrame:IsA("GuiObject") then hiddenFrame.Visible = hidden end
				if mobileControls and mobileControls:IsA("GuiObject") then
					(mobileControls :: GuiObject).Visible = not hidden
				end
			end))
		end
	end

	-- Start hidden until toggled on.
	setControlsVisible(false)

	-- Topbar icon: kalau Main belum kasih, bikin sendiri dari iconFactory.
	if not topbarIcon and deps.iconFactory then
		local ok, created = pcall(function()
			return deps.iconFactory()
		end)
		if ok and created then
			topbarIcon = created
			pcall(function()
				if type(ICON_IMAGE) == "string" and ICON_IMAGE ~= "" then
					topbarIcon:setImage(ICON_IMAGE)
				end
			end)
			if deps.applyTopbarStyle then
				pcall(function()
					deps.applyTopbarStyle(topbarIcon)
				end)
			end
		end
	end
	if topbarIcon then
		if topbarIcon.selected and type(topbarIcon.selected.Connect) == "function" then
			track(topbarIcon.selected:Connect(function()
				setActive(true)
			end))
		end
		if topbarIcon.deselected and type(topbarIcon.deselected.Connect) == "function" then
			track(topbarIcon.deselected:Connect(function()
				setActive(false)
			end))
		end
	end

	track(localPlayer.CharacterAdded:Connect(function()
		if active then
			setActive(false)
		end
	end))

	log:info("MobileFreecamController initialized")

	return {
		isActive = function(): boolean
			return active
		end,
		toggle = function()
			setActive(not active)
		end,
		destroy = function()
			if active then
				setActive(false)
			end
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			table.clear(conns)
			if topbarIcon and type(topbarIcon.destroy) == "function" then
				pcall(function() topbarIcon:destroy() end)
			end
		end,
	}
end

return createMobileFreecamController
