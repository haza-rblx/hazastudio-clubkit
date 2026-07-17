--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Parent.Constants.Config)
local LoadingCinematicCamera = require(script.Parent.Parent.Utils.LoadingCinematicCamera)

local LoadingScreenUI = {}
LoadingScreenUI.__index = LoadingScreenUI

local sharedInstance: any? = nil
local LoadingConfig = Config.Loading

local COLOR_FADE_IN_TWEEN =
	TweenInfo.new(LoadingConfig.COLOR_FADE_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLOR_FADE_OUT_TWEEN =
	TweenInfo.new(LoadingConfig.COLOR_FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEFAULT_MINIMUM_DURATION = LoadingConfig.MINIMUM_DURATION
local FINAL_HOLD_DURATION = LoadingConfig.FINAL_HOLD_DURATION
local WATCHDOG_BUFFER = LoadingConfig.WATCHDOG_BUFFER
local PROGRESS_SMOOTH_SPEED = LoadingConfig.PROGRESS_SMOOTH_SPEED
local LOADING_COLOR_CORRECTION_NAME = "LoadingScreenColorCorrection"
local LOADING_BLUR_NAME = "LoadingScreenBlur"
local OVERHEAD_GUI_NAME = Config.Template.TEMPLATE_NAME
local INTRO_FRAME_NAME = "HazastudioLoadingIntro"

local NEUTRAL_COLOR = {
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
	TintColor = Color3.fromRGB(255, 255, 255),
}

-- Pitch black: applied instantly at the very start of loading
local BLACKOUT_COLOR = {
	Brightness = -1,
	Contrast = 0.4,
	Saturation = -1,
	TintColor = Color3.fromRGB(0, 0, 0),
}

-- Cinematic look during loading (tweened into from BLACKOUT)
local LOADING_COLOR = {
	Brightness = -0.2,
	Contrast = -0.3,
	Saturation = -1,
	TintColor = Color3.fromRGB(255, 255, 255),
}

-- Multilingual greetings — non-Latin scripts prioritized (Japanese, Korean, Chinese, Arabic…)
local DEFAULT_GREETINGS = {
	"こんにちは", -- Japanese: Konnichiwa
	"안녕", -- Korean: Annyeong
	"你好", -- Chinese: Nǐ hǎo
	"أهلاً", -- Arabic: Ahlan
	"नमस्ते", -- Hindi: Namaste
	"สวัสดี", -- Thai: Sawadee
	"ようこそ", -- Japanese: Welcome
	"어서와", -- Korean: Welcome
	"欢迎", -- Chinese: Huānyíng
	"مرحبا", -- Arabic: Marhaba
	"Привет", -- Russian: Privet
	"Γεια σου", -- Greek: Yia sou
	"どうも", -- Japanese: Hey / Thanks
	"반가워", -- Korean: Nice to meet you
	"嗨", -- Chinese: Hāi
	"Halo", -- Indonesian
	"Hello", -- English
	"Bienvenido", -- Spanish
}

local DEFAULT_TIPS = {
	"The best nights are never planned — they just happen when the right people, the right music, and the right energy collide.",
	"Real clubbers don't watch the clock. When the bassline hits right, time doesn't exist.",
	"The dancefloor is the world's oldest social network. No followers needed — just show up and move.",
	"House, techno, afrobeats, R&B — every genre has its own culture. Respect the vibe of the room you're in.",
	"The best outfit for a night out is confidence. Everything else is just accessories.",
	"In a good club, strangers become friends between the first and second drop.",
	"DJs don't just play music — they read the crowd, feel the energy, and build a journey that can last all night.",
	"Real nightlife etiquette: don't cut through the dancefloor, tip the bartender, and never kill someone else's vibe.",
	"The pre-game is part of the experience. Good energy starts before you even walk through the door.",
	"Ibiza, Berlin, Tokyo, Lagos — every city has its own night scene, its own sound, its own rules. The world raves differently.",
	"A great night out isn't about how late you stayed — it's about the moments you'll still be talking about next week.",
	"The golden rule of the dancefloor: if the music moves you, just dance. Nobody's judging — they're too busy feeling it too.",
	"Neon lights, smoke machines, and a bassline that you feel in your chest — some experiences are simply better lived than explained.",
	"The culture of nightlife is built on freedom — freedom to move, to express, to be whoever you want to be until sunrise.",
}

local coreUiVisibilityToken = 0

type Refs = {
	root: ScreenGui,
	contentWrapper: GuiObject?,
	content: GuiObject?,
	titleLabel: TextLabel,
	tipsLabel: TextLabel,
	loadingBarWrapper: GuiObject,
	barFill: GuiObject,
	loadingMark: GuiObject,
	progressLabel: TextLabel?,
}

type GuiVisibilityState = {
	playerGui: PlayerGui,
	screenGuiStates: { [ScreenGui]: boolean },
	screenGuiConnections: { [ScreenGui]: RBXScriptConnection },
	playerGuiChildAddedConnection: RBXScriptConnection?,
	visible: boolean,
}

type Options = {
	greetings: { string }?,
	tips: { string }?,
	minimumDuration: number?,
}

local function clamp(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function formatGreetingLine(template: string, playerName: string): string
	if string.find(template, "%%s") then
		return string.format(template, playerName)
	end
	return string.format("%s, %s", template, playerName)
end

local function pick(list: { string }, rng: Random): string
	if #list == 0 then
		return ""
	end
	return list[rng:NextInteger(1, #list)]
end

local function isProjectOverheadGui(gui: BillboardGui): boolean
	local variant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
	local variantName = if type(variant.templateName) == "string" then variant.templateName else OVERHEAD_GUI_NAME
	local wrapperName = if type(variant.wrapperName) == "string" then variant.wrapperName else "OverheadGUIMainWrapper"
	local hasSpecificWrapper = wrapperName ~= "Frame" and gui:FindFirstChild(wrapperName, true) ~= nil
	return gui.Name == OVERHEAD_GUI_NAME
		or gui.Name == variantName
		or hasSpecificWrapper
		or gui:FindFirstChild("OverheadGUIMainWrapper", true) ~= nil
end

local function isOverlayBlocking(self: any): boolean
	return self._available == true
		and self._dismissed ~= true
		and (
			self._started == true
			or self._bootFinished == true
			or self._finishRequested == true
			or self._waitingForClick == true
			or self._dismissing == true
		)
end

local function createColorCorrection(): ColorCorrectionEffect
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.Name == LOADING_COLOR_CORRECTION_NAME then
			pcall(function()
				child:Destroy()
			end)
		end
	end

	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = LOADING_COLOR_CORRECTION_NAME
	effect.Parent = Lighting
	return effect
end

local function createLoadingBlur(size: number): BlurEffect
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.Name == LOADING_BLUR_NAME then
			pcall(function()
				child:Destroy()
			end)
		end
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = LOADING_BLUR_NAME
	blur.Size = size
	blur.Enabled = true
	blur.Parent = Lighting
	return blur
end

local function resolveLogoImage(): string
	local branding = (Config :: any).Branding
	if type(branding) == "table" then
		local logo = branding.LOGO_IMAGE or branding.DEFAULT_LOGO_IMAGE
		if type(logo) == "string" and logo ~= "" then
			return logo
		end
	end
	return "rbxassetid://79426970537296"
end

local function findDescendant(parent: Instance, name: string): Instance?
	local direct = parent:FindFirstChild(name)
	if direct then
		return direct
	end

	return parent:FindFirstChild(name, true)
end

local function resolveGuiObject(parent: Instance, names: { string }): GuiObject?
	for _, name in ipairs(names) do
		local child = findDescendant(parent, name)
		if child and child:IsA("GuiObject") then
			return child
		end
	end

	return nil
end

local function setCoreUiVisible(visible: boolean)
	for _, coreGuiType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if coreGuiType ~= Enum.CoreGuiType.All then
			if visible and Config.FeatureFlags.HotbarEnabled and coreGuiType == Enum.CoreGuiType.Backpack then
				continue
			end

			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, visible)
			end)
		end
	end

	coreUiVisibilityToken += 1
	local token = coreUiVisibilityToken

	task.spawn(function()
		for _ = 1, LoadingConfig.CORE_TOPBAR_RETRY_COUNT do
			if coreUiVisibilityToken ~= token then
				return
			end

			local ok = pcall(function()
				StarterGui:SetCore("TopbarEnabled", visible)
			end)
			if ok then
				return
			end

			task.wait(LoadingConfig.CORE_TOPBAR_RETRY_INTERVAL)
		end
	end)
end

local function getGuiRestorePriority(guiName: string): number
	local clientBoot = (Config :: any).ClientBoot or {}
	local heavyNames = {
		[Config.Music.GUI_NAME] = true,
		[Config.Admin.GUI_NAME] = true,
		[Config.CommandLibrary.GUI_NAME] = true,
	}
	if heavyNames[guiName] then
		return 3
	end
	for _, name in ipairs(Config.Hotbar.GUI_NAMES) do
		if guiName == name then
			return 1
		end
	end
	if guiName == Config.Backpack.GUI_NAME then
		return 1
	end
	return 2
end

local function suppressScreenGui(state: GuiVisibilityState, root: ScreenGui, gui: ScreenGui)
	if gui == root then
		return
	end

	if state.screenGuiStates[gui] == nil then
		state.screenGuiStates[gui] = gui.Enabled
	end

	local connection = state.screenGuiConnections[gui]
	if not connection then
		state.screenGuiConnections[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not state.visible then
				return
			end

			if gui.Parent and gui ~= root and gui.Enabled then
				gui.Enabled = false
			end
		end)
	end

	gui.Enabled = false
end

local function resolveTextLabel(parent: Instance, names: { string }): TextLabel?
	for _, name in ipairs(names) do
		local child = findDescendant(parent, name)
		if child and child:IsA("TextLabel") then
			return child
		end
	end

	return nil
end

local function describeChildren(parent: Instance): string
	local children = parent:GetChildren()
	if #children == 0 then
		return "(none)"
	end

	local parts = table.create(#children)
	for index, child in ipairs(children) do
		parts[index] = string.format("%s[%s]", child.Name, child.ClassName)
	end

	return table.concat(parts, ", ")
end

local function suppressDefaultPlaceholderLabels(root: ScreenGui)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local label = descendant :: TextLabel
			if label.Name == "Label" and label.Text == "Label" then
				label.Visible = false
				label.Text = ""
			end
		end
	end
end

local function applyOptions(self: any, options: Options?)
	if not options then
		return
	end

	if options.greetings and #options.greetings > 0 then
		self._greetings = options.greetings
	end

	if options.tips and #options.tips > 0 then
		self._tips = options.tips
	end

	if options.minimumDuration and options.minimumDuration > 0 then
		self._minimumDuration = math.max(self._minimumDuration, options.minimumDuration)
	end
end

local function buildController(root: ScreenGui, options: Options?)
	local self = setmetatable({}, LoadingScreenUI)
	self._rng = Random.new()
	self._greetings = if options
			and options.greetings
			and #options.greetings > 0
		then options.greetings
		else DEFAULT_GREETINGS
	self._tips = if options and options.tips and #options.tips > 0 then options.tips else DEFAULT_TIPS
	self._minimumDuration = if options
			and options.minimumDuration
			and options.minimumDuration > 0
		then options.minimumDuration
		else DEFAULT_MINIMUM_DURATION
	self._available = false
	self._started = false
	self._bootFinished = false
	self._dismissed = false
	self._dismissing = false
	self._finishRequested = false
	self._startClock = nil :: number?
	self._progressTarget = 0
	self._progressDisplay = 0
	self._progressRenderConn = nil :: RBXScriptConnection?
	self._playerGuiVisibilityState = nil :: GuiVisibilityState?
	self._cinematicCamera = LoadingCinematicCamera.new()
	self._cinematicStarted = false
	self._introActive = false
	self._introEnded = false
	self._introFrame = nil :: Frame?
	self._introLogo = nil :: ImageLabel?
	self._blurEffect = nil :: BlurEffect?
	self._pendingDisplayName = nil :: string?
	self._colorCorrectionTween = nil :: Tween?
	self._finishDelay = nil :: thread?
	self._fadeDelay = nil :: thread?
	self._watchdogDelay = nil :: thread?
	self._skipPromptDelay = nil :: thread?
	self._greetingCycleThread = nil :: thread?
	self._tipsCycleThread = nil :: thread?
	self._displayName = nil :: string?
	self._overheadConns = {} :: { RBXScriptConnection }
	self._overheadSuppressed = {} :: { { gui: BillboardGui, wasEnabled: boolean, isProjectOverhead: boolean } }
	self._clickConn = nil :: RBXScriptConnection?
	self._skipDuringLoadConn = nil :: RBXScriptConnection?
	self._skipDuringLoadAllowed = false
	self._waitingForClick = false
	self._hiddenParts = {} :: { [BasePart]: number }
	self._playerHideConns = {} :: { RBXScriptConnection }
	self._gameplayEnteredCallbacks = {} :: { () -> () }
	self._gameplayEnteredFired = false
	self._root = root
	self._refs = nil :: Refs?
	self._barBaseSize = nil :: UDim2?
	self._colorCorrection = nil :: ColorCorrectionEffect?

	root.Enabled = false

	local contentWrapper = resolveGuiObject(root, { "ContentWrapper" })
	local content = if contentWrapper then resolveGuiObject(contentWrapper, { "Content" }) else nil
	if not content then
		content = resolveGuiObject(root, { "Content" })
	end

	local titleLabel = if content then resolveTextLabel(content, { "TitleCOntent", "TitleContent" }) else nil
	if not titleLabel then
		titleLabel = resolveTextLabel(root, { "TitleCOntent", "TitleContent" })
	end

	local tipsLabel = if content then resolveTextLabel(content, { "TipsContent" }) else nil
	if not tipsLabel then
		tipsLabel = resolveTextLabel(root, { "TipsContent" })
	end

	local loadingBarWrapper = resolveGuiObject(root, { "LoadingBarWrapper" })
	if not titleLabel or not tipsLabel or not loadingBarWrapper then
		warn(
			string.format(
				"[LoadingScreenUI] Incomplete loading screen tree | rootChildren=%s | contentWrapper=%s | content=%s | title=%s | tips=%s | loadingBar=%s",
				describeChildren(root),
				tostring(contentWrapper ~= nil),
				tostring(content ~= nil),
				tostring(titleLabel ~= nil),
				tostring(tipsLabel ~= nil),
				tostring(loadingBarWrapper ~= nil)
			)
		)
		return self
	end

	local barFill = resolveGuiObject(loadingBarWrapper, { "AdjustableWidth" }) or loadingBarWrapper

	local loadingMark = resolveGuiObject(barFill, { "LoadingMark" })
	if not loadingMark then
		loadingMark = resolveGuiObject(loadingBarWrapper, { "LoadingMark" })
	end
	if not loadingMark then
		loadingMark = resolveGuiObject(root, { "LoadingMark" })
	end
	if not loadingMark then
		loadingMark = barFill
	end
	local resolvedLoadingMark: GuiObject = loadingMark or barFill

	local progressLabel = resolveTextLabel(resolvedLoadingMark, { "LoadingProgresss", "LoadingProgress" })
	if not progressLabel then
		progressLabel = resolveTextLabel(root, { "LoadingProgresss", "LoadingProgress" })
	end
	if progressLabel then
		progressLabel.Visible = false
		progressLabel.Text = ""
	end

	loadingBarWrapper.Visible = true
	barFill.Visible = true
	resolvedLoadingMark.Visible = true

	self._root = root
	root.DisplayOrder = math.max(root.DisplayOrder, 999)
	root.IgnoreGuiInset = true
	root.ResetOnSpawn = false
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._refs = {
		root = root,
		contentWrapper = contentWrapper,
		content = content,
		titleLabel = titleLabel :: TextLabel,
		tipsLabel = tipsLabel :: TextLabel,
		loadingBarWrapper = loadingBarWrapper,
		barFill = barFill,
		loadingMark = resolvedLoadingMark,
		progressLabel = progressLabel :: TextLabel?,
	}
	self._barBaseSize = (barFill :: GuiObject).Size
	self._colorCorrection = createColorCorrection()
	suppressDefaultPlaceholderLabels(root)

	self._available = true
	return self
end

function LoadingScreenUI.attach(root: ScreenGui, options: Options?)
	if sharedInstance and sharedInstance._available then
		if sharedInstance._root == root then
			applyOptions(sharedInstance, options)
			return sharedInstance
		end

		sharedInstance:destroy()
	end

	sharedInstance = buildController(root, options)
	return sharedInstance
end

function LoadingScreenUI.get()
	if sharedInstance and sharedInstance._available then
		return sharedInstance
	end

	return nil
end

function LoadingScreenUI.isAvailable(self)
	return self._available == true
end

function LoadingScreenUI:isFinished()
	return self._dismissed == true
end

function LoadingScreenUI:isBootFinished()
	return self._bootFinished == true
end

function LoadingScreenUI:isBlockingGameplay()
	return isOverlayBlocking(self)
end

function LoadingScreenUI:onGameplayEntered(callback: () -> ())
	if type(callback) ~= "function" then
		return
	end
	if self._gameplayEnteredFired then
		task.defer(callback)
		return
	end
	table.insert(self._gameplayEnteredCallbacks, callback)
end

function LoadingScreenUI:_fireGameplayEntered()
	if self._gameplayEnteredFired then
		return
	end
	self._gameplayEnteredFired = true
	local callbacks = self._gameplayEnteredCallbacks
	self._gameplayEnteredCallbacks = {}
	for _, callback in ipairs(callbacks) do
		task.defer(callback)
	end
end

function LoadingScreenUI:hidePlayerGui(playerGui: PlayerGui)
	if not self._available or not self._refs then
		return
	end

	if
		self._playerGuiVisibilityState
		and self._playerGuiVisibilityState.playerGui == playerGui
		and self._playerGuiVisibilityState.visible
	then
		return
	end

	self:_restorePlayerGuiVisibility()

	local state: GuiVisibilityState = {
		playerGui = playerGui,
		screenGuiStates = {},
		screenGuiConnections = {},
		playerGuiChildAddedConnection = nil,
		visible = true,
	}
	self._playerGuiVisibilityState = state

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			suppressScreenGui(state, self._root, child)
		end
	end

	state.playerGuiChildAddedConnection = playerGui.ChildAdded:Connect(function(child)
		if not self._available then
			return
		end

		if self._playerGuiVisibilityState ~= state or not state.visible then
			return
		end

		if child:IsA("ScreenGui") then
			suppressScreenGui(state, self._root, child)
		end
	end)

	setCoreUiVisible(false)
end

function LoadingScreenUI.new(rootOrOptions: any?, options: Options?)
	if typeof(rootOrOptions) == "Instance" and rootOrOptions:IsA("ScreenGui") then
		return LoadingScreenUI.attach(rootOrOptions, options)
	end

	if type(rootOrOptions) == "table" and options == nil then
		options = rootOrOptions
	end

	if sharedInstance and sharedInstance._available then
		applyOptions(sharedInstance, options)
	end

	return sharedInstance
end

function LoadingScreenUI:_restorePlayerGuiVisibility()
	local state = self._playerGuiVisibilityState
	if not state then
		return
	end

	state.visible = false

	if state.playerGuiChildAddedConnection then
		state.playerGuiChildAddedConnection:Disconnect()
		state.playerGuiChildAddedConnection = nil
	end

	for gui, connection in pairs(state.screenGuiConnections) do
		connection:Disconnect()
		state.screenGuiConnections[gui] = nil
	end

	local restoreEntries = {} :: { { gui: ScreenGui, enabled: boolean, priority: number } }
	for gui, enabled in pairs(state.screenGuiStates) do
		if gui.Parent and gui:IsA("ScreenGui") and gui ~= self._root then
			table.insert(restoreEntries, {
				gui = gui,
				enabled = enabled,
				priority = getGuiRestorePriority(gui.Name),
			})
		end
		state.screenGuiStates[gui] = nil
	end

	self._playerGuiVisibilityState = nil

	table.sort(restoreEntries, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.gui.Name < b.gui.Name
	end)

	local clientBoot = (Config :: any).ClientBoot or {}
	local batchSize = math.max(1, math.floor(tonumber(clientBoot.GUI_RESTORE_BATCH_SIZE) or 3))
	local batchDelay = math.max(0, tonumber(clientBoot.GUI_RESTORE_BATCH_DELAY) or 0)

	task.spawn(function()
		local coreUiEnabled = false
		for index, entry in ipairs(restoreEntries) do
			if Config.Debug and Config.Debug.BOOT_PROFILE_MARKERS == true then
				debug.profilebegin("GuiRestoreBatch")
			end
			pcall(function()
				entry.gui.Enabled = entry.enabled
			end)
			if Config.Debug and Config.Debug.BOOT_PROFILE_MARKERS == true then
				debug.profileend()
			end

			if not coreUiEnabled and index >= batchSize then
				setCoreUiVisible(true)
				coreUiEnabled = true
			end

			if index % batchSize == 0 and index < #restoreEntries then
				if batchDelay > 0 then
					task.wait(batchDelay)
				else
					task.wait()
				end
			end
		end

		if not coreUiEnabled then
			setCoreUiVisible(true)
		end
	end)
end

function LoadingScreenUI:_destroyIntroLayer()
	if self._introFrame then
		pcall(function()
			self._introFrame:Destroy()
		end)
		self._introFrame = nil
		self._introLogo = nil
	end
	if self._blurEffect then
		pcall(function()
			self._blurEffect:Destroy()
		end)
		self._blurEffect = nil
	else
		for _, child in ipairs(Lighting:GetChildren()) do
			if child.Name == LOADING_BLUR_NAME then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end
end

function LoadingScreenUI:_applyIntroBlackout()
	if not self._colorCorrection then
		return
	end
	if self._colorCorrectionTween then
		self._colorCorrectionTween:Cancel()
		self._colorCorrectionTween = nil
	end
	local cc = self._colorCorrection
	cc.Enabled = true
	cc.Brightness = BLACKOUT_COLOR.Brightness
	cc.Contrast = BLACKOUT_COLOR.Contrast
	cc.Saturation = BLACKOUT_COLOR.Saturation
	cc.TintColor = BLACKOUT_COLOR.TintColor
end

function LoadingScreenUI:_updateBlurFromProgress(progress: number)
	if not self._blurEffect then
		return
	end
	local maxBlur = math.max(0, tonumber(LoadingConfig.INTRO_BLUR_SIZE) or 28)
	local clamped = clamp(progress, 0, 1)
	self._blurEffect.Size = maxBlur * (1 - clamped)
	if clamped >= 0.98 then
		self._blurEffect.Enabled = false
	else
		self._blurEffect.Enabled = true
	end
end

function LoadingScreenUI:_beginMainLoadingPhase(displayName: string?)
	if self._cinematicStarted then
		return
	end
	self._cinematicStarted = true

	self:_applyLoadingColor()
	self:_startCinematicCamera()

	local name = displayName or self._pendingDisplayName or self._displayName
	self:_startTextCycles(name)

	task.delay(LoadingConfig.TIPS_FADE_DELAY, function()
		if not self._available or not self._started or not self._refs then
			return
		end
		if self._bootFinished or self._dismissed then
			return
		end
		TweenService:Create(
			self._refs.tipsLabel,
			TweenInfo.new(LoadingConfig.TIPS_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 0 }
		):Play()
	end)
end

function LoadingScreenUI:_endIntro(instant: boolean?)
	if self._introEnded then
		return
	end
	self._introEnded = true
	self._introActive = false

	local fadeDuration = if instant then 0 else math.max(0, tonumber(LoadingConfig.INTRO_FADE_OUT_DURATION) or 0.55)
	local introFrame = self._introFrame
	local introLogo = self._introLogo

	local function afterFade()
		if introFrame and introFrame.Parent then
			pcall(function()
				introFrame:Destroy()
			end)
		end
		if self._introFrame == introFrame then
			self._introFrame = nil
			self._introLogo = nil
		end
		if self._available and self._started and not self._bootFinished and not self._dismissed then
			self:_beginMainLoadingPhase(self._pendingDisplayName)
		end
	end

	if not introFrame or fadeDuration <= 0 then
		afterFade()
		return
	end

	local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweensFinished = 0
	local totalTweens = if introLogo then 2 else 1
	local function onTweenDone()
		tweensFinished += 1
		if tweensFinished >= totalTweens then
			afterFade()
		end
	end

	local frameTween = TweenService:Create(introFrame, fadeInfo, { BackgroundTransparency = 1 })
	frameTween.Completed:Connect(onTweenDone)
	frameTween:Play()
	if introLogo then
		local logoTween = TweenService:Create(introLogo, fadeInfo, {
			ImageTransparency = 1,
			Size = UDim2.fromOffset(
				math.floor((tonumber(LoadingConfig.INTRO_LOGO_SIZE_PX) or 160) * 1.08),
				math.floor((tonumber(LoadingConfig.INTRO_LOGO_SIZE_PX) or 160) * 1.08)
			),
		})
		logoTween.Completed:Connect(onTweenDone)
		logoTween:Play()
	end
end

function LoadingScreenUI:_tryEndIntro()
	if not self._introActive or self._introEnded then
		return
	end
	if LoadingConfig.INTRO_ENABLED == false then
		self:_endIntro(true)
		return
	end

	local minDuration = math.max(0, tonumber(LoadingConfig.INTRO_MIN_DURATION) or 1.25)
	local endProgress = clamp(tonumber(LoadingConfig.INTRO_END_PROGRESS) or 0.28, 0, 1)
	local elapsed = if self._startClock then os.clock() - self._startClock else 0

	if elapsed < minDuration then
		return
	end

	if self._finishRequested or self._progressDisplay >= endProgress then
		self:_endIntro(false)
	end
end

function LoadingScreenUI:_startIntroLayer()
	if not self._refs then
		self:_beginMainLoadingPhase(self._pendingDisplayName)
		return
	end

	if LoadingConfig.INTRO_ENABLED == false then
		self._introEnded = true
		self._introActive = false
		self:_beginMainLoadingPhase(self._pendingDisplayName)
		return
	end

	-- Tear down any leftover intro from a previous session.
	local existing = self._refs.root:FindFirstChild(INTRO_FRAME_NAME)
	if existing then
		pcall(function()
			existing:Destroy()
		end)
	end

	self._introActive = true
	self._introEnded = false

	local maxBlur = math.max(0, tonumber(LoadingConfig.INTRO_BLUR_SIZE) or 28)
	self._blurEffect = createLoadingBlur(maxBlur)

	local frame = Instance.new("Frame")
	frame.Name = INTRO_FRAME_NAME
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0, 0)
	frame.ZIndex = 100
	frame.Parent = self._refs.root
	self._introFrame = frame

	local logoSize = math.max(64, math.floor(tonumber(LoadingConfig.INTRO_LOGO_SIZE_PX) or 160))
	local logo = Instance.new("ImageLabel")
	logo.Name = "LoadingLogo"
	logo.BackgroundTransparency = 1
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	logo.Size = UDim2.fromOffset(math.floor(logoSize * 0.88), math.floor(logoSize * 0.88))
	logo.Image = resolveLogoImage()
	logo.ScaleType = Enum.ScaleType.Fit
	logo.ImageTransparency = 1
	logo.ZIndex = 101
	logo.Parent = frame
	self._introLogo = logo

	-- Keep greetings/tips hidden under the blank intro; bar stays visible above via ZIndex on template.
	self._refs.titleLabel.TextTransparency = 1
	self._refs.tipsLabel.TextTransparency = 1
	-- Keep progress bar readable above the blank intro plate.
	self._refs.loadingBarWrapper.ZIndex = math.max(self._refs.loadingBarWrapper.ZIndex, 110)
	self._refs.barFill.ZIndex = math.max(self._refs.barFill.ZIndex, 111)
	self._refs.loadingMark.ZIndex = math.max(self._refs.loadingMark.ZIndex, 112)

	local fadeIn = math.max(0.05, tonumber(LoadingConfig.INTRO_LOGO_FADE_IN_DURATION) or 0.45)
	local fadeInfo = TweenInfo.new(fadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(logo, fadeInfo, {
		ImageTransparency = 0,
		Size = UDim2.fromOffset(logoSize, logoSize),
	}):Play()

	local minDuration = math.max(0, tonumber(LoadingConfig.INTRO_MIN_DURATION) or 1.25)
	if minDuration > 0 then
		task.delay(minDuration, function()
			if self._available and self._introActive and not self._introEnded then
				self:_tryEndIntro()
			end
		end)
	end
end

function LoadingScreenUI:_startCinematicCamera()
	if not self._cinematicCamera then
		return
	end

	self._cinematicCamera:start()
end

function LoadingScreenUI:_restoreCinematicCamera()
	if not self._cinematicCamera then
		return
	end

	self._cinematicCamera:stop()
end

function LoadingScreenUI:_cancelFinishDelay()
	local threadHandle = self._finishDelay
	self._finishDelay = nil
	if threadHandle and threadHandle ~= coroutine.running() then
		pcall(task.cancel, threadHandle)
	end
end

function LoadingScreenUI:_cancelProgressAnimation()
	if self._progressRenderConn then
		self._progressRenderConn:Disconnect()
		self._progressRenderConn = nil
	end
end

function LoadingScreenUI:_suppressOverheads()
	self._overheadSuppressed = {}
	self._overheadConns = {}

	local function hideGui(gui: BillboardGui)
		-- Avoid double-suppressing the same gui
		for _, entry in ipairs(self._overheadSuppressed) do
			if entry.gui == gui then
				return
			end
		end
		table.insert(self._overheadSuppressed, {
			gui = gui,
			wasEnabled = gui.Enabled,
			isProjectOverhead = isProjectOverheadGui(gui),
		})
		gui.Enabled = false
	end

	local function watchCharacter(character: Model)
		local head = character:FindFirstChild("Head")
		if not head then
			return
		end

		-- Hide any BillboardGui already present (parented to Head)
		for _, desc in ipairs(head:GetDescendants()) do
			if desc:IsA("BillboardGui") then
				hideGui(desc :: BillboardGui)
			end
		end

		-- Watch for BillboardGui added to Head later (server replication arrives after CharacterAdded)
		local conn = head.DescendantAdded:Connect(function(desc)
			if desc:IsA("BillboardGui") and isOverlayBlocking(self) then
				hideGui(desc :: BillboardGui)
			end
		end)
		table.insert(self._overheadConns, conn)
	end

	local function watchPlayer(player: Player)
		if player.Character then
			watchCharacter(player.Character)
		end
		local conn = player.CharacterAdded:Connect(function(character)
			if isOverlayBlocking(self) then
				watchCharacter(character)
			end
		end)
		table.insert(self._overheadConns, conn)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	local addConn = Players.PlayerAdded:Connect(function(player: Player)
		if isOverlayBlocking(self) then
			watchPlayer(player)
		end
	end)
	table.insert(self._overheadConns, addConn)
end

function LoadingScreenUI:_restoreOverheads()
	for _, conn in ipairs(self._overheadConns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._overheadConns = {}

	for _, entry in ipairs(self._overheadSuppressed) do
		pcall(function()
			if entry.gui and entry.gui.Parent then
				entry.gui.Enabled = entry.wasEnabled
			end
		end)
	end
	self._overheadSuppressed = {}
end

-- ── Other-Player Visibility ─────────────────────────────────

function LoadingScreenUI:_hideOtherPlayersLocally()
	self._hiddenParts = {}
	self._playerHideConns = {}

	local localPlayer = Players.LocalPlayer

	local function hideCharacter(character: Model)
		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("BasePart") then
				local part = desc :: BasePart
				if self._hiddenParts[part] == nil then
					self._hiddenParts[part] = part.LocalTransparencyModifier
				end
				part.LocalTransparencyModifier = 1
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			if player.Character then
				hideCharacter(player.Character)
			end
			local conn = player.CharacterAdded:Connect(function(character)
				if isOverlayBlocking(self) then
					hideCharacter(character)
				end
			end)
			table.insert(self._playerHideConns, conn)
		end
	end

	local addConn = Players.PlayerAdded:Connect(function(player: Player)
		if player == localPlayer then
			return
		end
		if not isOverlayBlocking(self) then
			return
		end
		if player.Character then
			hideCharacter(player.Character)
		end
		local conn = player.CharacterAdded:Connect(function(character)
			if isOverlayBlocking(self) then
				hideCharacter(character)
			end
		end)
		table.insert(self._playerHideConns, conn)
	end)
	table.insert(self._playerHideConns, addConn)
end

function LoadingScreenUI:_restoreOtherPlayersLocally()
	for _, conn in ipairs(self._playerHideConns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._playerHideConns = {}

	for part, localTransparencyModifier in pairs(self._hiddenParts) do
		pcall(function()
			if part and part.Parent then
				part.LocalTransparencyModifier = localTransparencyModifier
			end
		end)
	end
	self._hiddenParts = {}
end

function LoadingScreenUI:_cancelFadeDelay()
	local threadHandle = self._fadeDelay
	self._fadeDelay = nil
	if threadHandle and threadHandle ~= coroutine.running() then
		pcall(task.cancel, threadHandle)
	end
end

function LoadingScreenUI:_cancelWatchdogDelay()
	local threadHandle = self._watchdogDelay
	self._watchdogDelay = nil
	if threadHandle and threadHandle ~= coroutine.running() then
		pcall(task.cancel, threadHandle)
	end
end

function LoadingScreenUI:_cancelSkipPromptDelay()
	local threadHandle = self._skipPromptDelay
	self._skipPromptDelay = nil
	if threadHandle and threadHandle ~= coroutine.running() then
		pcall(task.cancel, threadHandle)
	end
end

function LoadingScreenUI:_applyLoadingColor()
	if not self._colorCorrection then
		return
	end

	if self._colorCorrectionTween then
		self._colorCorrectionTween:Cancel()
		self._colorCorrectionTween = nil
	end

	-- 1. Snap instantly to pitch black
	local cc = self._colorCorrection
	cc.Enabled = true
	cc.Brightness = BLACKOUT_COLOR.Brightness
	cc.Contrast = BLACKOUT_COLOR.Contrast
	cc.Saturation = BLACKOUT_COLOR.Saturation
	cc.TintColor = BLACKOUT_COLOR.TintColor

	-- 2. After a brief pause, tween up to the cinematic loading look
	task.delay(LoadingConfig.BLACKOUT_TO_LOADING_DELAY, function()
		if not self._available or not self._colorCorrection then
			return
		end
		if self._colorCorrectionTween then
			self._colorCorrectionTween:Cancel()
		end
		self._colorCorrectionTween = TweenService:Create(self._colorCorrection, COLOR_FADE_IN_TWEEN, LOADING_COLOR)
		self._colorCorrectionTween:Play()
	end)
end

function LoadingScreenUI:_applyProgressDisplay(progress: number)
	if not self._available or not self._refs or not self._barBaseSize then
		return
	end

	local clamped = clamp(progress, 0, 1)
	self._progressDisplay = clamped

	local baseSize = self._barBaseSize
	local nextWidthScale = baseSize.X.Scale * clamped
	local nextWidthOffset = math.floor(baseSize.X.Offset * clamped + 0.5)
	self._refs.barFill.Size = UDim2.new(nextWidthScale, nextWidthOffset, baseSize.Y.Scale, baseSize.Y.Offset)

	if self._refs.progressLabel and self._refs.progressLabel.Visible then
		self._refs.progressLabel.Text = string.format("%d%%", math.floor(clamped * 100 + 0.5))
	end

	self:_updateBlurFromProgress(clamped)
	self:_tryEndIntro()
end

function LoadingScreenUI:_runProgressAnimation()
	if self._progressRenderConn then
		return
	end

	self._progressRenderConn = RunService.RenderStepped:Connect(function(dt: number)
		if not self._available then
			self:_cancelProgressAnimation()
			return
		end

		local target = self._progressTarget or 0
		local display = self._progressDisplay or 0
		local diff = target - display

		if math.abs(diff) < 0.0005 then
			self._progressDisplay = target
			self:_applyProgressDisplay(target)
			return
		end

		local alpha = math.clamp(dt * PROGRESS_SMOOTH_SPEED, 0, 1)
		local next = display + diff * alpha
		self._progressDisplay = next
		self:_applyProgressDisplay(next)
	end)
end

function LoadingScreenUI:_fadeOutAndClose()
	if not self._refs then
		self:_finalizeDismissal()
		return
	end

	self:_cancelFadeDelay()

	if self._colorCorrection then
		if self._colorCorrectionTween then
			self._colorCorrectionTween:Cancel()
		end
		self._colorCorrection.Enabled = true
		self._colorCorrectionTween = TweenService:Create(self._colorCorrection, COLOR_FADE_OUT_TWEEN, NEUTRAL_COLOR)
		self._colorCorrectionTween:Play()
	end

	self._fadeDelay = task.delay(COLOR_FADE_OUT_TWEEN.Time, function()
		self._fadeDelay = nil
		if not self._available then
			return
		end

		self:_finalizeDismissal()
	end)
end

function LoadingScreenUI:_restoreColorCorrection()
	if not self._colorCorrection then
		return
	end

	if self._colorCorrectionTween then
		self._colorCorrectionTween:Cancel()
		self._colorCorrectionTween = nil
	end

	pcall(function()
		self._colorCorrection:Destroy()
	end)
	self._colorCorrection = nil
end

function LoadingScreenUI:_finalizeDismissal()
	if self._dismissed then
		return
	end

	self:_cancelFinishDelay()
	self:_cancelWatchdogDelay()
	self:_cancelProgressAnimation()
	self:_cancelTextCycles()

	if self._clickConn then
		self._clickConn:Disconnect()
		self._clickConn = nil
	end
	if self._skipDuringLoadConn then
		self._skipDuringLoadConn:Disconnect()
		self._skipDuringLoadConn = nil
	end
	self._skipDuringLoadAllowed = false

	self._waitingForClick = false
	self._dismissing = false
	self._dismissed = true
	self._bootFinished = true
	self._started = false
	self._finishRequested = false
	self._startClock = nil

	self:_fireGameplayEntered()

	self:_restoreColorCorrection()
	self:_destroyIntroLayer()

	if self._refs then
		self._refs.root.Enabled = false
	end

	self:_restoreCinematicCamera()
	self._cinematicStarted = false
	self._introActive = false
	self._introEnded = false
	self:_restoreOverheads()
	self:_restoreOtherPlayersLocally()
	self:_restorePlayerGuiVisibility()
end

function LoadingScreenUI:_enterWaitForClick()
	if not self._available or not self._refs then
		self:_fadeOutAndClose()
		return
	end

	self:_cancelTextCycles()
	self:_cancelProgressAnimation()

	-- Swap to welcome state
	local name = self._displayName or "Player"
	local welcomeFormat = LoadingConfig.WELCOME_DISMISS_FORMAT or "Welcome to the club, %s"
	self._refs.titleLabel.Text = string.format(welcomeFormat, name)
	self._refs.tipsLabel.Text = "Tap anywhere to skip"
	self._refs.tipsLabel.TextTransparency = 0

	-- Hide the progress bar — not needed here
	local barWrapper = self._refs.loadingBarWrapper :: GuiObject
	barWrapper.Visible = false

	self._waitingForClick = true

	-- Accept any mouse click, touch, or key press
	self._clickConn = UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if not self._waitingForClick then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1
		then
			self:_doClickReveal()
		end
	end)
end

function LoadingScreenUI:_doClickReveal()
	if not self._waitingForClick then
		return
	end
	self._waitingForClick = false
	self._dismissing = true

	if self._clickConn then
		self._clickConn:Disconnect()
		self._clickConn = nil
	end

	if not self._colorCorrection then
		-- No color correction available — skip straight to cleanup
		self:_finalizeDismissal()
		return
	end

	if self._cinematicCamera then
		self._cinematicCamera:playClickLift(LoadingConfig.CLICK_BLACKOUT_DURATION)
	end

	-- Step 1: Fade to pitch black before revealing gameplay.
	if self._colorCorrectionTween then
		self._colorCorrectionTween:Cancel()
	end
	self._colorCorrectionTween = TweenService:Create(
		self._colorCorrection,
		TweenInfo.new(LoadingConfig.CLICK_BLACKOUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		BLACKOUT_COLOR
	)
	self._colorCorrectionTween:Play()

	-- Step 2: Once black — hide all loading UI then fade back to normal
	task.delay(LoadingConfig.CLICK_BLACKOUT_DURATION, function()
		if not self._available then
			return
		end
		-- Hide loading content while screen is pitch black
		if self._refs then
			if self._refs.contentWrapper then
				local cw = self._refs.contentWrapper :: GuiObject
				cw.Visible = false
			elseif self._refs.content then
				local ct = self._refs.content :: GuiObject
				ct.Visible = false
			end
		end
		if self._cinematicCamera then
			self._cinematicCamera:playGameplayDrop(LoadingConfig.CLICK_REVEAL_DURATION)
		end
		-- Step 3: Fade back to normal gameplay lighting over 1.4s
		if self._colorCorrectionTween then
			self._colorCorrectionTween:Cancel()
		end
		self._colorCorrectionTween = TweenService:Create(
			self._colorCorrection,
			TweenInfo.new(LoadingConfig.CLICK_REVEAL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			NEUTRAL_COLOR
		)
		self._colorCorrectionTween:Play()
		-- Step 4: After fade completes — full cleanup
		task.delay(LoadingConfig.CLICK_REVEAL_DURATION, function()
			if not self._available then
				return
			end
			self:_finalizeDismissal()
		end)
	end)
end

function LoadingScreenUI:_completeFinish()
	if not self._available or self._bootFinished then
		return
	end

	self:_cancelFinishDelay()
	self:_cancelWatchdogDelay()
	self:_cancelSkipPromptDelay()

	self._bootFinished = true
	self._started = false
	self._finishRequested = false
	self._startClock = nil
	self:_enterWaitForClick()
end

function LoadingScreenUI:_scheduleFinish()
	self:_cancelFinishDelay()

	local startedAt = self._startClock
	if not startedAt then
		self:_completeFinish()
		return
	end

	local elapsed = os.clock() - startedAt
	local remaining = math.max(self._minimumDuration - elapsed, FINAL_HOLD_DURATION)
	if remaining <= 0 then
		self:_completeFinish()
		return
	end

	self._finishDelay = task.delay(remaining, function()
		self._finishDelay = nil
		if self._available and self._finishRequested then
			self:_completeFinish()
		end
	end)
end

function LoadingScreenUI:_startTextCycles(displayName: string?)
	local name = displayName and displayName ~= "" and displayName or "Player"
	self._displayName = name

	-- Cancel any running cycles first
	self:_cancelTextCycles()

	-- Greeting cycle: rotate through list every 5s with fade transition
	local GREET_FADE_IN =
		TweenInfo.new(LoadingConfig.GREETING_FADE_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local GREET_FADE_OUT =
		TweenInfo.new(LoadingConfig.GREETING_FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	self._greetingCycleThread = task.spawn(function()
		local greetings = self._greetings
		local primaryGreeting = LoadingConfig.PRIMARY_GREETING
		if type(primaryGreeting) == "string" and primaryGreeting ~= "" then
			greetings = { primaryGreeting }
		end
		local idx = 1
		while self._available and self._started and not self._bootFinished do
			if self._refs then
				self._refs.titleLabel.Text = formatGreetingLine(greetings[idx], name)
				TweenService:Create(self._refs.titleLabel, GREET_FADE_IN, { TextTransparency = 0 }):Play()
			end
			idx = (idx % #greetings) + 1
			task.wait(LoadingConfig.GREETING_VISIBLE_DURATION)
			if not (self._available and self._started and not self._bootFinished) then
				break
			end
			if self._refs then
				TweenService:Create(self._refs.titleLabel, GREET_FADE_OUT, { TextTransparency = 1 }):Play()
			end
			task.wait(LoadingConfig.GREETING_FADE_GAP)
		end
	end)

	-- Tips cycle: rotate through list every 8s
	self._tipsCycleThread = task.spawn(function()
		local tips = self._tips
		local idx = 1
		while self._available and self._started and not self._bootFinished do
			if self._refs then
				self._refs.tipsLabel.Text = tips[idx]
			end
			idx = (idx % #tips) + 1
			task.wait(LoadingConfig.TIPS_CYCLE_DURATION)
		end
	end)
end

function LoadingScreenUI:_cancelTextCycles()
	if self._greetingCycleThread then
		pcall(task.cancel, self._greetingCycleThread)
		self._greetingCycleThread = nil
	end
	if self._tipsCycleThread then
		pcall(task.cancel, self._tipsCycleThread)
		self._tipsCycleThread = nil
	end
end

function LoadingScreenUI:setTitle(displayName: string?)
	if not self._available or not self._refs then
		return
	end

	local greeting = pick(self._greetings, self._rng)
	local name = displayName and displayName ~= "" and displayName or "Player"
	self._refs.titleLabel.Text = string.format("%s, %s", greeting, name)
end

function LoadingScreenUI:setTip(text: string?)
	if not self._available or not self._refs then
		return
	end

	if text and text ~= "" then
		self._refs.tipsLabel.Text = text
		return
	end

	self._refs.tipsLabel.Text = pick(self._tips, self._rng)
end

function LoadingScreenUI:_bindSkipDuringLoadInput()
	if self._skipDuringLoadConn then
		return
	end

	self._skipDuringLoadConn = UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if not self._skipDuringLoadAllowed or self._bootFinished or self._waitingForClick then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1
		then
			self:finish()
		end
	end)
end

--- Boot + overhead siap: izinkan skip (tap anywhere) tanpa fake early finish.
function LoadingScreenUI:setSkipAvailable(enabled: boolean)
	if not self._available or not self._refs or self._bootFinished then
		return
	end

	self._skipDuringLoadAllowed = enabled == true
	if not enabled then
		return
	end

	self._refs.tipsLabel.Text = "Tap anywhere to skip"
	self._refs.tipsLabel.TextTransparency = 0
	self:_bindSkipDuringLoadInput()
end

function LoadingScreenUI:setProgress(progress: number)
	if not self._available or not self._refs or not self._barBaseSize then
		return
	end

	local clamped = clamp(progress, 0, 1)
	if clamped > self._progressTarget then
		self._progressTarget = clamped
	end

	if
		self._progressDisplay < LoadingConfig.INITIAL_PROGRESS
		and self._progressTarget > LoadingConfig.INITIAL_PROGRESS
	then
		self._progressDisplay = LoadingConfig.INITIAL_PROGRESS
		self:_applyProgressDisplay(LoadingConfig.INITIAL_PROGRESS)
	end

	self:_runProgressAnimation()
end

function LoadingScreenUI:start(displayName: string?, tipText: string?)
	if not self._available or self._bootFinished or self._dismissed then
		return
	end

	if self._started and not self._bootFinished then
		if self._refs then
			self._refs.root.Enabled = true
		end
		return
	end

	if self._refs then
		suppressDefaultPlaceholderLabels(self._refs.root)
		self._refs.root.Enabled = true
		self._refs.loadingBarWrapper.Visible = true
		self._refs.barFill.Visible = true
		self._refs.loadingMark.Visible = true

		-- Start content as invisible — intro / main phase fade them in.
		self._refs.titleLabel.TextTransparency = 1
		self._refs.tipsLabel.TextTransparency = 1
	end

	self._started = true
	self._bootFinished = false
	self._dismissed = false
	self._dismissing = false
	self._finishRequested = false
	self._startClock = os.clock()
	self._cinematicStarted = false
	self._introActive = false
	self._introEnded = false
	self._pendingDisplayName = displayName

	if not self._colorCorrection then
		self._colorCorrection = createColorCorrection()
	end

	self:setTitle(displayName)
	self:setTip(tipText)
	self:_applyIntroBlackout()
	self:_startIntroLayer()
	self:_suppressOverheads()
	self:_hideOtherPlayersLocally()
	self:setProgress(LoadingConfig.INITIAL_PROGRESS)

	self:_cancelWatchdogDelay()
	self:_cancelSkipPromptDelay()

	local watchdogTimeout = self._minimumDuration + WATCHDOG_BUFFER + 40
	self._watchdogDelay = task.delay(watchdogTimeout, function()
		self._watchdogDelay = nil
		if not self._available or self._bootFinished then
			return
		end

		warn(string.format("[LoadingScreenUI] watchdog forcing close after %.1fs", watchdogTimeout))
		self:_completeFinish()
	end)
end

function LoadingScreenUI:finish()
	if not self._available or self._bootFinished or self._dismissed then
		return
	end

	self._finishRequested = true
	-- Ensure cinematic/main phase exists before welcome dismiss if intro is still up.
	if self._introActive and not self._introEnded then
		self:setProgress(1)
		local minDuration = math.max(0, tonumber(LoadingConfig.INTRO_MIN_DURATION) or 1.25)
		local elapsed = if self._startClock then os.clock() - self._startClock else minDuration
		local remainingIntro = math.max(0, minDuration - elapsed)
		task.delay(remainingIntro, function()
			if not (self._available and self._finishRequested) then
				return
			end
			if self._introActive and not self._introEnded then
				self:_endIntro(false)
			end
			self:_scheduleFinish()
		end)
		return
	elseif not self._cinematicStarted then
		self:_beginMainLoadingPhase(self._pendingDisplayName)
	end
	self:setProgress(1)
	self:_scheduleFinish()
end

function LoadingScreenUI:destroy()
	if not self._available then
		if sharedInstance == self then
			sharedInstance = nil
		end
		return
	end

	self:_cancelFinishDelay()
	self:_cancelFadeDelay()
	self:_cancelWatchdogDelay()
	self:_cancelSkipPromptDelay()
	self:_cancelProgressAnimation()

	if self._clickConn then
		self._clickConn:Disconnect()
		self._clickConn = nil
	end
	if self._skipDuringLoadConn then
		self._skipDuringLoadConn:Disconnect()
		self._skipDuringLoadConn = nil
	end
	self._skipDuringLoadAllowed = false
	self._waitingForClick = false

	self:_finalizeDismissal()

	self._available = false
	self._started = false
	self._bootFinished = true
	self._dismissed = true
	self._dismissing = false
	self._finishRequested = false
	self._startClock = nil

	if sharedInstance == self then
		sharedInstance = nil
	end
end

return LoadingScreenUI
