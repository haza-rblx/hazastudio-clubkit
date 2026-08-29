--!nocheck
--[[
  CinematicLoading — place pack (NOT Club Kit engine). LocalScript in ReplicatedFirst with a
  child ScreenGui `LoadingUI` (from CinematicLoadingUI.rbxm).

  Ported from the pre-kit Hierapolis loading screen. Differences from the original:
    * gated on ClubKitConfig.Features.LoadingScreen == false (kit loading screen owns boot otherwise)
    * the bar follows the kit's real client boot (Players.LocalPlayer attributes written by
      Main.client: ClubKitBootProgress / ClubKitBootSettled) instead of a fixed 16 s timer
    * sets ClubKitExternalLoading = true while up, so the kit holds enterGameplay (join-community
      prompt, join greetings) until the player has picked a graphics preset
    * CoreGui is restored per type to what it was before, not blanket-enabled (the kit hotbar
      keeps Backpack off)
    * skips itself on the kit's AFK auto-rejoin (same as the kit loading screen)
  Camera: needs Workspace.CameraParts/Camera1..Camera3 with BaseParts named Cam1.. (sorted by name).
]]

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local MaterialService = game:GetService("MaterialService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- =============================================================================
-- PLACE SETTINGS (edit freely — this file is place-owned)
-- =============================================================================
local SETTINGS = {
	PresentedBy = "Presented by COMA Studio",
	WelcomeMessage = "Welcome to COMA Studio",
	LoadingMusicId = "rbxassetid://130897186549906",
	MusicVolume = 0.6,
	PresentedByDuration = 5, -- seconds before the bar appears
	TipDuration = 3,
	-- Bar pacing: climbs at most this many % per tick while waiting for the kit.
	BarTickSeconds = 0.12,
	-- Time-based floor so the bar never looks stuck while the kit boots (reaches this % by MaxWait).
	BarTimeFloorPercent = 88,
	-- Give up waiting for the kit after this many seconds (bar completes anyway).
	MaxWait = 60,
	SkipAtPercent = 45,
	-- Brand logo shown above the loading text when the template GameIcon is blank.
	-- The template's GameIcon frame is 0.7 x 0.7 of the screen (invisible in the old place
	-- because it had no image), so the logo is resized here. false = keep it hidden.
	ShowLogo = false, -- Hierapolis: no logo on the loading screen (owner call 2026-08-29)
	LogoScale = 0.16, -- fraction of screen height, square (only when ShowLogo = true)
	Tips = {
		"Join our community server COMA Studio!",
	},
	Story = {
		"<i>Founded in 1473 beneath the frozen mountains</i>",
		"<i>Hierapolis was built by the Order of Solaris as a city of art, celebration, and eternal light.</i>",
		{
			"<i>Thought centuries passed in silence beneath the ice...</i>\n<i>it's ryhthm never faded</i>",
			"<b>Today.. Hierapolis awakens once again</b>\n<b>Where History Dances Again.</b>",
		},
	},
	AncientGold = Color3.fromRGB(235, 197, 117),
	CleanWhite = Color3.fromRGB(245, 245, 245),
}

-- Attribute names are read from the kit's Config.ClientBoot when available (fallback = 2.10-era names).
local ATTR = {
	progress = "ClubKitBootProgress",
	settled = "ClubKitBootSettled",
	external = "ClubKitExternalLoading",
}

local Plr = Players.LocalPlayer

-- =============================================================================
-- GATE — only run when the kit loading screen is off
-- =============================================================================
local function readKitConfig()
	local folder = ReplicatedStorage:WaitForChild("Hazastudio_ClubKitConfig", 30)
	local mod = folder and folder:WaitForChild("ClubKitConfig", 30)
	if not (mod and mod:IsA("ModuleScript")) then
		return nil
	end
	local ok, cfg = pcall(require, mod)
	return if ok and type(cfg) == "table" then cfg else nil
end

local kitConfig = readKitConfig()
if kitConfig and type(kitConfig.Features) == "table" and kitConfig.Features.LoadingScreen ~= false then
	warn("[CinematicLoading] ClubKitConfig.Features.LoadingScreen is not false — kit loading screen owns boot; pack disabled")
	return
end

do
	-- Kit engine constants (attribute names) + AFK rejoin skip, both optional.
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local shared = kit and kit:FindFirstChild("Shared")
	local constants = shared and shared:FindFirstChild("Constants")
	local configModule = constants and constants:FindFirstChild("Config")
	if configModule then
		local ok, Config = pcall(require, configModule)
		local boot = ok and type(Config) == "table" and Config.ClientBoot or nil
		if type(boot) == "table" then
			ATTR.progress = boot.BOOT_PROGRESS_ATTRIBUTE or ATTR.progress
			ATTR.settled = boot.BOOT_SETTLED_ATTRIBUTE or ATTR.settled
			ATTR.external = boot.EXTERNAL_LOADING_ATTRIBUTE or ATTR.external
		end
	end
	local session = shared and shared:FindFirstChild("Session")
	local rejoinModule = session and session:FindFirstChild("RejoinMode")
	if rejoinModule then
		local ok, RejoinMode = pcall(require, rejoinModule)
		if ok and RejoinMode and type(RejoinMode.isAfkRejoin) == "function" then
			local okCheck, isRejoin = pcall(RejoinMode.isAfkRejoin)
			if okCheck and isRejoin == true then
				ReplicatedFirst:RemoveDefaultLoadingScreen()
				return
			end
		end
	end
end

-- Hold the kit's gameplay entry until the player is through the graphics menu.
Plr:SetAttribute(ATTR.external, true)

local function releaseKit()
	Plr:SetAttribute(ATTR.external, false)
end

-- =============================================================================
-- CHARACTER / UI SETUP
-- =============================================================================
local function GetSafeCharacter()
	local char = Plr.Character or Plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 4)
	local hum = char:WaitForChild("Humanoid", 4)
	if not hrp or not hum then
		char = Plr.CharacterAdded:Wait()
		hrp = char:WaitForChild("HumanoidRootPart", 8)
		hum = char:WaitForChild("Humanoid", 8)
	end
	return char, hum, hrp
end

local InitialChar, InitialHum, InitialHrp = GetSafeCharacter()
if InitialHrp then
	InitialHrp.Anchored = true
end

Plr:SetAttribute("IsLoading", true)
Plr:SetAttribute("LoadingFinished", false)

local LoadingUI = script:WaitForChild("LoadingUI"):Clone()
LoadingUI.ResetOnSpawn = false
local MainFrame = LoadingUI:WaitForChild("MainFrame")

MainFrame.BackgroundTransparency = 1
if MainFrame:IsA("ImageLabel") then
	MainFrame.ImageTransparency = 1
end
local BGFrame = MainFrame:FindFirstChild("BGFrame")
if BGFrame then
	BGFrame.BackgroundTransparency = 1
	if BGFrame:IsA("ImageLabel") then
		BGFrame.ImageTransparency = 1
	end
end

local Circle = MainFrame:WaitForChild("Circle")
local LoadingLabel = MainFrame:WaitForChild("LoadingText")
local GameIcon = MainFrame:WaitForChild("GameIcon")
local GraphFrame = MainFrame:WaitForChild("Graphics")
local HighBtn = GraphFrame:WaitForChild("HIGH")
local LowBtn = GraphFrame:WaitForChild("MEDIUM")
local PotatoBtn = GraphFrame:WaitForChild("POTATO")
local SkipFrame = MainFrame:WaitForChild("SkipFrame")
local SkipBtn = SkipFrame:WaitForChild("SkipButton")
local Bar = MainFrame:WaitForChild("Bar")
local BackBar = Bar:WaitForChild("BackBar")
local Percent = MainFrame:WaitForChild("Percent")
local Tip = MainFrame:WaitForChild("Tip")
local StoryText = MainFrame:WaitForChild("StoryText")

local ClickSFX = LoadingUI:WaitForChild("Click")
local HoverSFX = LoadingUI:WaitForChild("Hover")

-- Brand logo from the kit config when the template icon is blank — resized, because the
-- template frame is screen-sized.
if GameIcon:IsA("ImageLabel") then
	local logo = kitConfig and type(kitConfig.Branding) == "table" and kitConfig.Branding.LogoImage or nil
	if GameIcon.Image ~= "" then
		logo = GameIcon.Image -- template supplied its own
	end
	if SETTINGS.ShowLogo and type(logo) == "string" and logo ~= "" then
		GameIcon.Image = logo
		GameIcon.ScaleType = Enum.ScaleType.Fit
		GameIcon.BackgroundTransparency = 1
		GameIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		GameIcon.Size = UDim2.fromScale(SETTINGS.LogoScale, SETTINGS.LogoScale)
		GameIcon.Position = UDim2.fromScale(0.5, 0.36)
		local ratio = GameIcon:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.DominantAxis = Enum.DominantAxis.Height
		ratio.Parent = GameIcon
	else
		-- No logo at all on this screen (ShowLogo = false, or nothing to show).
		GameIcon.Image = ""
		GameIcon.Visible = false
	end
end

local BGMusic = Instance.new("Sound")
BGMusic.Name = "LoadingMusic"
BGMusic.SoundId = SETTINGS.LoadingMusicId
BGMusic.Volume = SETTINGS.MusicVolume
BGMusic.Looped = true
BGMusic.Parent = LoadingUI
-- Played once LoadingUI is inside PlayerGui (a Sound outside the DataModel does not start).

local GraphSelected = false
local StillLoading = true
local CameraLocked = false
local TipShown = true
local Skipped = false

local CamTracker = Instance.new("CFrameValue")
local ActiveCamTween = nil

RunService:BindToRenderStep("LoadingCameraLock", Enum.RenderPriority.Camera.Value + 1, function()
	if CameraLocked then
		local cam = Workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CamTracker.Value
	end
end)

local Vignette = Instance.new("Frame")
Vignette.Name = "CinematicVignette"
Vignette.Size = UDim2.new(1, 0, 0.4, 0)
Vignette.Position = UDim2.new(0, 0, 0.6, 0)
Vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Vignette.BorderSizePixel = 0
Vignette.BackgroundTransparency = 1
Vignette.ZIndex = 0
Vignette.Parent = MainFrame

local VignetteGradient = Instance.new("UIGradient")
VignetteGradient.Rotation = 90
VignetteGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0.15),
})
VignetteGradient.Parent = Vignette

ReplicatedFirst:RemoveDefaultLoadingScreen()
SkipFrame.Visible = false
GraphFrame.Visible = false
Bar.Visible = false

StoryText.Text = ""
StoryText.TextTransparency = 1
StoryText.Visible = false
StoryText.RichText = true
StoryText.Font = Enum.Font.Garamond
StoryText.TextColor3 = SETTINGS.AncientGold
StoryText.TextWrapped = true

LoadingUI.DisplayOrder = 99999
LoadingUI.IgnoreGuiInset = true
LoadingUI.Parent = Plr:WaitForChild("PlayerGui")
BGMusic:Play()
-- Kit music stays muted while ClubKitExternalLoading is true (MusicPlayerController honours it),
-- so the loading track is the only thing playing; it fades out in FinishLoadingWithPan.

-- CoreGui: remember per-type state so we restore exactly what was there (kit hotbar owns Backpack).
local coreGuiBefore = {}
for _, coreGuiType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
	if coreGuiType ~= Enum.CoreGuiType.All then
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(coreGuiType)
		end)
		coreGuiBefore[coreGuiType] = if ok then enabled else true
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end)
	end
end

-- Every ScreenGui stays disabled until a preset is picked — including ones the kit enables
-- mid-boot (topbar pills, hotbar), which a ChildAdded-only hook would miss. We watch Enabled on
-- each gui and re-hide; `hiding` guards our own writes from re-triggering.
local hiddenGuis = {}
local hiddenSet = {}
local guiConns = {}
local hiding = true

local function hideGui(gui)
	if not gui:IsA("ScreenGui") or gui == LoadingUI then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
		if not hiddenSet[gui] then
			hiddenSet[gui] = true
			table.insert(hiddenGuis, gui)
		end
	end
	if not guiConns[gui] then
		guiConns[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if hiding and gui.Enabled then
				gui.Enabled = false
				if not hiddenSet[gui] then
					hiddenSet[gui] = true
					table.insert(hiddenGuis, gui)
				end
			end
		end)
	end
end

for _, gui in ipairs(Plr.PlayerGui:GetChildren()) do
	hideGui(gui)
end
local guiHideConn = Plr.PlayerGui.ChildAdded:Connect(hideGui)

-- =============================================================================
-- CINEMATIC CAMERA
-- =============================================================================
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local CameraFolder = Workspace:WaitForChild("CameraParts", 10)
	CameraLocked = true

	local function getSortedCams(folderName)
		local cams = {}
		local folder = CameraFolder and CameraFolder:FindFirstChild(folderName)
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart") then
					table.insert(cams, part)
				end
			end
			table.sort(cams, function(a, b)
				return a.Name < b.Name
			end)
		end
		return cams
	end

	local function PlayPhase(folderName, textIndex, isLastPhase)
		if not CameraLocked or GraphSelected then
			return
		end

		local cams = getSortedCams(folderName)
		local textData = SETTINGS.Story[textIndex]

		TweenService:Create(StoryText, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.5)
		if not CameraLocked or GraphSelected then
			return
		end

		StoryText.TextSize = (textIndex == 3) and 45 or 24
		StoryText.Text = if type(textData) == "string" then textData else textData[1]
		StoryText.Visible = true
		TweenService:Create(StoryText, TweenInfo.new(1), { TextTransparency = 0 }):Play()

		if #cams > 0 then
			CamTracker.Value = cams[1].CFrame

			if isLastPhase then
				if #cams > 1 then
					ActiveCamTween = TweenService:Create(
						CamTracker,
						TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ Value = cams[2].CFrame }
					)
					ActiveCamTween:Play()

					task.wait(2.5)
					if CameraLocked and not GraphSelected then
						TweenService:Create(StoryText, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
						task.wait(0.5)
					end
					if CameraLocked and not GraphSelected and type(textData) == "table" then
						StoryText.Text = textData[2]
						TweenService:Create(StoryText, TweenInfo.new(1), { TextTransparency = 0 }):Play()
					end
					if ActiveCamTween.PlaybackState == Enum.PlaybackState.Playing then
						ActiveCamTween.Completed:Wait()
					end
				end

				local _, _, currentHrp = GetSafeCharacter()
				local targetCF
				if currentHrp then
					local focusPos = currentHrp.Position + Vector3.new(0, 1.5, 0)
					local camOffset = currentHrp.CFrame.LookVector * -12 + Vector3.new(0, 2.5, 0)
					targetCF = CFrame.lookAt(focusPos + camOffset, focusPos)
				else
					local lastCam = cams[#cams] or cams[1]
					targetCF = lastCam.CFrame * CFrame.new(0, 0, -20)
				end

				if CameraLocked and not GraphSelected then
					ActiveCamTween = TweenService:Create(
						CamTracker,
						TweenInfo.new(15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ Value = targetCF }
					)
					ActiveCamTween:Play()
					ActiveCamTween.Completed:Wait()
				end
			else
				for i = 2, #cams do
					if not CameraLocked or GraphSelected then
						break
					end
					ActiveCamTween = TweenService:Create(
						CamTracker,
						TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ Value = cams[i].CFrame }
					)
					ActiveCamTween:Play()
					ActiveCamTween.Completed:Wait()
				end
			end
		else
			task.wait(2)
		end
	end

	while CameraLocked and LoadingUI.Parent do
		if GraphSelected then
			break
		end
		PlayPhase("Camera1", 1, false)
		if GraphSelected then
			break
		end
		PlayPhase("Camera2", 2, false)
		if GraphSelected then
			break
		end
		PlayPhase("Camera3", 3, true)
	end
end)

-- =============================================================================
-- GRAPHICS MENU
-- =============================================================================
local function HoverEffect(Btn)
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local padding = Btn:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding", Btn)
	padding.PaddingLeft = UDim.new(0, 10)

	Btn.MouseEnter:Connect(function()
		HoverSFX:Play()
		TweenService:Create(Btn, tweenInfo, { TextColor3 = SETTINGS.CleanWhite, TextTransparency = 0 }):Play()
		TweenService:Create(padding, tweenInfo, { PaddingLeft = UDim.new(0, 25) }):Play()
	end)
	Btn.MouseLeave:Connect(function()
		TweenService:Create(Btn, tweenInfo, { TextColor3 = SETTINGS.AncientGold, TextTransparency = 0.4 }):Play()
		TweenService:Create(padding, tweenInfo, { PaddingLeft = UDim.new(0, 10) }):Play()
	end)
end

HoverEffect(HighBtn)
HoverEffect(LowBtn)
HoverEffect(PotatoBtn)

local function FinishLoadingWithPan(graphicSetting)
	if GraphSelected then
		return
	end
	GraphSelected = true

	if ActiveCamTween then
		ActiveCamTween:Cancel()
	end

	if graphicSetting == "High" then
		Lighting.GlobalShadows = true
	elseif graphicSetting == "Medium" then
		Lighting.GlobalShadows = false
	elseif graphicSetting == "Potato" then
		MaterialService:SetBaseMaterialOverride(Enum.Material.SmoothPlastic, "None")
		Lighting.GlobalShadows = false
		Lighting.ShadowSoftness = 0
		for _, part in pairs(Workspace:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CastShadow = false
			end
		end
	end

	local FadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(StoryText, FadeOut, { TextTransparency = 1 }):Play()
	TweenService:Create(Vignette, FadeOut, { BackgroundTransparency = 1 }):Play()
	for _, c in ipairs(GraphFrame:GetDescendants()) do
		if c:IsA("TextLabel") or c:IsA("TextButton") then
			TweenService:Create(c, FadeOut, { TextTransparency = 1 }):Play()
		end
	end
	TweenService:Create(BGMusic, TweenInfo.new(1.5), { Volume = 0 }):Play()
	task.wait(0.8)

	local _, currentHum, currentHrp = GetSafeCharacter()
	local cam = Workspace.CurrentCamera

	if currentHrp then
		local focusPos = currentHrp.Position + Vector3.new(0, 1.5, 0)
		local camOffset = currentHrp.CFrame.LookVector * -12 + Vector3.new(0, 2.5, 0)
		local targetCFrame = CFrame.lookAt(focusPos + camOffset, focusPos)
		local panTween = TweenService:Create(
			CamTracker,
			TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Value = targetCFrame }
		)
		panTween:Play()
		panTween.Completed:Wait()
	end

	CameraLocked = false
	RunService:UnbindFromRenderStep("LoadingCameraLock")

	cam.CameraType = Enum.CameraType.Custom
	if currentHum then
		cam.CameraSubject = currentHum
	end

	hiding = false
	if guiHideConn then
		guiHideConn:Disconnect()
	end
	for _, conn in pairs(guiConns) do
		conn:Disconnect()
	end
	for coreGuiType, enabled in pairs(coreGuiBefore) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
		end)
	end
	for _, gui in ipairs(hiddenGuis) do
		if gui and gui.Parent then
			gui.Enabled = true
		end
	end

	if currentHrp then
		currentHrp.Anchored = false
	end
	if InitialHrp and InitialHrp.Parent then
		InitialHrp.Anchored = false
	end

	Plr:SetAttribute("IsLoading", false)
	Plr:SetAttribute("LoadingFinished", true)
	LoadingUI:Destroy()
	-- Now let the kit fire its post-loading flow (join prompt, greetings).
	releaseKit()
end

HighBtn.MouseButton1Click:Connect(function()
	ClickSFX:Play()
	FinishLoadingWithPan("High")
end)
LowBtn.MouseButton1Click:Connect(function()
	ClickSFX:Play()
	FinishLoadingWithPan("Medium")
end)
PotatoBtn.MouseButton1Click:Connect(function()
	ClickSFX:Play()
	FinishLoadingWithPan("Potato")
end)

local function StartCinematicMenu()
	local FadeIn = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	TweenService:Create(Vignette, FadeIn, { BackgroundTransparency = 0 }):Play()

	GraphFrame.Visible = true
	GraphFrame.BackgroundTransparency = 1
	GraphFrame.AnchorPoint = Vector2.new(0, 0.5)
	GraphFrame.Position = UDim2.new(0.04, 0, 0.75, 0)

	local uiScale = GraphFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	uiScale.Parent = GraphFrame
	uiScale.Scale = 0.85
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local listLayout = GraphFrame:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", GraphFrame)
	listLayout.Padding = UDim.new(0, 15)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	HighBtn.Text = "High Quality"
	LowBtn.Text = "Balanced"
	PotatoBtn.Text = "Performance"

	for _, child in ipairs(GraphFrame:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child.Font = Enum.Font.Garamond
			child.TextColor3 = SETTINGS.AncientGold
			child.TextSize = 22
			child.TextTransparency = 1
			child.TextXAlignment = Enum.TextXAlignment.Left
			TweenService:Create(child, FadeIn, { TextTransparency = 0.4 }):Play()
		end
		if child:IsA("Frame") then
			child.BackgroundTransparency = 1
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			child.BackgroundTransparency = 1
			child.ImageTransparency = 1
		end
		if child:IsA("UIStroke") then
			child.Transparency = 1
		end
	end
end

local function LastSequence()
	if not StillLoading then
		return
	end
	StillLoading = false
	TipShown = false

	local FadeOut = TweenInfo.new(0.5)
	TweenService:Create(Bar, FadeOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(BackBar, FadeOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(Percent, FadeOut, { TextTransparency = 1 }):Play()
	TweenService:Create(Tip, FadeOut, { TextTransparency = 1 }):Play()
	TweenService:Create(Circle, FadeOut, { ImageTransparency = 1 }):Play()
	TweenService:Create(SkipFrame, FadeOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(SkipBtn, FadeOut, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	if BGFrame then
		TweenService:Create(BGFrame, FadeOut, { BackgroundTransparency = 1 }):Play()
	end
	local skipStroke = SkipFrame:FindFirstChildOfClass("UIStroke")
	if skipStroke then
		TweenService:Create(skipStroke, FadeOut, { Transparency = 1 }):Play()
	end
	task.wait(0.5)

	LoadingLabel.Text = SETTINGS.WelcomeMessage
	TweenService:Create(LoadingLabel, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.wait(2.5)
	TweenService:Create(LoadingLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	TweenService:Create(GameIcon, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
	task.wait(0.5)

	StartCinematicMenu()
end

-- Skip = jump to the welcome + graphics menu; only honoured once the kit has settled
-- (or the wait timed out), otherwise the kit UI would still be booting under the menu.
local wantSkip = false
SkipBtn.MouseButton1Click:Connect(function()
	if Skipped then
		return
	end
	Skipped = true
	wantSkip = true
	ClickSFX:Play()
end)

task.spawn(function()
	while LoadingUI.Parent do
		Circle.Rotation = 0
		TweenService:Create(Circle, TweenInfo.new(1, Enum.EasingStyle.Linear), { Rotation = -360 }):Play()
		task.wait(1)
	end
end)

task.spawn(function()
	task.wait(SETTINGS.PresentedByDuration + 1)
	while TipShown do
		for _, tipMessage in ipairs(SETTINGS.Tips) do
			if not TipShown then
				break
			end
			TweenService:Create(Tip, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			if not TipShown then
				break
			end
			Tip.Text = tipMessage
			TweenService:Create(Tip, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
			task.wait(SETTINGS.TipDuration)
		end
	end
end)

-- =============================================================================
-- PROGRESS — follows the kit's client boot
-- =============================================================================
LoadingLabel.Text = SETTINGS.PresentedBy
LoadingLabel.TextTransparency = 0

task.wait(SETTINGS.PresentedByDuration)
TweenService:Create(LoadingLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
task.wait(0.5)

Bar.Visible = true
Bar.BackgroundTransparency = 1
BackBar.BackgroundTransparency = 1
Percent.TextTransparency = 1
Tip.TextTransparency = 1
BackBar.Size = UDim2.new(0, 0, 1, 0)
Percent.Text = "0%"

local tweenInfo = TweenInfo.new(0.5)
TweenService:Create(Bar, tweenInfo, { BackgroundTransparency = 0.6 }):Play()
TweenService:Create(BackBar, tweenInfo, { BackgroundTransparency = 0 }):Play()
TweenService:Create(Percent, tweenInfo, { TextTransparency = 0 }):Play()
Tip.Text = SETTINGS.Tips[1] or ""
TweenService:Create(Tip, tweenInfo, { TextTransparency = 0 }):Play()

local function kitSettled()
	return Plr:GetAttribute(ATTR.settled) == true
end

local function kitProgressPercent()
	local p = tonumber(Plr:GetAttribute(ATTR.progress)) or 0
	return math.clamp(p, 0, 1) * 100
end

local function showPercent(percent)
	Percent.Text = percent .. "%"
	TweenService:Create(BackBar, TweenInfo.new(SETTINGS.BarTickSeconds), { Size = UDim2.new(percent / 100, 0, 1, 0) }):Play()
end

local shown = 0
local skipButtonShown = false
local startedAt = os.clock()

while StillLoading do
	local elapsed = os.clock() - startedAt
	local settled = kitSettled() or elapsed >= SETTINGS.MaxWait
	local timeFloor = math.min(SETTINGS.BarTimeFloorPercent, (elapsed / SETTINGS.MaxWait) * SETTINGS.BarTimeFloorPercent)
	-- Kit progress maps to 0..95; the last 5% is reserved for "settled".
	local target = math.max(timeFloor, kitProgressPercent() * 0.95)
	if settled then
		target = 100
	end
	if shown < target then
		shown = math.min(shown + 1, math.floor(target))
		showPercent(shown)
	end

	if shown >= SETTINGS.SkipAtPercent and not skipButtonShown then
		skipButtonShown = true
		SkipFrame.Visible = true
		SkipFrame.BackgroundTransparency = 1
		TweenService:Create(SkipFrame, TweenInfo.new(0.5), { BackgroundTransparency = 0.9 }):Play()
	end

	if settled and (shown >= 100 or wantSkip) then
		break
	end
	task.wait(SETTINGS.BarTickSeconds)
end

if StillLoading then
	showPercent(100)
	task.wait(1)
	LastSequence()
end
