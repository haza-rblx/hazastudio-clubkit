--!strict

local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local UISpring = require(script.Parent.Parent.Utils.UISpring)
local LeaderstatsVisibilityService = require(script.Parent.Parent.Services.LeaderstatsVisibilityService)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)
local TopMenuGuiRefs = require(script.Parent.Parent.UI.TopMenuGuiRefs)
local OverheadController = require(script.Parent.OverheadController)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local AccentService = require(script.Parent.Parent.Services.AccentService)
local AccentSurfaceTint = require(script.Parent.Parent.Services.AccentSurfaceTint)
local EventBoardController = require(script.Parent.EventBoardController)

local TopMenuController = {}
local log = Logger.new("TopMenuController")

type IconsMap = {
	shop: any,
	donation: any,
	gift: any,
	couple: any,
	settings: any,
	cinematic: any,
	broadcast: any,
}

type InitDeps = {
	menuIcon: any,
	icons: IconsMap,
	settingsUI: any,
	-- When false, hide CinematicDockButton on desktop + phone top menus.
	isCinematicVisible: (() -> boolean)?,
	-- The MusicTopbarIcon wrapper, read at click/open time (it is created after this init is queued).
	getMusicIcon: (() -> any)?,
}

-- A topbar icon whose row the menu carries (see adoptTopbarTrigger).
type AdoptedTrigger = {
	icon: any,
	allowed: boolean,
	routed: boolean,
	realSetEnabled: (any, boolean) -> any,
}

local MENU_HIDDEN_MARGIN = 24
local BLUR_OPTIONS = {
	enableBlur = true,
	blurName = Config.TopbarMenu.BACKDROP_BLUR_NAME,
}

local menuIconRef: any = nil
local iconsRef: IconsMap? = nil
local settingsUIRef: any = nil
-- Set by init(); binds the menu shell's Back button once both the shell and init() exist.
local bindBackToMainMenuFn: (() -> ())? = nil
local isCinematicVisibleFn: (() -> boolean)? = nil
local getMusicIconFn: (() -> any)? = nil
local adoptedTriggers: { [string]: AdoptedTrigger } = {}
local refs: TopMenuGuiRefs.Refs? = nil
local animHelper: AnimationHelper.AnimationHelper? = nil
local desktopRestingPosition: UDim2? = nil
local phoneRestingPosition: UDim2? = nil
local isOpen = false
local isAnimating = false
local menuPosSpring: UISpring.DriveHandle? = nil
local menuFadeSpring: UISpring.DriveHandle? = nil
local menuAnimToken = 0
local clickOutsideConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil
local blockedMenuIcons: { [any]: boolean } = {}
-- ADR 0011: the rows' designed text/image transparencies, captured once at init. Re-reading them
-- at open time would bake a half-faded value in as the resting value if the menu is re-opened
-- while the previous cascade is still running.
local rowFadeBases: { [GuiObject]: number } = {}
local _initConnections: { RBXScriptConnection } = {}
local _initUnsubs: { () -> () } = {}

local function trackInitConnection(conn: RBXScriptConnection)
	table.insert(_initConnections, conn)
end

local function trackInitUnsub(unsub: () -> ())
	table.insert(_initUnsubs, unsub)
end

local BUTTONS = Config.TopbarMenu.BUTTONS

-- ADR 0011: the sidebar spring settles in one step when the player asked Roblox for less motion.
local function isReducedMotion(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

local function stopMenuSprings()
	if menuPosSpring then
		menuPosSpring:stop()
		menuPosSpring = nil
	end
	if menuFadeSpring then
		menuFadeSpring:stop()
		menuFadeSpring = nil
	end
end

local function suppressTopbarPlusMenuWidgets(menuIcon: any)
	if not menuIcon or type(menuIcon.getInstance) ~= "function" then
		return
	end
	local ok, menu = pcall(function()
		return menuIcon:getInstance("Menu")
	end)
	if not ok or not menu or not menu:IsA("GuiObject") then
		return
	end
	for _, child in ipairs(menu:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute("WidgetUID") and child.Name == "Widget" then
			child.Visible = false
		end
	end
end

local function hideTriggerIcon(icon: any)
	if not icon then
		return
	end
	if type(icon.leave) == "function" then
		pcall(function()
			icon:leave()
		end)
	end
	if type(icon.setEnabled) == "function" then
		pcall(function()
			icon:setEnabled(false)
		end)
	end
end

function TopMenuController.hideTopbarTriggerIcons(triggerIcons: { any })
	for _, icon in ipairs(triggerIcons) do
		hideTriggerIcon(icon)
	end
end

function TopMenuController.attachHiddenMenuTriggers(menuIcon: any, triggerIcons: { any })
	TopMenuController.hideTopbarTriggerIcons(triggerIcons)
	suppressTopbarPlusMenuWidgets(menuIcon)
end

function TopMenuController.configureMenuIcon(menuIcon: any)
	if not menuIcon then
		return
	end

	if type(menuIcon.setImage) == "function" then
		pcall(function()
			menuIcon:setImage(Config.Icons.Topbar.Menu, "Deselected")
		end)
	end
	if type(menuIcon.setLabel) == "function" then
		pcall(function()
			local label = tostring((Config.TopbarMenu and Config.TopbarMenu.LABEL) or "Menu")
			menuIcon:setLabel(label, "Deselected")
		end)
	end
	if type(menuIcon.modifyTheme) == "function" then
		pcall(function()
			local fontId = tonumber(Config.TopbarMenu and Config.TopbarMenu.FONT_ASSET_ID) or 12187365364
			local fontFace = Font.fromId(fontId, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
			local selectedLabel = tostring(
				(Config.TopbarMenu and Config.TopbarMenu.LABEL_SELECTED) or "Close Menu"
			)
			-- No TextSize override here: the open state is a word now, not a single "X"
			-- glyph, so it has to read at the same size as the closed "Menu" label.
			menuIcon:modifyTheme({
				{ "IconLabel", "FontFace", fontFace, "Selected" },
				{ "IconLabel", "Text", selectedLabel, "Selected" },
				{ "IconLabel", "TextStrokeTransparency", 0.8, "Selected" },
				{ "IconImage", "Image", "", "Selected" },
			})
		end)
	end
	if type(menuIcon.refresh) == "function" then
		pcall(function()
			menuIcon:refresh()
		end)
	end
end

function TopMenuController.blockTopbarPlusMenu(menuIcon: any)
	if not menuIcon or blockedMenuIcons[menuIcon] then
		return
	end
	blockedMenuIcons[menuIcon] = true

	suppressTopbarPlusMenuWidgets(menuIcon)
	TopMenuController.configureMenuIcon(menuIcon)

	if type(menuIcon.setMenu) == "function" then
		menuIcon.setMenu = function(self: any, _arrayOfIcons: any)
			suppressTopbarPlusMenuWidgets(self)
			return self
		end
	end

	if menuIcon and menuIcon.menuSet and type(menuIcon.menuSet.Connect) == "function" then
		trackInitConnection(menuIcon.menuSet:Connect(function(items: any)
			if type(items) == "table" and #items > 0 then
				suppressTopbarPlusMenuWidgets(menuIcon)
			end
		end))
	end

	if menuIcon and menuIcon.menuChildAdded and type(menuIcon.menuChildAdded.Connect) == "function" then
		trackInitConnection(menuIcon.menuChildAdded:Connect(function()
			suppressTopbarPlusMenuWidgets(menuIcon)
		end))
	end

	if menuIcon and menuIcon.selected and type(menuIcon.selected.Connect) == "function" then
		trackInitConnection(menuIcon.selected:Connect(function()
			suppressTopbarPlusMenuWidgets(menuIcon)
		end))
	end
end

function TopMenuController.setSettingsUI(settingsUI: any)
	settingsUIRef = settingsUI
	-- init() and SettingsController.init run as separate boot tasks in either order; whichever
	-- comes second binds the Back button (it used to be bound by init() alone, so a shell that
	-- arrived later left Back as a plain close).
	if bindBackToMainMenuFn then
		bindBackToMainMenuFn()
	end
end

local function isPointInsideGui(gui: GuiObject?, point: Vector2): boolean
	if not gui or not gui.Visible then
		return false
	end
	local pos = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return point.X >= pos.X
		and point.X <= pos.X + size.X
		and point.Y >= pos.Y
		and point.Y <= pos.Y + size.Y
end

local function resolveTopbarWidget(icon: any): GuiObject?
	local function resolveWidget(candidate: any): GuiObject?
		if typeof(candidate) == "Instance" and candidate:IsA("GuiObject") then
			return candidate :: GuiObject
		end
		return nil
	end

	for _, candidate in ipairs({
		icon.widget,
		icon._widget,
		icon.widgetInstance,
		icon._widgetInstance,
		icon.buttonInstance,
		icon._buttonInstance,
	}) do
		local widget = resolveWidget(candidate)
		if widget then
			return widget
		end
	end

	for _, methodName in ipairs({ "getInstance", "getWidget", "getButton", "getIconInstance" }) do
		local method = icon[methodName]
		if type(method) == "function" then
			for _, arg in ipairs({ "Widget", nil }) do
				local ok, result = pcall(function()
					if arg == nil then
						return method(icon)
					end
					return method(icon, arg)
				end)
				if ok then
					local widget = resolveWidget(result)
					if widget then
						return widget
					end
				end
			end
		end
	end

	return nil
end

local function getActiveMenuFrame(): GuiObject?
	if not refs then
		return nil
	end
	if PhoneLayout.isPhoneLayout() then
		return refs.phoneMenu
	end
	return refs.desktopMenu
end

local function getRestingPosition(frame: GuiObject): UDim2
	if refs and frame == refs.desktopMenu and desktopRestingPosition then
		return desktopRestingPosition
	end
	if refs and frame == refs.phoneMenu and phoneRestingPosition then
		return phoneRestingPosition
	end
	return frame.Position
end

local function getMenuHiddenPosition(frame: GuiObject, shownPosition: UDim2): UDim2
	local width = frame.AbsoluteSize.X
	if width <= 0 then
		width = 300
	end
	return UDim2.new(
		shownPosition.X.Scale,
		shownPosition.X.Offset + width + MENU_HIDDEN_MARGIN,
		shownPosition.Y.Scale,
		shownPosition.Y.Offset
	)
end

local function applyLayoutVisibility()
	if not refs then
		return
	end

	local isPhone = PhoneLayout.isPhoneLayout()
	refs.desktopMenu.Visible = (isOpen or isAnimating) and not isPhone
	refs.phoneMenu.Visible = (isOpen or isAnimating) and isPhone

	local cinematicVisible = true
	if isCinematicVisibleFn then
		local ok, result = pcall(isCinematicVisibleFn)
		cinematicVisible = ok and result == true
	end
	local musicIcon = if getMusicIconFn then getMusicIconFn() else nil
	local musicVisible = musicIcon ~= nil and type(musicIcon.isShown) == "function" and musicIcon:isShown()
	for _, buttonMap in ipairs({ refs.desktopButtons, refs.phoneButtons }) do
		local cinematicButton = buttonMap[BUTTONS.CINEMATIC_DOCK]
		if cinematicButton then
			cinematicButton.Visible = cinematicVisible
		end
		local musicButton = buttonMap[BUTTONS.MUSIC_PLAYER]
		if musicButton then
			musicButton.Visible = musicVisible
		end
		for buttonName, trigger in pairs(adoptedTriggers) do
			local button = buttonMap[buttonName]
			if button then
				button.Visible = trigger.allowed
			end
		end
	end
end

local function applyAdoptedTrigger(trigger: AdoptedTrigger)
	pcall(trigger.realSetEnabled, trigger.icon, trigger.allowed and not trigger.routed)
end

-- First guess from the StarterGui template so the icon does not flash on the strip during boot;
-- init() settles it from the menus actually resolved in PlayerGui.
local function templateHasRowInBothMenus(buttonName: string): boolean
	local cfg = Config.TopbarMenu
	local root = StarterGui:FindFirstChild(cfg.GUI_NAME)
	if not root then
		return false
	end
	for _, frameName in ipairs({ cfg.DESKTOP_FRAME_NAME, cfg.PHONE_FRAME_NAME }) do
		local frame = root:FindFirstChild(frameName)
		local row = if frame then frame:FindFirstChild(buttonName, true) else nil
		if not (row and row:IsA("TextButton")) then
			return false
		end
	end
	return true
end

-- Moves a topbar icon into the menu row `buttonName` when both menus (desktop + phone) carry that
-- row; a GUI without it keeps the icon on the strip exactly as before. The feature controllers keep
-- calling icon:setEnabled(allowed) — that now decides the row's visibility, and the icon stays off
-- the strip. The row opens it with icon:select(), which TopbarPlus honours on a disabled icon.
function TopMenuController.adoptTopbarTrigger(icon: any, buttonName: string)
	if not icon or type(icon.setEnabled) ~= "function" or adoptedTriggers[buttonName] then
		return
	end
	local trigger: AdoptedTrigger = {
		icon = icon,
		allowed = icon.isEnabled ~= false,
		routed = templateHasRowInBothMenus(buttonName),
		realSetEnabled = icon.setEnabled,
	}
	adoptedTriggers[buttonName] = trigger
	icon.setEnabled = function(self: any, enabled: boolean)
		local allowed = enabled == true
		if trigger.allowed ~= allowed then
			trigger.allowed = allowed
			applyLayoutVisibility()
		end
		applyAdoptedTrigger(trigger)
		return self
	end
	applyAdoptedTrigger(trigger)
end

local function setMenuFrameHiddenState(frame: GuiObject, shownPosition: UDim2)
	frame.Position = getMenuHiddenPosition(frame, shownPosition)
	if frame:IsA("CanvasGroup") then
		(frame :: CanvasGroup).GroupTransparency = 1
	end
end

local function disconnectClickOutside()
	if clickOutsideConnection then
		clickOutsideConnection:Disconnect()
		clickOutsideConnection = nil
	end
end

local function requestCloseMenu()
	if menuIconRef and type(menuIconRef.deselect) == "function" then
		pcall(function()
			menuIconRef:deselect()
		end)
	end
end

local function playBackdropIn()
	if animHelper then
		animHelper:presentBackdropEffects(BLUR_OPTIONS)
	end
end

local function playBackdropOut(onDone: (() -> ())?)
	if animHelper then
		animHelper:dismissBackdropEffects(BLUR_OPTIONS, onDone)
	elseif onDone then
		onDone()
	end
end

local function closeSettingsPanelIfOpen()
	local settingsUI = settingsUIRef
	local icons = iconsRef
	if not settingsUI or type(settingsUI.isVisible) ~= "function" or not settingsUI:isVisible() then
		return
	end
	if type(settingsUI.hide) == "function" then
		settingsUI:hide()
	end
	if icons and icons.settings and type(icons.settings.deselect) == "function" then
		pcall(function()
			icons.settings:deselect()
		end)
	end
end

local function safeSelect(icon: any)
	if icon and type(icon.select) == "function" then
		pcall(function()
			icon:select()
		end)
	end
end

local function openSettingsTab(tabKey: "profile" | "settings" | "event")
	local settingsUI = settingsUIRef
	local icons = iconsRef
	if not icons then
		return
	end
	if settingsUI and type(settingsUI.selectTab) == "function" then
		settingsUI:selectTab(tabKey)
	end
	if settingsUI and type(settingsUI.isVisible) == "function" and settingsUI:isVisible() then
		return
	end
	safeSelect(icons.settings)
end

local function hideMenuImmediate()
	if not refs then
		return
	end
	isOpen = false
	isAnimating = false
	menuAnimToken += 1
	stopMenuSprings()
	if animHelper then
		animHelper:cancelPanel(refs.desktopMenu)
		animHelper:cancelPanel(refs.phoneMenu)
	end

	local blur = Lighting:FindFirstChild(Config.TopbarMenu.BACKDROP_BLUR_NAME)
	if blur and blur:IsA("BlurEffect") then
		blur.Size = 0
		blur.Enabled = false
	end

	refs.desktopMenu.Visible = false
	refs.phoneMenu.Visible = false
	if desktopRestingPosition then
		refs.desktopMenu.Position = desktopRestingPosition
	end
	if phoneRestingPosition then
		refs.phoneMenu.Position = phoneRestingPosition
	end
	if refs.desktopMenu:IsA("CanvasGroup") then
		(refs.desktopMenu :: CanvasGroup).GroupTransparency = 0
	end
	if refs.phoneMenu:IsA("CanvasGroup") then
		(refs.phoneMenu :: CanvasGroup).GroupTransparency = 0
	end
	refs.root.Enabled = false
	disconnectClickOutside()
	LeaderstatsVisibilityService.popHidden()
end

local function applyMenuPosition(frame: GuiObject, resting: UDim2, xOffset: number)
	frame.Position = UDim2.new(resting.X.Scale, xOffset, resting.Y.Scale, resting.Y.Offset)
end

local function springMenuTo(opts: {
	frame: GuiObject,
	resting: UDim2,
	goalX: number,
	goalFade: number,
	onSettled: (() -> ())?,
})
	local frame = opts.frame
	local resting = opts.resting

	local startX = frame.Position.X.Offset
	local startXV = 0
	local startFade = if frame:IsA("CanvasGroup") then (frame :: CanvasGroup).GroupTransparency else 0
	local startFadeV = 0
	if menuPosSpring and menuPosSpring:isRunning() then
		startX = menuPosSpring:getPosition()
		startXV = menuPosSpring:getVelocity()
	end
	if menuFadeSpring and menuFadeSpring:isRunning() then
		startFade = menuFadeSpring:getPosition()
		startFadeV = menuFadeSpring:getVelocity()
	end

	menuAnimToken += 1
	local token = menuAnimToken
	stopMenuSprings()

	local settledPos = false
	local settledFade = not frame:IsA("CanvasGroup")
	local function tryFinish()
		if token ~= menuAnimToken then
			return
		end
		if not settledPos or not settledFade then
			return
		end
		stopMenuSprings()
		applyMenuPosition(frame, resting, opts.goalX)
		if frame:IsA("CanvasGroup") then
			(frame :: CanvasGroup).GroupTransparency = opts.goalFade
		end
		if opts.onSettled then
			opts.onSettled()
		end
	end

	if isReducedMotion() then
		settledPos = true
		settledFade = true
		tryFinish()
		return
	end

	menuPosSpring = UISpring.driveNumber({
		frequency = MotionPresets.sidebarSpringFrequency(),
		position = startX,
		velocity = startXV,
		goal = opts.goalX,
		posEpsilon = 0.35,
		velEpsilon = 8,
		onStep = function(value: number)
			if token ~= menuAnimToken then
				return
			end
			applyMenuPosition(frame, resting, value)
		end,
		onSettled = function()
			settledPos = true
			tryFinish()
		end,
	})

	if frame:IsA("CanvasGroup") then
		menuFadeSpring = UISpring.driveNumber({
			frequency = MotionPresets.sidebarFadeSpringFrequency(),
			position = startFade,
			velocity = startFadeV,
			goal = opts.goalFade,
			posEpsilon = 0.01,
			velEpsilon = 0.05,
			onStep = function(value: number)
				if token ~= menuAnimToken then
					return
				end
				(frame :: CanvasGroup).GroupTransparency = math.clamp(value, 0, 1)
			end,
			onSettled = function()
				settledFade = true
				tryFinish()
			end,
		})
	else
		tryFinish()
	end
end

local function hideMenu()
	if not refs or (not isOpen and not isAnimating) then
		return
	end
	-- Already closing — leave the in-flight spring alone.
	if isAnimating and not isOpen then
		return
	end

	isOpen = false
	isAnimating = true
	disconnectClickOutside()
	applyLayoutVisibility()

	local activeFrame = getActiveMenuFrame()
	if not activeFrame then
		hideMenuImmediate()
		return
	end

	local restingPosition = getRestingPosition(activeFrame)
	local hidden = getMenuHiddenPosition(activeFrame, restingPosition)
	if animHelper then
		animHelper:cancelPanel(activeFrame)
	end

	local closed = false
	local pending = 2
	local closeToken = 0
	local function finishClose()
		if closed then
			return
		end
		pending -= 1
		if pending > 0 then
			return
		end
		-- Ignore if a newer open/close animation superseded this close.
		if closeToken ~= menuAnimToken or isOpen then
			return
		end
		closed = true
		isAnimating = false
		activeFrame.Visible = false
		activeFrame.Position = restingPosition
		if activeFrame:IsA("CanvasGroup") then
			(activeFrame :: CanvasGroup).GroupTransparency = 0
		end
		if refs then
			refs.root.Enabled = false
		end
		LeaderstatsVisibilityService.popHidden()
	end

	springMenuTo({
		frame = activeFrame,
		resting = restingPosition,
		goalX = hidden.X.Offset,
		goalFade = 1,
		onSettled = function()
			if not isOpen then
				finishClose()
			end
		end,
	})
	closeToken = menuAnimToken
	playBackdropOut(function()
		if not isOpen then
			finishClose()
		end
	end)
end

local function showMenu()
	if not refs then
		log:warn("showMenu called before TopMenuController init finished")
		return
	end
	-- Already fully open.
	if isOpen and not isAnimating then
		return
	end
	-- Already opening — leave in-flight spring alone.
	if isOpen and isAnimating then
		return
	end

	closeSettingsPanelIfOpen()

	local wasClosing = isAnimating and not isOpen
	isOpen = true
	isAnimating = true
	if not wasClosing then
		LeaderstatsVisibilityService.pushHidden()
	end
	refs.root.Enabled = true
	if refs.root.DisplayOrder < 50 then
		refs.root.DisplayOrder = 50
	end

	applyLayoutVisibility()
	playBackdropIn()

	local activeFrame = getActiveMenuFrame()
	if not activeFrame then
		isAnimating = false
		return
	end

	local restingPosition = getRestingPosition(activeFrame)
	if not wasClosing then
		setMenuFrameHiddenState(activeFrame, restingPosition)
	end
	activeFrame.Visible = true

	-- ADR 0011: rows light up top to bottom behind the slide. Only on a real open — showMenu
	-- already returns early for an open menu, and the visibility refreshes never reach here.
	UIMotion.stagger(
		if activeFrame == refs.phoneMenu then refs.phoneRows else refs.desktopRows,
		rowFadeBases,
		0.035
	)

	if animHelper then
		animHelper:cancelPanel(activeFrame)
	end

	springMenuTo({
		frame = activeFrame,
		resting = restingPosition,
		goalX = restingPosition.X.Offset,
		goalFade = 0,
		onSettled = function()
			isAnimating = false
			activeFrame.Position = restingPosition
			-- LAZY_PANEL_ROWS builds ~970 Settings rows on first show; inside the Settings open tween
			-- that stalls its first frames. Build here instead, while the menu is at rest.
			local shell = settingsUIRef
			if shell and type(shell.ensureTabBuilt) == "function" then
				task.defer(pcall, function()
					shell:ensureTabBuilt("settings")
				end)
			end
			if activeFrame:IsA("CanvasGroup") then
				(activeFrame :: CanvasGroup).GroupTransparency = 0
			end
		end,
	})
end

local function isPointerInsideMenu(point: Vector2): boolean
	local activeFrame = getActiveMenuFrame()
	if isPointInsideGui(activeFrame, point) then
		return true
	end
	if menuIconRef then
		local widget = resolveTopbarWidget(menuIconRef)
		if isPointInsideGui(widget, point) then
			return true
		end
	end
	return false
end

local function connectClickOutside()
	disconnectClickOutside()
	clickOutsideConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isOpen or gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not isPointerInsideMenu(input.Position) then
			requestCloseMenu()
		end
	end)
end

local function closeMenuThen(action: () -> ())
	requestCloseMenu()
	action()
end

-- Section rows are UIListLayout children, so the row button itself cannot scale without resizing
-- what the layout reserves and shoving its siblings; UIMotion.canScale refuses it and scales the
-- row's icon in place instead (hover up, press down, inside a fixed-size slot). The dark card rows
-- also lift their fill a touch toward grey on hover (UIMotion.bindHoverTint); a row with a
-- transparent fill (the phone menu) keeps the icon lift only.
-- `action` is nil for a row that has nothing to open (the Community row with no invite
-- configured): it still gets the same feel as its neighbours, just no click handler.
-- Accent theme: a picked accent tints the hover lift toward it; Graphite keeps the grey lift.
local function accentHoverLift(rest: Color3): Color3?
	if AccentService.isDesign() then
		return nil
	end
	return rest:Lerp(AccentService.get().fill, 0.22)
end

-- Accent theme: the plain icon discs (white at high transparency, desktop menu) turn into a solid
-- disc of the accent — one flat colour, no gradient (owner 2026-10-08) — with the glyph in the
-- accent's on-fill colour (white; black on yellow). Multicolor gives each disc the colourful
-- gradient its phone-menu twin has; Graphite keeps the design. Discs that already have their own
-- UIGradient (phone menu) are left to AccentSurfaceTint.
local ICON_DISC_GRADIENT_NAME = "AccentDiscGradient"
local ICON_DISC_GRADIENT_ROTATION = 106
type IconDiscDesign = { color: Color3, transparency: number, gradient: UIGradient, twin: UIGradient? }
local iconDiscDesigns: { [GuiObject]: IconDiscDesign } = {}
local iconGlyphDesigns: { [ImageLabel]: Color3 } = {}

local function paintIconDiscs()
	local accent = AccentService.get()
	local design = AccentService.isDesign()
	local multicolor = AccentService.isMulticolor()
	local solid = if design then nil else accent.fill
	local glyphColor = if design then nil else accent.onFill
	for disc, saved in pairs(iconDiscDesigns) do
		local twin = saved.twin
		-- The twin may already be recoloured; its design value rides on the attribute.
		local twinDesign = if multicolor and twin
			then (twin:GetAttribute("AccentDesignColor") :: any) or twin.Color
			else nil
		-- A gradient only for Multicolor's twin colours; an accent is one flat fill.
		saved.gradient.Enabled = twinDesign ~= nil
		if twinDesign then
			saved.gradient.Color = twinDesign
		end
		disc.BackgroundColor3 = if twinDesign then Color3.new(1, 1, 1) else solid or saved.color
		disc.BackgroundTransparency = if twinDesign or solid then 0 else saved.transparency
		for _, glyph in ipairs(disc:GetChildren()) do
			local glyphDesign = if glyph:IsA("ImageLabel") then iconGlyphDesigns[glyph] else nil
			if glyphDesign then
				(glyph :: ImageLabel).ImageColor3 = if twinDesign then Color3.new(1, 1, 1) else glyphColor or glyphDesign
			end
		end
	end
end

local function twinGradient(twins: { [string]: GuiButton }?, buttonName: string): UIGradient?
	local twin = if twins then twins[buttonName] else nil
	local slot = if twin then twin:FindFirstChild("UIMotionIconSlot") else nil
	local disc = if slot then slot:FindFirstChildWhichIsA("ImageLabel") else nil
	return if disc then disc:FindFirstChildWhichIsA("UIGradient") else nil
end

local function collectIconDiscs(rows: { GuiObject }, twins: { [string]: GuiButton }?)
	for _, row in ipairs(rows) do
		for _, slot in ipairs(row:GetDescendants()) do
			if slot.Name == "UIMotionIconSlot" then
				for _, disc in ipairs(slot:GetChildren()) do
					if
						disc:IsA("GuiObject")
						and disc.BackgroundTransparency < 1
						and not disc:FindFirstChildWhichIsA("UIGradient")
						and iconDiscDesigns[disc] == nil
					then
						local gradient = Instance.new("UIGradient")
						gradient.Name = ICON_DISC_GRADIENT_NAME
						gradient.Rotation = ICON_DISC_GRADIENT_ROTATION
						gradient.Enabled = false
						gradient.Parent = disc
						iconDiscDesigns[disc] = {
							color = disc.BackgroundColor3,
							transparency = disc.BackgroundTransparency,
							gradient = gradient,
							twin = twinGradient(twins, slot.Parent and slot.Parent.Name or ""),
						}
						disc.Destroying:Connect(function()
							iconDiscDesigns[disc] = nil
						end)
						disc:SetAttribute(AccentSurfaceTint.NO_TINT_ATTRIBUTE, true)
						for _, glyph in ipairs(disc:GetChildren()) do
							if glyph:IsA("ImageLabel") and iconGlyphDesigns[glyph] == nil then
								iconGlyphDesigns[glyph] = glyph.ImageColor3
								glyph.Destroying:Connect(function()
									iconGlyphDesigns[glyph] = nil
								end)
							end
						end
					end
				end
			end
		end
	end
end

local function bindButton(button: GuiButton?, action: (() -> ())?)
	if not button then
		return
	end
	local row = button
	for _, connection in ipairs(UIMotion.bindPress(row)) do
		trackInitConnection(connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(row)) do
		trackInitConnection(connection)
	end
	for _, connection in ipairs(UIMotion.bindHoverTint(row, accentHoverLift)) do
		trackInitConnection(connection)
	end

	local icon = row:FindFirstChildWhichIsA("ImageLabel", true)
		or row:FindFirstChildWhichIsA("ImageButton", true)

	if not action then
		return
	end
	local onActivated = action
	trackInitConnection(button.Activated:Connect(function()
		UIMotion.spin(icon :: GuiObject?, 1)
		UIMotion.releaseHoverTint(row)
		if button:GetAttribute("KeepMenuOpen") == true then
			onActivated()
		else
			closeMenuThen(onActivated)
		end
	end))
end

local function trimString(value: string): string
	return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", ""))
end

-- Returns display text (discord.gg/...) and https URL for OpenBrowserWindow.
local function normalizeDiscordInvite(raw: string): (string, string)
	local s = trimString(raw)
	if s == "" then
		return "", ""
	end
	s = string.gsub(s, "^[Hh][Tt][Tt][Pp][Ss]?://", "")
	local lower = string.lower(s)
	if string.find(lower, "discord.gg/", 1, true) == nil and string.find(s, "/", 1, true) == nil then
		-- Invite code only → discord.gg/<code>
		s = "discord.gg/" .. s
	end
	return s, "https://" .. s
end

local function isDiscordInviteLabelText(text: string): boolean
	local lower = string.lower(text)
	return string.find(lower, "discord.gg", 1, true) ~= nil
		or string.find(lower, "yourlinkhere", 1, true) ~= nil
end

local function openDiscordInvite(url: string)
	if url == "" then
		return
	end
	local ok, err = pcall(function()
		GuiService:OpenBrowserWindow(url)
	end)
	if not ok then
		log:warn("Open Discord invite failed", { error = tostring(err), url = url })
	end
end

local function bindGuiObjectClick(target: GuiObject, action: () -> ())
	if target:IsA("GuiButton") then
		bindButton(target :: GuiButton, action)
		return
	end
	-- The invite chip is a Frame in a laid-out row: rotation is the one flourish a UIListLayout
	-- ignores, so it wiggles instead of popping.
	local chipIcon = target:FindFirstChildWhichIsA("ImageLabel", true)
	target.Active = true
	trackInitConnection(target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		UIMotion.wiggle(if chipIcon then chipIcon :: ImageLabel else target, 6)
		if target:GetAttribute("KeepMenuOpen") == true then
			action()
		else
			closeMenuThen(action)
		end
	end))
end

local function applyDiscordInvite(menuRoot: Instance)
	local branding = Config.Branding or {}
	local display, url = normalizeDiscordInvite(tostring(branding.DISCORD_INVITE or ""))

	for _, d in ipairs(menuRoot:GetDescendants()) do
		if d:IsA("TextLabel") and isDiscordInviteLabelText(d.Text) then
			if display ~= "" then
				d.Text = display
			end
		end
	end

	-- Section3 has TextButton CommunityButton (row) + Frame CommunityButton (link chip).
	local function visit(parent: Instance)
		for _, child in ipairs(parent:GetChildren()) do
			-- The Discord invite opens the browser without closing the top menu (KeepMenuOpen).
			if child.Name == BUTTONS.COMMUNITY and child:IsA("GuiObject") then
				local gui = child :: GuiObject
				if display == "" then
					-- Hide invite chip only (Frame), keep row label.
					if not gui:IsA("GuiButton") then
						gui.Visible = false
					else
						-- wireButtons skips COMMUNITY because its action lives here; with no
						-- invite configured this branch used to return without binding, which
						-- left the one section row in the sidebar with no press or hover.
						bindButton(gui :: GuiButton, nil)
					end
				else
					gui.Visible = true
					gui:SetAttribute("KeepMenuOpen", true)
					bindGuiObjectClick(gui, function()
						openDiscordInvite(url)
					end)
				end
			end
			visit(child)
		end
	end
	visit(menuRoot)
end

local function wireButtons(buttonMap: TopMenuGuiRefs.ButtonMap)
	local icons = iconsRef
	if not icons then
		return
	end

	bindButton(buttonMap[BUTTONS.SHOP], function()
		safeSelect(icons.shop)
	end)
	bindButton(buttonMap[BUTTONS.DONATIONS], function()
		safeSelect(icons.donation)
	end)
	bindButton(buttonMap[BUTTONS.GIFT], function()
		safeSelect(icons.gift)
	end)
	bindButton(buttonMap[BUTTONS.COUPLE], function()
		safeSelect(icons.couple)
	end)
	bindButton(buttonMap[BUTTONS.BROADCAST], function()
		safeSelect(icons.broadcast)
	end)
	bindButton(buttonMap[BUTTONS.SETTINGS], function()
		openSettingsTab("settings")
	end)
	bindButton(buttonMap[BUTTONS.CINEMATIC_DOCK], function()
		-- Permission / toast: CinematicDockController (server-gated authorize).
		safeSelect(icons.cinematic)
	end)
	bindButton(buttonMap[BUTTONS.PROFILE], function()
		openSettingsTab("profile")
	end)
	-- Event board (ADR 0015): both rows open the menu's Event tab; Quests scrolls to its quests.
	-- A menu without the EventTab design keeps the "coming soon" answer.
	local function hasEventTab(): boolean
		local settingsUI = settingsUIRef
		return settingsUI ~= nil and type(settingsUI.hasTab) == "function" and settingsUI:hasTab("event")
	end
	bindButton(buttonMap[BUTTONS.QUESTS], function()
		if not hasEventTab() then
			NotifService.info(Config.TopbarMenu.QUESTS_SOON_MESSAGE)
			return
		end
		openSettingsTab("event")
		EventBoardController.focusQuests()
	end)
	bindButton(buttonMap[BUTTONS.EVENT], function()
		if not hasEventTab() then
			NotifService.info(Config.TopbarMenu.EVENT_SOON_MESSAGE)
			return
		end
		openSettingsTab("event")
	end)
	bindButton(buttonMap[BUTTONS.ADMIN_PANEL], function()
		local trigger = adoptedTriggers[BUTTONS.ADMIN_PANEL]
		if trigger then
			safeSelect(trigger.icon)
		end
	end)
	-- Same as the topbar dropdown's "Music Player" item (toggles the panel).
	bindButton(buttonMap[BUTTONS.MUSIC_PLAYER], function()
		local musicIcon = if getMusicIconFn then getMusicIconFn() else nil
		if musicIcon and type(musicIcon.openPlayer) == "function" then
			musicIcon:openPlayer()
		end
	end)
end

function TopMenuController.init(deps: InitDeps)
	menuIconRef = deps.menuIcon
	iconsRef = deps.icons
	isCinematicVisibleFn = deps.isCinematicVisible
	getMusicIconFn = deps.getMusicIcon
	if deps.settingsUI ~= nil then
		settingsUIRef = deps.settingsUI
	end
	animHelper = AnimationHelper.new()

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local resolved: TopMenuGuiRefs.Refs? = nil
	local lastError: string? = nil
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return TopMenuGuiRefs.resolve(playerGui)
		end)
		if ok then
			resolved = result
			break
		end
		lastError = tostring(result)
		if attempt < 3 then
			task.wait(1)
		end
	end
	if not resolved then
		log:warn("Failed to resolve TopMenu GUI", { error = lastError })
		-- No menu to open them from: adopted icons go back on the strip.
		for _, trigger in pairs(adoptedTriggers) do
			trigger.routed = false
			applyAdoptedTrigger(trigger)
		end
		return
	end
	refs = resolved
	log:info("TopMenuController ready", { gui = refs.root:GetFullName() })

	desktopRestingPosition = refs.desktopMenu.Position
	phoneRestingPosition = refs.phoneMenu.Position

	local staleBackdrop = refs.root:FindFirstChild("TopMenuBackdrop")
	if staleBackdrop then
		staleBackdrop:Destroy()
	end

	refs.desktopMenu.Visible = false
	refs.phoneMenu.Visible = false
	for buttonName, trigger in pairs(adoptedTriggers) do
		trigger.routed = refs.desktopButtons[buttonName] ~= nil and refs.phoneButtons[buttonName] ~= nil
		applyAdoptedTrigger(trigger)
	end
	applyLayoutVisibility()

	wireButtons(refs.desktopButtons)
	wireButtons(refs.phoneButtons)
	-- Record the rows' designed transparencies once, before any cascade has touched them.
	for _, rows in ipairs({ refs.desktopRows, refs.phoneRows }) do
		local elements: { GuiObject } = {}
		for _, row in ipairs(rows) do
			table.insert(elements, row)
			for _, descendant in ipairs(row:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					table.insert(elements, descendant)
				end
			end
		end
		UIMotion.captureBases(elements, rowFadeBases)
	end
	applyDiscordInvite(refs.desktopMenu)
	applyDiscordInvite(refs.phoneMenu)
	collectIconDiscs(refs.desktopRows, refs.phoneButtons :: any)
	collectIconDiscs(refs.phoneRows, nil)
	paintIconDiscs()
	trackInitUnsub(AccentService.subscribe(paintIconDiscs))
	AccentSurfaceTint.attach(refs.root)

	local menuIcon = deps.menuIcon
	if menuIcon.selected and type(menuIcon.selected.Connect) == "function" then
		trackInitConnection(menuIcon.selected:Connect(function()
			showMenu()
			connectClickOutside()
		end))
	end
	if menuIcon.deselected and type(menuIcon.deselected.Connect) == "function" then
		trackInitConnection(menuIcon.deselected:Connect(function()
			hideMenu()
		end))
	end

	-- The menu's tab-level Back buttons (07-MenuGUI) hand control back to this
	-- top menu. `menuIcon:select()` fires this controller's own selected
	-- handler → showMenu(), whose closeSettingsPanelIfOpen() closes the menu
	-- panel first; the topbar icon label flips to its selected state and the
	-- open cascade + backdrop play exactly like a normal open. Wired here in
	-- init() (after every local function exists) rather than in setSettingsUI
	-- (which runs earlier, at SettingsController.init).
	bindBackToMainMenuFn = function()
		local settingsUI = settingsUIRef
		if settingsUI and type(settingsUI.bindBackToMainMenu) == "function" then
			settingsUI:bindBackToMainMenu(function()
				-- Closed here as well: showMenu would do it, but not when the top
				-- menu is somehow already open and the selected handler
				-- early-returns.
				closeSettingsPanelIfOpen()
				if menuIconRef and type(menuIconRef.select) == "function" then
					pcall(function()
						menuIconRef:select()
					end)
				end
			end)
		end
	end
	bindBackToMainMenuFn()

	local camera = workspace.CurrentCamera
	if camera and viewportConnection == nil then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen then
				applyLayoutVisibility()
			end
		end)
		trackInitConnection(viewportConnection)
	end

	-- Role may arrive after menu resolve; refresh CinematicDockButton visibility.
	if type(OverheadController.subscribeRoleChanged) == "function" then
		trackInitUnsub(OverheadController.subscribeRoleChanged(function(userId: number, _role: string?)
			if userId == player.UserId then
				applyLayoutVisibility()
			end
		end))
	end
	if type(OverheadController.subscribeOverheadCacheUpdated) == "function" then
		trackInitUnsub(OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
			if userId == nil or userId == player.UserId then
				applyLayoutVisibility()
			end
		end))
	end
end

function TopMenuController.destroy()
	disconnectClickOutside()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	menuAnimToken += 1
	stopMenuSprings()
	for _, conn in ipairs(_initConnections) do
		conn:Disconnect()
	end
	table.clear(_initConnections)
	for _, unsub in ipairs(_initUnsubs) do
		unsub()
	end
	table.clear(_initUnsubs)
end

return TopMenuController
