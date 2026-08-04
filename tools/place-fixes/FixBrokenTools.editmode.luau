-- Place-only tool fixes (not Club Kit). Run once via execute_luau / Command Bar.

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local results = {}

local function note(msg)
	table.insert(results, msg)
end

-- DualGlowStick: ReplicatedStorage.DuelWeld
local duel = RS:FindFirstChild("DuelWeld")
if not duel then
	duel = Instance.new("Folder")
	duel.Name = "DuelWeld"
	duel.Parent = RS
	note("created DuelWeld")
end
for _, name in ipairs({ "LeftGrip", "RightGrip" }) do
	local m = duel:FindFirstChild(name)
	if not m then
		m = Instance.new("Motor6D")
		m.Name = name
		m.C0 = CFrame.new()
		m.C1 = CFrame.new()
		m.Parent = duel
		note("created " .. name)
	end
end

-- HeartCoil: CoilBoostEvent + server handler outside Hazastudio_ClubKit
local coilEv = RS:FindFirstChild("CoilBoostEvent")
if not coilEv then
	coilEv = Instance.new("RemoteEvent")
	coilEv.Name = "CoilBoostEvent"
	coilEv.Parent = RS
	note("created CoilBoostEvent")
end

local placeFix = SSS:FindFirstChild("PlaceToolsFix")
if not placeFix then
	placeFix = Instance.new("Folder")
	placeFix.Name = "PlaceToolsFix"
	placeFix.Parent = SSS
	note("created PlaceToolsFix")
end

local coilServer = placeFix:FindFirstChild("CoilBoostServer")
if not coilServer then
	coilServer = Instance.new("Script")
	coilServer.Name = "CoilBoostServer"
	coilServer.Parent = placeFix
	note("created CoilBoostServer")
end
coilServer.Source = table.concat({
	"-- Place-only (not Club Kit). Syncs HeartCoil WalkSpeed requests.",
	'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
	'local Players = game:GetService("Players")',
	"",
	'local CoilBoostEvent = ReplicatedStorage:WaitForChild("CoilBoostEvent")',
	"",
	"local MIN_SPEED = 8",
	"local MAX_SPEED = 80",
	"",
	"CoilBoostEvent.OnServerEvent:Connect(function(player, speed)",
	'\tif typeof(speed) ~= "number" then',
	"\t\treturn",
	"\tend",
	"\tspeed = math.clamp(speed, MIN_SPEED, MAX_SPEED)",
	"\tlocal character = player.Character",
	"\tif not character then",
	"\t\treturn",
	"\tend",
	'\tlocal humanoid = character:FindFirstChildOfClass("Humanoid")',
	"\tif not humanoid or humanoid.Health <= 0 then",
	"\t\treturn",
	"\tend",
	"\thumanoid.WalkSpeed = speed",
	"end)",
	"",
	"Players.PlayerAdded:Connect(function(player)",
	"\tplayer.CharacterRemoving:Connect(function(character)",
	'\t\tlocal humanoid = character:FindFirstChildOfClass("Humanoid")',
	"\t\tif humanoid then",
	"\t\t\thumanoid.WalkSpeed = 16",
	"\t\tend",
	"\tend)",
	"end)",
	"",
}, "\n")

-- Selfie: FOVState + StarterGui.FOV
local fovState = RS:FindFirstChild("FOVState")
if not fovState then
	fovState = Instance.new("ModuleScript")
	fovState.Name = "FOVState"
	fovState.Parent = RS
	note("created FOVState")
end
fovState.Source = table.concat({
	"-- Place-only FOV state for Selfie tool.",
	"local FOVState = {",
	"\tLastCustomFOV = 40,",
	"}",
	"return FOVState",
	"",
}, "\n")

local fovGui = StarterGui:FindFirstChild("FOV")
if not fovGui then
	fovGui = Instance.new("ScreenGui")
	fovGui.Name = "FOV"
	fovGui.ResetOnSpawn = false
	fovGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fovGui.Parent = StarterGui
	note("created StarterGui.FOV")
end
local fovFrame = fovGui:FindFirstChild("FOV")
if not fovFrame then
	fovFrame = Instance.new("Frame")
	fovFrame.Name = "FOV"
	fovFrame.BackgroundTransparency = 1
	fovFrame.Size = UDim2.fromScale(1, 1)
	fovFrame.Visible = false
	fovFrame.Parent = fovGui
	local tip = Instance.new("TextLabel")
	tip.Name = "Hint"
	tip.BackgroundTransparency = 1
	tip.Size = UDim2.new(0, 200, 0, 24)
	tip.Position = UDim2.new(0.5, -100, 0.88, 0)
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = 14
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.TextTransparency = 0.25
	tip.Text = "Selfie FOV"
	tip.Parent = fovFrame
	note("created FOV.FOV frame")
end

-- Patch scripts in every Tools/<role>/ copy
local DualScript = table.concat({
	"-- Place-fixed DualGlowStick weld (uses ReplicatedStorage.DuelWeld).",
	'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
	'local duelFolder = ReplicatedStorage:WaitForChild("DuelWeld")',
	'local grip = duelFolder:WaitForChild("LeftGrip")',
	'local grip2 = duelFolder:WaitForChild("RightGrip")',
	"local tool = script.Parent",
	"local activeWeld = nil",
	"",
	"local function clearWeld()",
	"\tif activeWeld then",
	"\t\tactiveWeld:Destroy()",
	"\t\tactiveWeld = nil",
	"\tend",
	"end",
	"",
	"tool.Equipped:Connect(function()",
	"\tclearWeld()",
	"\tlocal char = tool.Parent",
	"\tif not char then",
	"\t\treturn",
	"\tend",
	'\tlocal left = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")',
	'\tlocal handle2 = tool:FindFirstChild("Handle2")',
	"\tif not left or not handle2 then",
	"\t\treturn",
	"\tend",
	"\tlocal weldClone = grip:Clone()",
	"\tweldClone.C0 = grip2.C0",
	"\tweldClone.C1 = tool.Grip",
	"\tweldClone.Part0 = left",
	"\tweldClone.Part1 = handle2",
	"\tweldClone.Parent = left",
	"\tactiveWeld = weldClone",
	"end)",
	"",
	"tool.Unequipped:Connect(clearWeld)",
	"",
}, "\n")

local SelfieScript = table.concat({
	"-- Place-fixed Selfie FOV (Player casing + optional GUI/module).",
	"local Tool = script.Parent",
	'local Player = game:GetService("Players").LocalPlayer',
	"local Camera = workspace.CurrentCamera",
	'local TweenService = game:GetService("TweenService")',
	'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
	"",
	'local gui = Player:WaitForChild("PlayerGui")',
	'local fovScreen = gui:WaitForChild("FOV", 10)',
	"if not fovScreen then",
	'\twarn("[Selfie] FOV GUI missing, selfie FOV disabled")',
	"\treturn",
	"end",
	"",
	'local FOVGui = fovScreen:WaitForChild("FOV", 10)',
	"if not FOVGui then",
	'\twarn("[Selfie] FOV frame missing")',
	"\treturn",
	"end",
	"",
	'local fovStateModule = ReplicatedStorage:WaitForChild("FOVState", 10)',
	"if not fovStateModule then",
	'\twarn("[Selfie] FOVState missing")',
	"\treturn",
	"end",
	"local FOVState = require(fovStateModule)",
	"",
	"local EquipAnimTrack",
	"",
	"local function tweenFOVToCustom()",
	"\tTweenService:Create(Camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {",
	"\t\tFieldOfView = FOVState.LastCustomFOV or 40,",
	"\t}):Play()",
	"end",
	"",
	"local function tweenFOVToDefault()",
	"\tTweenService:Create(Camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {",
	"\t\tFieldOfView = 70,",
	"\t}):Play()",
	"end",
	"",
	"Tool.Equipped:Connect(function()",
	"\tlocal Character = Player.Character",
	'\tif Character and Character:FindFirstChildOfClass("Humanoid") then',
	'\t\tlocal humanoid = Character:FindFirstChildOfClass("Humanoid")',
	'\t\tlocal Animation = Instance.new("Animation")',
	'\t\tAnimation.AnimationId = "rbxassetid://131307365418579"',
	"\t\tEquipAnimTrack = humanoid:LoadAnimation(Animation)",
	"\t\tEquipAnimTrack.Priority = Enum.AnimationPriority.Action",
	"\t\tpcall(function()",
	"\t\t\tEquipAnimTrack:Play()",
	"\t\tend)",
	"\tend",
	"\tFOVGui.Visible = true",
	"\ttweenFOVToCustom()",
	"end)",
	"",
	"Tool.Unequipped:Connect(function()",
	"\tif EquipAnimTrack then",
	"\t\tEquipAnimTrack:Stop()",
	"\t\tEquipAnimTrack = nil",
	"\tend",
	"\tFOVGui.Visible = false",
	"\ttweenFOVToDefault()",
	"end)",
	"",
}, "\n")

local HeartScript = table.concat({
	"-- Place-fixed HeartCoil (CoilBoostEvent + live Humanoid).",
	'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
	'local Players = game:GetService("Players")',
	'local CoilBoostEvent = ReplicatedStorage:WaitForChild("CoilBoostEvent", 10)',
	"",
	"local player = Players.LocalPlayer",
	"local tool = script.Parent",
	"",
	"local normalSpeed = 16",
	"local boostedSpeed = 50",
	"",
	"local function getHumanoid()",
	"\tlocal character = player.Character",
	"\tif not character then",
	"\t\treturn nil",
	"\tend",
	'\treturn character:FindFirstChildOfClass("Humanoid")',
	"end",
	"",
	"tool.Equipped:Connect(function()",
	"\tlocal humanoid = getHumanoid()",
	"\tif humanoid then",
	"\t\thumanoid.WalkSpeed = boostedSpeed",
	"\tend",
	"\tif CoilBoostEvent then",
	"\t\tCoilBoostEvent:FireServer(boostedSpeed)",
	"\tend",
	"end)",
	"",
	"tool.Unequipped:Connect(function()",
	"\tlocal humanoid = getHumanoid()",
	"\tif humanoid then",
	"\t\thumanoid.WalkSpeed = normalSpeed",
	"\tend",
	"\tif CoilBoostEvent then",
	"\t\tCoilBoostEvent:FireServer(normalSpeed)",
	"\tend",
	"end)",
	"",
}, "\n")

local toolsRoot = game:GetService("ServerStorage"):FindFirstChild("Tools")
local patched = { dual = 0, selfie = 0, heart = 0 }
if toolsRoot then
	for _, roleFolder in ipairs(toolsRoot:GetChildren()) do
		if roleFolder:IsA("Folder") then
			local dual = roleFolder:FindFirstChild("DualGlowStick")
			if dual then
				local s = dual:FindFirstChildWhichIsA("Script")
				if s then
					s.Source = DualScript
					patched.dual += 1
				end
			end
			local selfie = roleFolder:FindFirstChild("Selfie")
			if selfie then
				local ls = selfie:FindFirstChildWhichIsA("LocalScript")
				if ls then
					ls.Source = SelfieScript
					patched.selfie += 1
				end
			end
			local heart = roleFolder:FindFirstChild("HeartCoil")
			if heart then
				local ls = heart:FindFirstChildWhichIsA("LocalScript")
				if ls then
					ls.Source = HeartScript
					patched.heart += 1
				end
			end
		end
	end
end

note(("patched DualGlowStick x%d Selfie x%d HeartCoil x%d"):format(patched.dual, patched.selfie, patched.heart))
return results
