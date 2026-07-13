--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local LeaderstatsVisibilityService = require(script.Parent.Parent.Services.LeaderstatsVisibilityService)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)
local TopMenuGuiRefs = require(script.Parent.Parent.UI.TopMenuGuiRefs)

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
	isCinematicVisible: () -> boolean,
}

local MENU_SLIDE_IN = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local MENU_SLIDE_OUT = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MENU_HIDDEN_MARGIN = 24
local BLUR_OPTIONS = {
	enableBlur = true,
	blurName = Config.TopbarMenu.BACKDROP_BLUR_NAME,
}

local menuIconRef: any = nil
local iconsRef: IconsMap? = nil
local settingsUIRef: any = nil
local isCinematicVisibleFn: (() -> boolean)? = nil
local refs: TopMenuGuiRefs.Refs? = nil
local animHelper: AnimationHelper.AnimationHelper? = nil
local desktopRestingPosition: UDim2? = nil
local phoneRestingPosition: UDim2? = nil
local isOpen = false
local isAnimating = false
local menuTween: Tween? = nil
local clickOutsideConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil
local blockedMenuIcons: { [any]: boolean } = {}
local _initConnections: { RBXScriptConnection } = {}

local function trackInitConnection(conn: RBXScriptConnection)
	table.insert(_initConnections, conn)
end

local BUTTONS = Config.TopbarMenu.BUTTONS

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
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
			menuIcon:modifyTheme({
				{ "IconLabel", "FontFace", fontFace, "Selected" },
				{ "IconLabel", "Text", "X", "Selected" },
				{ "IconLabel", "TextSize", 20, "Selected" },
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

local function applyGatedButtonVisibility()
	if not refs or not isCinematicVisibleFn then
		return
	end

	local showCinematic = isCinematicVisibleFn()
	for _, buttonMap in ipairs({ refs.desktopButtons, refs.phoneButtons }) do
		local cinematicButton = buttonMap[BUTTONS.CINEMATIC_DOCK]
		if cinematicButton then
			cinematicButton.Visible = showCinematic
		end
	end
end

local function applyLayoutVisibility()
	if not refs then
		return
	end

	local isPhone = PhoneLayout.isPhoneLayout()
	refs.desktopMenu.Visible = (isOpen or isAnimating) and not isPhone
	refs.phoneMenu.Visible = (isOpen or isAnimating) and isPhone
	applyGatedButtonVisibility()
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

local function openSettingsTab(tabKey: "profile" | "settings")
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
	cancelTween(menuTween)
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
	refs.root.Enabled = false
	disconnectClickOutside()
	LeaderstatsVisibilityService.popHidden()
end

local function hideMenu()
	if not refs or (not isOpen and not isAnimating) then
		return
	end
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
	cancelTween(menuTween)
	if animHelper then
		animHelper:cancelPanel(activeFrame)
	end

	local tweenGoal = {
		Position = getMenuHiddenPosition(activeFrame, restingPosition),
	} :: { [string]: any }
	if activeFrame:IsA("CanvasGroup") then
		tweenGoal.GroupTransparency = 1
	end

	menuTween = TweenService:Create(activeFrame, MENU_SLIDE_OUT, tweenGoal)
	menuTween:Play()

	local closed = false
	local pending = 2
	local function finishClose()
		if closed then
			return
		end
		pending -= 1
		if pending > 0 then
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

	menuTween.Completed:Once(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			finishClose()
		end
	end)
	playBackdropOut(finishClose)
end

local function showMenu()
	if not refs then
		log:warn("showMenu called before TopMenuController init finished")
		return
	end
	if isOpen or isAnimating then
		return
	end

	closeSettingsPanelIfOpen()

	isOpen = true
	isAnimating = true
	LeaderstatsVisibilityService.pushHidden()
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
	setMenuFrameHiddenState(activeFrame, restingPosition)
	activeFrame.Visible = true

	cancelTween(menuTween)
	if animHelper then
		animHelper:cancelPanel(activeFrame)
	end

	local tweenGoal = {
		Position = restingPosition,
	} :: { [string]: any }
	if activeFrame:IsA("CanvasGroup") then
		tweenGoal.GroupTransparency = 0
	end

	menuTween = TweenService:Create(activeFrame, MENU_SLIDE_IN, tweenGoal)
	menuTween:Play()
	menuTween.Completed:Once(function(playbackState)
		isAnimating = false
		if playbackState == Enum.PlaybackState.Completed then
			activeFrame.Position = restingPosition
		end
	end)
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

local function bindButton(button: TextButton?, action: () -> ())
	if not button then
		return
	end
	button.Activated:Connect(function()
		closeMenuThen(action)
	end)
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
		if isCinematicVisibleFn and not isCinematicVisibleFn() then
			return
		end
		safeSelect(icons.cinematic)
	end)
	bindButton(buttonMap[BUTTONS.PROFILE], function()
		openSettingsTab("profile")
	end)
end

function TopMenuController.init(deps: InitDeps)
	menuIconRef = deps.menuIcon
	iconsRef = deps.icons
	if deps.settingsUI ~= nil then
		settingsUIRef = deps.settingsUI
	end
	isCinematicVisibleFn = deps.isCinematicVisible
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
	applyGatedButtonVisibility()

	wireButtons(refs.desktopButtons)
	wireButtons(refs.phoneButtons)

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

	local camera = workspace.CurrentCamera
	if camera and viewportConnection == nil then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen then
				applyLayoutVisibility()
			end
		end)
		trackInitConnection(viewportConnection)
	end
end

function TopMenuController.destroy()
	disconnectClickOutside()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	cancelTween(menuTween)
	menuTween = nil
	for _, conn in ipairs(_initConnections) do
		conn:Disconnect()
	end
	table.clear(_initConnections)
end

return TopMenuController
