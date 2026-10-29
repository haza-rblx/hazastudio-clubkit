--!strict
-- Onboarding modal shell (CONTEXT.md "Onboarding"): the 17-OnboardingGUI split sketch (stage on
-- the left, panel on the right), Back / close / primary button, step navigation and open/close
-- motion. The steps themselves live in OnboardingSteps.
--
-- Built from the owner's design pieces found in PlayerGui; a place without the sketch (or its
-- buttons) gets no modal: `OnboardingUI.open` returns nil and says what was missing.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Icon = require(ReplicatedStorage.Hazastudio_ClubKit.Icon) :: any
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local PhoneLayout = require(script.Parent.Parent.Parent.Utils.PhoneLayout)
local Kit = require(script.Parent.OnboardingKit)
local Controls = require(script.Parent.OnboardingControls)
local Steps = require(script.Parent.OnboardingSteps)

type Ctx = Kit.Ctx

export type Session = {
	goTo: (index: number) -> (),
	close: () -> (),
	destroy: () -> (),
	isOpen: () -> boolean,
}

export type OpenOptions = {
	apply: Kit.Apply,
	placeName: string,
	onClosed: (() -> ())?,
}

local SKETCH_GUI = "17-OnboardingGUI"
local MENU_GUI = "07-MenuGUI"
local TOP_MENU_GUI = "15-TopMenuGUI"
local LOADING_GUI = "00-LoadingScreen"
local REMINDERS_GUI = "19-EventReminders"
local SHELL_GUI = "ClubKitOnboarding"

local log = Logger.new("OnboardingUI")

local tween = Kit.tween
local SHELL_W, SHELL_H = Kit.SHELL_W, Kit.SHELL_H
local TOP_H = Kit.TOP_H

local OnboardingUI = {}

local function menuPillSource(): any
	local found: any = nil
	local ok, icons = pcall(function()
		return Icon.getIcons()
	end)
	if not ok or type(icons) ~= "table" then
		return nil
	end
	for _, icon in pairs(icons) do
		local okLabel, lbl = pcall(function()
			return icon:getInstance("IconLabel")
		end)
		if okLabel and lbl and (lbl.Text == "Menu" or lbl.Text == "Close Menu") then
			found = icon.widget
		end
	end
	return found
end

-- Everything the modal clones from. Optional parts are nil when the place lacks them.
local function resolveSources(playerGui: PlayerGui): Kit.Sources
	local menuGui = playerGui:FindFirstChild(MENU_GUI)
	local settingsTab = if menuGui then menuGui:FindFirstChild("SettingsTab", true) else nil
	local profileTab = if menuGui then menuGui:FindFirstChild("ProfileTab", true) else nil
	local topMenuGui = playerGui:FindFirstChild(TOP_MENU_GUI)
	local remindersGui = playerGui:FindFirstChild(REMINDERS_GUI)
	return {
		loadingScreen = playerGui:FindFirstChild(LOADING_GUI),
		settingsTab = settingsTab,
		profileTab = profileTab,
		topBarMenu = if topMenuGui then topMenuGui:FindFirstChild("TopBarMenu", true) else nil,
		questPopup = playerGui:FindFirstChild(Config.EventBoard.QUEST_POPUP_GUI),
		reminderCard = Kit.find(remindersGui, "Templates", "ReminderCard"),
		summarySrc = if profileTab then profileTab:FindFirstChild("PlayerInfoSummary") else nil,
		menuPillSrc = menuPillSource(),
	}
end

-- Opens the modal. Returns the session, or nil plus the name of the piece that is missing.
function OnboardingUI.open(options: OpenOptions): (Session?, string?)
	local lp = Players.LocalPlayer
	local playerGui = lp:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, "PlayerGui"
	end
	local sketchGui = playerGui:FindFirstChild(SKETCH_GUI)
	local sketch = if sketchGui then sketchGui:FindFirstChild("Frame") else nil
	if not sketch then
		return nil, SKETCH_GUI .. ".Frame"
	end
	local src = resolveSources(playerGui)

	local leftSrc: Frame?, rightSrc: Frame? = nil, nil
	local inner = sketch:FindFirstChildOfClass("Frame")
	for _, f in ipairs(if inner then inner:GetChildren() else {}) do
		if f:IsA("Frame") then
			if f.AnchorPoint.X == 0 then
				leftSrc = f
			else
				rightSrc = f
			end
		end
	end
	if not leftSrc or not rightSrc then
		return nil, SKETCH_GUI .. " stage/panel frames"
	end
	local primarySrc = if src.questPopup then src.questPopup:FindFirstChild("SubmitButton", true) else nil
	local backSrc = if src.settingsTab then src.settingsTab:FindFirstChild("BacktoMainMenuButton") else nil
	if not primarySrc then
		return nil, Config.EventBoard.QUEST_POPUP_GUI .. ".SubmitButton"
	end
	if not backSrc then
		return nil, MENU_GUI .. " SettingsTab.BacktoMainMenuButton"
	end

	-- ── shell ──────────────────────────────────────────────────────────────────────────────
	local gui = Instance.new("ScreenGui")
	gui.Name = SHELL_GUI
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 250
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Active = true
	dim.Parent = gui

	-- The fade group is larger than the modal so the UIShadows are not clipped by it.
	local SHADOW_MARGIN = 60
	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromOffset(SHELL_W + SHADOW_MARGIN * 2, SHELL_H + SHADOW_MARGIN * 2)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	-- Phones: the shell is taller than a landscape phone (iPhone 7 is 667x375), so a FitStage with
	-- its own UIScale shrinks the whole modal to the screen. shellScale stays the open/close
	-- motion's: only the first UIScale under a GuiObject applies, so the two sit on different frames.
	local FIT_MARGIN = 12
	local fitStage = Instance.new("Frame")
	fitStage.Name = "FitStage"
	fitStage.AnchorPoint = Vector2.new(0.5, 0.5)
	fitStage.Position = UDim2.fromScale(0.5, 0.5)
	fitStage.Size = group.Size
	fitStage.BackgroundTransparency = 1
	fitStage.BorderSizePixel = 0
	fitStage.Parent = gui
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = fitStage
	local function fitToScreen()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local room = camera.ViewportSize
		-- On a phone the modal stays clear of the topbar and the hotbar (owner 2026-10-09).
		local top, bottom = FIT_MARGIN, FIT_MARGIN
		if PhoneLayout.isPhoneLayout() then
			local onboarding = Config.Onboarding :: any
			top = GuiService:GetGuiInset().Y + (tonumber(onboarding.PHONE_TOP_GAP) or 10)
			bottom = tonumber(onboarding.PHONE_BOTTOM_RESERVE) or 66
		end
		local availableY = math.max(1, room.Y - top - bottom)
		fitScale.Scale = math.min(1, (room.X - 2 * FIT_MARGIN) / SHELL_W, availableY / SHELL_H)
		fitStage.Position = UDim2.new(0.5, 0, 0, top + availableY / 2)
	end
	fitToScreen()
	group.Parent = fitStage
	local shellScale = Instance.new("UIScale")
	shellScale.Scale = 0.94
	shellScale.Parent = group
	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromOffset(SHELL_W, SHELL_H)
	shell.BackgroundTransparency = 1
	shell.BorderSizePixel = 0
	shell.Parent = group

	-- The owner's own UIShadow (ReminderCard Header/Body), cloned onto each half.
	local shadowSrc = if src.reminderCard then src.reminderCard:FindFirstChild("Header") else nil
	shadowSrc = if shadowSrc then shadowSrc:FindFirstChildOfClass("UIShadow") else nil
	local function addShadow(frame: Instance)
		if shadowSrc then
			shadowSrc:Clone().Parent = frame
		end
	end

	-- Corner discipline (owner 2026-10-08): the two halves are separate pieces with a 2px gap,
	-- 28px on the outside and 4px where they meet, like the grouped rows (18 / 4).
	local OUTER, INNER, HALF_GAP = 28, 4, 1
	local function cornerRadii(frame: Instance, topLeft: number, topRight: number, bottomLeft: number, bottomRight: number)
		local corner = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		corner.TopLeftRadius = UDim.new(0, topLeft)
		corner.TopRightRadius = UDim.new(0, topRight)
		corner.BottomLeftRadius = UDim.new(0, bottomLeft)
		corner.BottomRightRadius = UDim.new(0, bottomRight)
		corner.Parent = frame
	end

	-- Shadow casters behind each half; the halves themselves clip their content to the corners.
	local stageBack = Instance.new("Frame")
	stageBack.Name = "StageBack"
	stageBack.BackgroundColor3 = Color3.fromHex("262626")
	stageBack.BorderSizePixel = 0
	stageBack.Size = UDim2.new(0.5, -HALF_GAP, 1, 0)
	cornerRadii(stageBack, OUTER, INNER, OUTER, INNER)
	addShadow(stageBack)
	stageBack.Parent = shell

	local stageSrc = Kit.cleanClone(leftSrc)
	-- A CanvasGroup, so rounded corners clip the previews instead of cutting them off square.
	local stage = Instance.new("CanvasGroup")
	stage.Name = "Stage"
	stage.BackgroundColor3 = stageSrc.BackgroundColor3
	for k, v in pairs(stageSrc:GetAttributes()) do
		stage:SetAttribute(k, v)
	end
	stage.BorderSizePixel = 0
	stage.Size = UDim2.new(0.5, -HALF_GAP, 1, 0)
	cornerRadii(stage, OUTER, INNER, OUTER, INNER)
	stageSrc:Destroy()
	stage.ClipsDescendants = true
	stage.Parent = shell

	-- Backdrop painted here, outside the surface tint: neutral while the player keeps the design
	-- colours (Multicolor / Graphite), the accent otherwise. The stage frame itself stays
	-- transparent but is still tinted, which is how the accent colour is read back below.
	local stageBg = Instance.new("Frame")
	stageBg.Name = "StageBg"
	stageBg.Size = UDim2.fromScale(1, 1)
	stageBg.BorderSizePixel = 0
	stageBg.ZIndex = 0
	stageBg:SetAttribute(Kit.NO_TINT, true)
	stageBg.Parent = stage
	local function paintStageBg()
		stageBg.BackgroundColor3 = if AccentService.isDesign() then Color3.fromHex("262626") else stage.BackgroundColor3
	end
	stage.BackgroundTransparency = 1
	paintStageBg()
	local stageSignal = stage:GetPropertyChangedSignal("BackgroundColor3"):Connect(paintStageBg)
	local unsubAccent = AccentService.subscribe(paintStageBg)

	local panel = Kit.cleanClone(rightSrc)
	panel.Name = "Panel"
	for _, c in ipairs(panel:GetChildren()) do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.fromScale(1, 0)
	panel.Size = UDim2.new(0.5, -HALF_GAP, 1, 0)
	panel.BackgroundColor3 = (sketch :: Frame).BackgroundColor3
	panel.BackgroundTransparency = 0
	cornerRadii(panel, INNER, OUTER, INNER, OUTER)
	addShadow(panel)
	panel.ClipsDescendants = true
	local pad = panel:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = panel
	end
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	panel.Parent = shell

	local wipe = Instance.new("Frame")
	wipe.Name = "Wipe"
	wipe.Size = UDim2.fromScale(1, 1)
	wipe.BackgroundColor3 = stageBg.BackgroundColor3
	wipe:SetAttribute(Kit.NO_TINT, true)
	local wipeSignal = stageBg:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		wipe.BackgroundColor3 = stageBg.BackgroundColor3
	end)
	wipe.BackgroundTransparency = 1
	wipe.ZIndex = 50
	wipe.BorderSizePixel = 0
	cornerRadii(wipe, OUTER, INNER, OUTER, INNER)
	wipe.Parent = stage

	-- Top row: Back on the left. No close X (owner 2026-10-08).
	local close: any = nil

	local back = Kit.cleanClone(backSrc)
	back.Size = UDim2.fromOffset(112, 40)
	back.Position = UDim2.fromOffset(-3, 0)
	local backLabel = back:FindFirstChildOfClass("TextLabel")
	if backLabel then
		backLabel.Text = "Back"
	end
	-- Arrow and label on one centre line, arrow larger (owner 2026-10-08).
	local backLayout = back:FindFirstChildOfClass("UIListLayout")
	if backLayout then
		backLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	local backIcon = back:FindFirstChildWhichIsA("ImageButton") or back:FindFirstChildWhichIsA("ImageLabel")
	if backIcon then
		local ratio = backIcon:FindFirstChildOfClass("UIAspectRatioConstraint")
		if ratio then
			ratio:Destroy()
		end
		backIcon.Size = UDim2.fromOffset(32, 32)
	end
	back.Parent = panel

	-- Primary: the quest popup SubmitButton, full width like the ReminderCard ButtonSlot.
	local primary = Kit.cleanClone(primarySrc)
	primary.AnchorPoint = Vector2.new(0, 1)
	primary.Position = UDim2.fromScale(0, 1)
	primary.Size = UDim2.new(1, 0, 0, 40)
	primary.Parent = panel
	local primaryLabel = primary:FindFirstChildOfClass("TextLabel")
	if primaryLabel then
		primaryLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

	local pageHost = Instance.new("Frame")
	pageHost.Name = "Page"
	pageHost.BackgroundTransparency = 1
	pageHost.Size = UDim2.new(1, 0, 1, -52)
	pageHost.Parent = panel

	local ctx: Ctx = {
		gui = gui,
		shell = shell,
		stage = stage,
		stageBg = stageBg,
		panel = panel,
		wipe = wipe,
		shellScale = shellScale,
		conns = {},
		picks = {},
		alive = true,
		runToken = 0,
		src = src,
		apply = options.apply,
		placeName = options.placeName,
	}
	if workspace.CurrentCamera then
		table.insert(ctx.conns, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen))
	end

	-- ── navigation ─────────────────────────────────────────────────────────────────────────
	local current = 0
	local currentPage: Frame? = nil
	local busy = false
	local destroyed = false

	local function clearStage()
		for _, c in ipairs(stage:GetChildren()) do
			if c ~= wipe and c ~= stageBg and not c:IsA("UICorner") then
				c:Destroy()
			end
		end
	end

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		ctx.alive = false
		for _, c in ipairs(ctx.conns) do
			c:Disconnect()
		end
		table.clear(ctx.conns)
		stageSignal:Disconnect()
		wipeSignal:Disconnect()
		unsubAccent()
		gui:Destroy()
		if options.onClosed then
			options.onClosed()
		end
	end

	local function closeAll()
		if not ctx.alive then
			return
		end
		ctx.alive = false
		tween(shellScale, 0.3, { Scale = 0.94 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(group, 0.3, { GroupTransparency = 1 })
		tween(dim, 0.3, { BackgroundTransparency = 1 })
		task.delay(0.35, destroy)
	end

	local function goTo(index: number)
		if busy or not ctx.alive or index < 1 then
			return
		end
		if index > #Steps.list then
			-- Finishing stores the "don't show again" tick (ticked unless the player cleared it).
			ctx.apply.dismiss(ctx.picks.dontShow ~= false)
			closeAll()
			return
		end
		busy = true
		ctx.runToken += 1
		local token = ctx.runToken
		local dir = if index >= current then 1 else -1
		current = index
		if currentPage then
			local old = currentPage
			tween(old, 0.2, { Position = UDim2.fromOffset(-24 * dir, old.Position.Y.Offset) })
			for _, d in ipairs(old:GetDescendants()) do
				if d:IsA("TextLabel") then
					tween(d, 0.15, { TextTransparency = 1 })
				end
			end
			tween(wipe, 0.18, { BackgroundTransparency = 0 })
			task.wait(0.2)
			old:Destroy()
		end
		if not ctx.alive then
			busy = false
			return
		end
		clearStage()
		-- Step 1 has no Back, so its page starts at the top; later pages sit under the Back row.
		local topY = if index > 1 then TOP_H else 0
		back.Visible = index > 1
		pageHost.Position = UDim2.fromOffset(0, topY)
		pageHost.Size = UDim2.new(1, 0, 1, -52 - topY)
		local page = Controls.newPage()
		page.Position = UDim2.fromOffset(28 * dir, 0)
		page.Parent = pageHost
		currentPage = page
		local ok, err = pcall(function(): any
			Steps.list[index](ctx, page, token)
			return nil
		end)
		if not ok then
			log:warn("Onboarding step failed", { step = index, err = tostring(err) })
		end
		tween(page, 0.35, { Position = UDim2.fromOffset(0, 0) })
		tween(wipe, 0.3, { BackgroundTransparency = 1 })
		if primaryLabel then
			primaryLabel.Text = if index == 1 then "Get started" elseif index == #Steps.list then "Let's go" else "Next"
		end
		task.wait(0.3)
		busy = false
	end

	local function bindPress(button: GuiObject)
		for _, c in ipairs(UIMotion.bindPress(button)) do
			table.insert(ctx.conns, c)
		end
	end
	bindPress(primary)
	bindPress(back)
	table.insert(
		ctx.conns,
		primary.Activated:Connect(function()
			goTo(current + 1)
		end)
	)
	table.insert(
		ctx.conns,
		back.Activated:Connect(function()
			goTo(current - 1)
		end)
	)
	if close then
		table.insert(ctx.conns, close.Activated:Connect(closeAll))
	end

	gui.Parent = playerGui
	tween(dim, 0.35, { BackgroundTransparency = 0.45 })
	tween(group, 0.35, { GroupTransparency = 0 })
	tween(shellScale, 0.45, { Scale = 1 })
	task.spawn(goTo, 1)

	local session: Session = {
		goTo = goTo,
		close = closeAll,
		destroy = destroy,
		isOpen = function()
			return not destroyed
		end,
	}
	return session, nil
end

return OnboardingUI
