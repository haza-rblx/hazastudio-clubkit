--!strict
-- 07-MenuGUI shell: show/hide, 2-tab switch, modal, facade for SettingsController.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local LeaderstatsVisibilityService = require(script.Parent.Parent.Services.LeaderstatsVisibilityService)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local MenuGuiRefs = require(script.Parent.MenuGuiRefs)
local ProfileTabBinder = require(script.Parent.ProfileTabBinder)
local CustomTitleUI = require(script.Parent.CustomTitleUI)
local FreeTitleEventUI = require(script.Parent.FreeTitleEventUI)
local SettingsTabBinder = require(script.Parent.SettingsTabBinder)

type SettingsPayload = Types.SettingsPayload
type ProfileMenuPayload = Types.ProfileMenuPayload
type OverheadPayload = Types.OverheadPayload

local SIDEBAR_HIDDEN_MARGIN = 24
local BLUR_OPTIONS = {
	enableBlur = true,
	blurName = Config.Settings.BACKDROP_BLUR_NAME,
}

-- Event is a third tab only where the menu has the EventTab design (ADR 0015).
local TAB_KEYS = { "profile", "settings", "event" }

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

local function getSidebarHiddenPosition(wrapper: GuiObject, shownPosition: UDim2): UDim2
	local width = wrapper.AbsoluteSize.X
	if width <= 0 then
		width = 360
	end
	return UDim2.new(
		shownPosition.X.Scale,
		shownPosition.X.Offset + width + SIDEBAR_HIDDEN_MARGIN,
		shownPosition.Y.Scale,
		shownPosition.Y.Offset
	)
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

local function setTextButtonText(button: TextButton, text: string)
	button.Text = text
	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label and label ~= button then
		label.Text = text
	end
end

local function disableAutoButtonColor(button: GuiButton)
	button.AutoButtonColor = false
end

local function asModalFrame(modal: GuiObject?): Frame?
	if modal and modal:IsA("Frame") then
		return modal :: Frame
	end
	return nil
end

local function resetModalVisual(modal: GuiObject?)
	if not modal then
		return
	end
	local uiScale = modal:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		uiScale.Scale = 1
	end
	modal.Visible = false
end

local function nameLooksActive(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "active", 1, true) ~= nil or string.find(lower, "selected", 1, true) ~= nil
end

local function nameLooksIdle(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "idle", 1, true) ~= nil or string.find(lower, "normal", 1, true) ~= nil
end

type TabStyleSnapshot = {
	backgroundColor3: Color3,
	backgroundTransparency: number,
	borderSizePixel: number,
	textColor3: Color3?,
	textTransparency: number?,
	items: { { path: string, className: string, props: { [string]: any } } },
}

local function relativePath(root: Instance, descendant: Instance): string
	local parts: { string } = {}
	local current: Instance? = descendant
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

local function findByRelativePath(root: Instance, path: string): Instance?
	if path == "" then
		return root
	end
	local current: Instance = root
	for token in string.gmatch(path, "[^/]+") do
		local nextInst = current:FindFirstChild(token)
		if not nextInst then
			return nil
		end
		current = nextInst
	end
	return current
end

local function captureButtonVisual(button: TextButton): TabStyleSnapshot
	local items: { { path: string, className: string, props: { [string]: any } } } = {}
	for _, descendant in ipairs(button:GetDescendants()) do
		local path = relativePath(button, descendant)
		if descendant:IsA("UIGradient") then
			table.insert(items, {
				path = path,
				className = "UIGradient",
				props = {
					Enabled = descendant.Enabled,
					Color = descendant.Color,
					Transparency = descendant.Transparency,
					Rotation = descendant.Rotation,
				},
			})
		elseif descendant:IsA("UIStroke") then
			table.insert(items, {
				path = path,
				className = "UIStroke",
				props = {
					Color = descendant.Color,
					Transparency = descendant.Transparency,
					Thickness = descendant.Thickness,
					Enabled = descendant.Enabled,
				},
			})
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = {
					TextColor3 = descendant.TextColor3,
					TextTransparency = descendant.TextTransparency,
					Visible = descendant.Visible,
				},
			})
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = {
					ImageColor3 = descendant.ImageColor3,
					ImageTransparency = descendant.ImageTransparency,
					Visible = descendant.Visible,
				},
			})
		elseif descendant:IsA("GuiObject") and (nameLooksActive(descendant.Name) or nameLooksIdle(descendant.Name)) then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = { Visible = (descendant :: GuiObject).Visible },
			})
		end
	end

	return {
		backgroundColor3 = button.BackgroundColor3,
		backgroundTransparency = button.BackgroundTransparency,
		borderSizePixel = button.BorderSizePixel,
		textColor3 = button.TextColor3,
		textTransparency = button.TextTransparency,
		items = items,
	}
end

local function applyButtonVisual(button: TextButton, snapshot: TabStyleSnapshot)
	button.BackgroundColor3 = snapshot.backgroundColor3
	button.BackgroundTransparency = snapshot.backgroundTransparency
	button.BorderSizePixel = snapshot.borderSizePixel
	if snapshot.textColor3 then
		button.TextColor3 = snapshot.textColor3
	end
	if snapshot.textTransparency ~= nil then
		button.TextTransparency = snapshot.textTransparency
	end

	for _, item in ipairs(snapshot.items) do
		local target = findByRelativePath(button, item.path)
		if target and target.ClassName == item.className then
			for prop, value in pairs(item.props) do
				(target :: any)[prop] = value
			end
		end
	end
end

local function hideTabStyleTemplate(button: TextButton?, primary: TextButton?)
	if button and primary and button ~= primary then
		button.Visible = false
	end
end

local MenuShellUI = {}
MenuShellUI.__index = MenuShellUI

function MenuShellUI.new(gui: ScreenGui)
	local refs = MenuGuiRefs.resolve(gui)
	if not refs then
		error("[MenuShellUI] Failed to resolve 07-MenuGUI v2 tree")
	end

	local self = setmetatable({}, MenuShellUI) :: any
	self._gui = gui
	self._refs = refs
	self._profile = ProfileTabBinder.new(refs)
	self._settings = SettingsTabBinder.new(refs)
	self._visible = false
	self._activeTabKey = "profile"
	self._currentProfilePayload = nil :: ProfileMenuPayload?
	self._currentOverheadPayload = nil :: OverheadPayload?
	self._changeCallback = nil
	self._profileChangeCallback = nil
	self._resetCallback = nil
	self._closeCallback = nil
	self._visibilityChangedCallback = nil
	self._activeModalField = nil :: string?
	self._wrapperTween = nil
	self._wrapperShownPosition = refs.outerWrapper.Position
	self._anim = AnimationHelper.new()
	self._backdropActive = false
	-- Designed transparencies for the open cascade, captured once per element. Strong keys on
	-- purpose (ADR 0011 addendum, 2026-09-17): a weak entry is dropped while the element is alive,
	-- and the next capture would then record a mid-cascade transparency as the design. A rebuilt
	-- settings section keeps its old entries here until the shell goes — bytes per element.
	self._fadeBases = {} :: { [GuiObject]: number }

	local tabButtons = refs.tabButtons
	self._tabIdleStyle = if tabButtons.profileIdle
		then captureButtonVisual(tabButtons.profileIdle)
		elseif tabButtons.settingsIdle
		then captureButtonVisual(tabButtons.settingsIdle)
		else nil
	self._tabActiveStyle = if tabButtons.settingsActive
		then captureButtonVisual(tabButtons.settingsActive)
		elseif tabButtons.profileActive
		then captureButtonVisual(tabButtons.profileActive)
		else nil
	self._clickOutsideConnection = nil :: RBXScriptConnection?

	hideTabStyleTemplate(tabButtons.profileActive, tabButtons.profileButton)
	hideTabStyleTemplate(tabButtons.settingsIdle, tabButtons.settingsButton)
	hideTabStyleTemplate(tabButtons.eventActive, tabButtons.eventButton)

	refs.profileTab.Visible = true
	refs.settingsTab.Visible = false
	if refs.eventTab then
		refs.eventTab.Visible = false
	end
	if refs.universalModal then
		refs.universalModal.Visible = false
	end

	gui.Enabled = false
	refs.outerWrapper.Visible = false
	if refs.outerWrapper:IsA("CanvasGroup") then
		(refs.outerWrapper :: CanvasGroup).GroupTransparency = 1
	end
	refs.outerWrapper.Position = getSidebarHiddenPosition(refs.outerWrapper, self._wrapperShownPosition)

	self:_wireTabs()
	self:_wireModal()
	self:_wireProfile()
	self:_wireFreeTitleEvent()

	return self
end

-- The event card is a second door to the custom title panel, so the shell owns it:
-- it already holds that panel and the payload the panel opens with. Resolved at
-- boot rather than lazily, because the card is meant to be on screen.
function MenuShellUI:_wireFreeTitleEvent()
	if Config.FeatureFlags.FreeTitleEventEnabled ~= true then
		return
	end
	if Config.FeatureFlags.SelfCustomTitleEnabled ~= true then
		warn("[MenuShellUI] FreeTitleEvent is on but SelfCustomTitle is off — the card has nothing to open")
		return
	end
	local playerGui = self._gui.Parent
	if not playerGui then
		return
	end

	local card = FreeTitleEventUI.tryCreate(playerGui)
	if not card then
		warn("[MenuShellUI] FreeTitleEvent is on but " .. Config.FreeTitleEvent.FRAME_NAME .. " is missing — no card")
		return
	end
	card:bindOpen(function()
		self:openCustomTitlePanel()
	end)
	self._freeTitleCard = card
	card:playEntrance()
end

-- Open the custom title panel from outside the profile menu (the event card).
-- Routed through the same request the profile row builds, so the level gate, the
-- quota message and the fallback to the text-only modal all behave identically.
function MenuShellUI:openCustomTitlePanel(): boolean
	local payload = self._currentProfilePayload
	if not payload then
		return false
	end
	self:_showProfileFieldModal({
		field = "specialTitle",
		title = "Title",
		currentValue = payload.specialTitle,
		canEdit = payload.canEditSpecialTitle == true,
	} :: any)
	return true
end

-- UIMotion hands back its press/hover connections; PressFeedback used to own them and drop
-- them when the button was destroyed, so keep exactly that contract (the hover pair also
-- holds a UserInputService connection that must not outlive the button).
function MenuShellUI:_bindButtonMotion(button: GuiObject)
	local connections = UIMotion.bindPress(button)
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(connections, connection)
	end
	if #connections == 0 then
		return
	end
	button.Destroying:Once(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end)
end

-- The active/idle swap repaints the whole tab button from a snapshot; fading its text and
-- icons back in turns that snap into a cross-fade. Bases are read straight after the
-- repaint, so they are always the designed values even on a second switch.
function MenuShellUI:_fadeTabButton(button: TextButton?)
	if not button then
		return
	end
	local elements: { GuiObject } = { button }
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			table.insert(elements, descendant)
		end
	end
	UIMotion.fadeIn(elements, UIMotion.captureBases(elements))
end

-- Rows of the page that is about to be shown cascade in. Bases are captured once per
-- element, at its designed transparency, so a second cascade never fades to invisible.
function MenuShellUI:_staggerTab(tab: ScrollingFrame)
	local bases = self._fadeBases
	local rows: { GuiObject } = {}
	local fresh: { GuiObject } = {}
	for _, child in ipairs(tab:GetChildren()) do
		if not child:IsA("GuiObject") or not child.Visible then
			continue
		end
		table.insert(rows, child)
		if bases[child] == nil then
			table.insert(fresh, child)
		end
		for _, descendant in ipairs(child:GetDescendants()) do
			if descendant:IsA("GuiObject") and bases[descendant] == nil then
				table.insert(fresh, descendant)
			end
		end
	end
	UIMotion.captureBases(fresh, bases)
	UIMotion.stagger(rows, bases)
end

function MenuShellUI:_wireTabs()
	local buttons = self._refs.tabButtons
	local wired: { [TextButton]: boolean } = {}

	local function wireButton(button: TextButton?, tabKey: string)
		if not button or wired[button] then
			return
		end
		wired[button] = true
		disableAutoButtonColor(button)
		self:_bindButtonMotion(button)
		button.Activated:Connect(function()
			self:_selectTab(tabKey)
		end)
	end

	-- Two separate tabs in TabSwitcher: Profile + Settings (not one toggle button).
	wireButton(buttons.profileButton, "profile")
	wireButton(buttons.settingsButton, "settings")
	wireButton(buttons.profileIdle, "profile")
	wireButton(buttons.profileActive, "profile")
	wireButton(buttons.settingsIdle, "settings")
	wireButton(buttons.settingsActive, "settings")
	if self._refs.eventTab then
		wireButton(buttons.eventButton, "event")
		wireButton(buttons.eventIdle, "event")
		wireButton(buttons.eventActive, "event")
	elseif buttons.eventButton then
		buttons.eventButton.Visible = false
	end

	self:_applyTabButtonStyles()
end

function MenuShellUI:_tabButton(tabKey: string): TextButton?
	local buttons = self._refs.tabButtons
	if tabKey == "profile" then
		return buttons.profileButton
	elseif tabKey == "settings" then
		return buttons.settingsButton
	end
	return if self._refs.eventTab then buttons.eventButton else nil
end

function MenuShellUI:_tabPage(tabKey: string): ScrollingFrame?
	if tabKey == "profile" then
		return self._refs.profileTab
	elseif tabKey == "settings" then
		return self._refs.settingsTab
	end
	return self._refs.eventTab
end

function MenuShellUI:_applyTabButtonStyles()
	for _, tabKey in ipairs(TAB_KEYS) do
		local button = self:_tabButton(tabKey)
		if button then
			button.Visible = true
			if self._activeTabKey == tabKey and self._tabActiveStyle then
				applyButtonVisual(button, self._tabActiveStyle)
			elseif self._tabIdleStyle then
				applyButtonVisual(button, self._tabIdleStyle)
			end
		end
	end
end

function MenuShellUI:_selectTab(tabKey: string)
	if not self:_tabPage(tabKey) then
		return
	end
	self:_hideProfileFieldModal(nil, true)
	local previousIndex = table.find(TAB_KEYS, self._activeTabKey)
	local nextIndex = table.find(TAB_KEYS, tabKey)
	local switched = previousIndex ~= nil and nextIndex ~= nil and previousIndex ~= nextIndex
	self._activeTabKey = tabKey
	for _, key in ipairs(TAB_KEYS) do
		local page = self:_tabPage(key)
		if page then
			page.Visible = key == tabKey
		end
	end
	self:_applyTabButtonStyles()
	if switched then
		self:_fadeTabButton(self:_tabButton(tabKey))
	end

	if tabKey == "settings" then
		self._settings:buildIfNeeded(self._settings:getPayload())
		self._settings:applyTabIdentity()
		local settingsPayload = self._settings:getPayload()
		if settingsPayload then
			self._settings:patchFromPayload(settingsPayload)
		end
	elseif tabKey == "profile" then
		self._profile:applyTabIdentity()
		if self._currentProfilePayload then
			self._profile:patchProfile(self._currentProfilePayload, self._currentOverheadPayload)
		end
		local localPlayer = game:GetService("Players").LocalPlayer
		if localPlayer then
			self._profile:ensureAvatarLoaded(localPlayer.UserId)
		end
	end

	-- Slide only on a real switch inside an open panel — opening plays the sidebar tween
	-- instead — and only after the page has been built and patched, so the settings tab
	-- owns its own UIPadding before UIMotion parks its slide padding beside it.
	if switched and self._visible then
		local page = self:_tabPage(tabKey) :: ScrollingFrame
		UIMotion.slideIn(page, if (nextIndex :: number) > (previousIndex :: number) then 1 else -1)
	end
end

function MenuShellUI:ensureTabBuilt(tabKey: string)
	if tabKey == "settings" then
		self._settings:buildIfNeeded(self._settings:getPayload())
	end
end

-- True when this menu has the tab (the event tab is optional GUI).
function MenuShellUI:hasTab(tabKey: string): boolean
	return self:_tabPage(tabKey) ~= nil
end

function MenuShellUI:selectTab(tabKey: "profile" | "settings" | "event")
	self:_selectTab(tabKey)
end

function MenuShellUI:_wireProfile()
	self._profile:bindProfileChange(function(field, value)
		if self._profileChangeCallback then
			self._profileChangeCallback(field, value)
		end
	end)
	self._profile:bindProfileFieldModal(function(request)
		self:_showProfileFieldModal(request)
	end)
end

function MenuShellUI:_wireModal()
	local refs = self._refs
	if refs.modalCancelButton then
		disableAutoButtonColor(refs.modalCancelButton)
		self:_bindButtonMotion(refs.modalCancelButton)
		refs.modalCancelButton.Activated:Connect(function()
			self:_hideProfileFieldModal()
		end)
	end
	if refs.modalUpdateButton then
		disableAutoButtonColor(refs.modalUpdateButton)
		self:_bindButtonMotion(refs.modalUpdateButton)
		refs.modalUpdateButton.Activated:Connect(function()
			self:_submitProfileFieldModal()
		end)
	end
	if refs.modalInput then
		refs.modalInput.ClearTextOnFocus = false
		refs.modalInput.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				self:_submitProfileFieldModal()
			end
		end)
	end
end

-- The self-service panel lives in its own buyer-installed ScreenGui, so it is
-- resolved lazily and only once: a place running the flag without the GUI keeps
-- the old modal instead of getting a button that does nothing.
function MenuShellUI:_getCustomTitleUI(): any?
	if self._customTitleResolved then
		return self._customTitle
	end
	self._customTitleResolved = true

	if Config.FeatureFlags.SelfCustomTitleEnabled ~= true then
		return nil
	end
	local playerGui = self._gui.Parent
	if not playerGui then
		return nil
	end

	local panel = CustomTitleUI.tryCreate(playerGui, self._anim)
	if not panel then
		warn("[MenuShellUI] SelfCustomTitle is on but " .. Config.CustomTitle.GUI_NAME .. " is missing — using the text-only modal")
		return nil
	end

	panel:bindSubmit(function(form)
		if self._profileChangeCallback then
			self._profileChangeCallback("customTitle", form)
		end
	end)
	panel:bindRemove(function()
		if self._profileChangeCallback then
			self._profileChangeCallback("customTitleRemove", true)
		end
	end)

	self._customTitle = panel
	return panel
end

function MenuShellUI:_showProfileFieldModal(request: ProfileTabBinder.ProfileFieldModalRequest)
	if request.field == "specialTitle" then
		local payload = self._currentProfilePayload
		if payload and (payload :: any).customTitleEnabled == true then
			local panel = self:_getCustomTitleUI()
			if panel then
				panel:open(payload)
				return
			end
		end
	end

	local modal = self._refs.universalModal
	local input = self._refs.modalInput
	if not modal or not input then
		return
	end

	if not request.canEdit then
		if request.field == "specialTitle" then
			-- Refused edit: the locked row shakes so the warning has a source on screen.
			-- Rotation, so the row stays put inside its UIListLayout.
			local locked = self._refs.specialTitleInput
			if locked then
				UIMotion.wiggle(locked.row, 5)
			end
			NotifService.warn(Config.ProfileMenu.MSG_TITLE_LOCKED)
		end
		return
	end

	self._activeModalField = request.field
	modal.Active = true

	if self._refs.modalTitle then
		self._refs.modalTitle.Text = request.title
	end
	if self._refs.modalUpdateButton then
		setTextButtonText(self._refs.modalUpdateButton, "Update")
	end
	if self._refs.modalCancelButton then
		setTextButtonText(self._refs.modalCancelButton, "Cancel")
	end

	input.TextEditable = true
	input.Text = request.currentValue or ""

	local modalFrame = asModalFrame(modal)
	if modalFrame then
		self._anim:cancelPanel(modalFrame)
		self._anim:presentCenterPanel(modalFrame, function()
			input:CaptureFocus()
		end)
		return
	end

	modal.Visible = true
	input:CaptureFocus()
end

function MenuShellUI:_hideProfileFieldModal(onDone: (() -> ())?, immediate: boolean?)
	local input = self._refs.modalInput
	if input then
		input:ReleaseFocus(false)
	end

	local modal = self._refs.universalModal
	self._activeModalField = nil

	if not modal then
		if onDone then
			onDone()
		end
		return
	end

	local modalFrame = asModalFrame(modal)
	if not modalFrame then
		resetModalVisual(modal)
		if onDone then
			onDone()
		end
		return
	end

	if immediate or not modalFrame.Visible then
		self._anim:cancelPanel(modalFrame)
		resetModalVisual(modalFrame)
		if onDone then
			onDone()
		end
		return
	end

	self._anim:dismissCenterPanel(modalFrame, function()
		resetModalVisual(modalFrame)
		if onDone then
			onDone()
		end
	end)
end

function MenuShellUI:_submitProfileFieldModal()
	local field = self._activeModalField
	local input = self._refs.modalInput
	if not field or not input then
		return
	end
	local nextValue = input.Text
	self:_hideProfileFieldModal(function()
		if self._profileChangeCallback then
			self._profileChangeCallback(field, nextValue)
			NotifService.success("Saved")
		end
		if self._currentProfilePayload then
			(self._currentProfilePayload :: any)[field] = nextValue
		end
		self._profile:patchProfileField(field, nextValue)
	end)
end

function MenuShellUI:bindChange(callback: (string, any) -> ())
	self._changeCallback = callback
	self._settings:bindChange(callback)
end

function MenuShellUI:setSliderDragHandler(field: string, callback: (boolean) -> ())
	self._settings:setSliderDragHandler(field, callback)
end

function MenuShellUI:bindProfileChange(callback: (string, any) -> ())
	self._profileChangeCallback = callback
end

function MenuShellUI:bindReset(callback: () -> ())
	self._resetCallback = callback
	self._settings:bindReset(callback)
end

function MenuShellUI:bindClose(callback: () -> ())
	self._closeCallback = callback
end

function MenuShellUI:bindVisibilityChanged(callback: (boolean) -> ())
	self._visibilityChangedCallback = callback
end

function MenuShellUI:_cancelMotionTweens()
	cancelTween(self._wrapperTween)
	self._wrapperTween = nil
end

function MenuShellUI:show()
	local wasVisible = self._visible
	self._visible = true
	self._profile:bindIfNeeded()

	if self._activeTabKey == "settings" then
		local settingsPayload = self._settings:getPayload()
		if settingsPayload then
			self:ensureTabBuilt("settings")
			self._settings:patchFromPayload(settingsPayload)
		end
	end
	if self._currentProfilePayload then
		self._profile:patchProfile(self._currentProfilePayload, self._currentOverheadPayload)
	end
	if self._activeTabKey == "profile" then
		local localPlayer = game:GetService("Players").LocalPlayer
		if localPlayer then
			self._profile:ensureAvatarLoaded(localPlayer.UserId)
		end
	end

	self:_cancelMotionTweens()
	local wrapper = self._refs.outerWrapper
	wrapper.Position = getSidebarHiddenPosition(wrapper, self._wrapperShownPosition)
	if wrapper:IsA("CanvasGroup") then
		(wrapper :: CanvasGroup).GroupTransparency = 1
	end

	self._gui.Enabled = true
	wrapper.Visible = true

	local wrapperTweenGoal = {
		Position = self._wrapperShownPosition,
	} :: { [string]: any }
	if wrapper:IsA("CanvasGroup") then
		wrapperTweenGoal.GroupTransparency = 0
	end
	self._wrapperTween = TweenService:Create(wrapper, MotionPresets.sidebarInInfo(), wrapperTweenGoal)
	self._wrapperTween:Play()

	if not wasVisible then
		self._anim:presentBackdropEffects(BLUR_OPTIONS)
		self._backdropActive = true
		LeaderstatsVisibilityService.pushHidden()
	end

	self:_selectTab(self._activeTabKey)

	-- Cascade the page in behind the sidebar tween, but only on a real open: re-showing an
	-- already-visible panel must not restart the fade under the player's cursor.
	if not wasVisible then
		self:_staggerTab(self:_tabPage(self._activeTabKey) :: ScrollingFrame)
	end

	-- Add click-outside detection
	if self._clickOutsideConnection then
		self._clickOutsideConnection:Disconnect()
	end
	
	self._clickOutsideConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not self._visible or gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		
		if not self:isPointerInsidePanel() then
			self:hide()
		end
	end)

	if not wasVisible and self._visibilityChangedCallback then
		self._visibilityChangedCallback(true)
	end
end

function MenuShellUI:hide()
	if not self._visible and not self._gui.Enabled then
		return
	end

	self:_hideProfileFieldModal(nil, true)
	self._visible = false
	self:_cancelMotionTweens()

	if self._backdropActive then
		self._backdropActive = false
		self._anim:dismissBackdropEffects(BLUR_OPTIONS)
	end
	
	-- Disconnect click-outside listener
	if self._clickOutsideConnection then
		self._clickOutsideConnection:Disconnect()
		self._clickOutsideConnection = nil
	end

	local wrapper = self._refs.outerWrapper
	local wrapperTweenGoal = {
		Position = getSidebarHiddenPosition(wrapper, self._wrapperShownPosition),
	} :: { [string]: any }
	if wrapper:IsA("CanvasGroup") then
		wrapperTweenGoal.GroupTransparency = 1
	end
	local wrapperTween = TweenService:Create(wrapper, MotionPresets.sidebarOutInfo(), wrapperTweenGoal)
	self._wrapperTween = wrapperTween
	wrapperTween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or self._visible then
			return
		end
		wrapper.Visible = false
		self._gui.Enabled = false
		LeaderstatsVisibilityService.popHidden()
		if self._visibilityChangedCallback then
			self._visibilityChangedCallback(false)
		end
	end)
	wrapperTween:Play()
end

function MenuShellUI:isVisible(): boolean
	return self._visible
end

function MenuShellUI:isPointerInsidePanel(): boolean
	return isPointInsideGui(self._refs.outerWrapper, UserInputService:GetMouseLocation())
end

function MenuShellUI:getPanelLeftScreenX(): number?
	if not self._refs.outerWrapper.Visible then
		return nil
	end
	return self._refs.outerWrapper.AbsolutePosition.X
end

function MenuShellUI:getRoot(): ScreenGui
	return self._gui
end

function MenuShellUI:isSettingsBuilt(): boolean
	return self._settings:isBuilt()
end

function MenuShellUI:isProfileBuilt(): boolean
	return true
end

function MenuShellUI:syncPayloadMirror(payload: SettingsPayload)
	self._settings:syncPayloadMirror(payload)
end

function MenuShellUI:setData(payload: SettingsPayload, options: { forceRebuild: boolean? }?)
	self._settings:setData(payload, options)
end

function MenuShellUI:patchFromPayload(payload: SettingsPayload)
	self._settings:patchFromPayload(payload)
end

function MenuShellUI:patchField(field: string, value: any)
	self._settings:patchField(field, value)
end

function MenuShellUI:setLocalOverheadData(payload: any)
	self._currentOverheadPayload = payload
	self._settings:setLocalOverheadData(payload)
	if self._currentProfilePayload then
		self._profile:patchProfile(self._currentProfilePayload, payload)
	end
end

function MenuShellUI:refreshOverheadConditionalItems()
	self._settings:refreshOverheadConditionalItems()
end

function MenuShellUI:patchProfileFromPayload(payload: ProfileMenuPayload, overhead: OverheadPayload?)
	self._currentProfilePayload = payload
	if overhead then
		self._currentOverheadPayload = overhead
	end
	self._profile:patchProfile(payload, self._currentOverheadPayload)
	-- The server echoes a fresh payload after every accepted or rejected update —
	-- and after admin actions and couple events too — so an open panel repaints its
	-- quota line and locked state from it. Deliberately *not* the form: the player
	-- may be mid-edit, and reloading their text and picks under them is exactly the
	-- "it snapped back to the old title" bug.
	if self._customTitle and self._customTitle:isOpen() then
		self._customTitle:applyPayload(payload)
	end
	-- The event card follows the same payload: the server decides who qualifies, the
	-- card only paints locked or open from that verdict.
	if self._freeTitleCard then
		self._freeTitleCard:applyState(payload)
	end
end

function MenuShellUI:setProfileData(payload: ProfileMenuPayload, options: { forceRebuild: boolean? }?)
	self:patchProfileFromPayload(payload, self._currentOverheadPayload)
end

function MenuShellUI:setAboutData(_playersByUserId: any?) end

function MenuShellUI:setPlayerListData(_playersByUserId: any?) end

local function createDisabledUI()
	local ui = {}
	function ui:bindChange() end
	function ui:bindProfileChange() end
	function ui:bindReset() end
	function ui:bindClose() end
	function ui:bindVisibilityChanged() end
	function ui:setData() end
	function ui:setLocalOverheadData() end
	function ui:setProfileData() end
	function ui:isSettingsBuilt(): boolean
		return false
	end
	function ui:isProfileBuilt(): boolean
		return false
	end
	function ui:patchFromPayload() end
	function ui:syncPayloadMirror() end
	function ui:patchField() end
	function ui:patchProfileFromPayload() end
	function ui:refreshOverheadConditionalItems() end
	function ui:setAboutData() end
	function ui:setPlayerListData() end
	function ui:show() end
	function ui:hide() end
	function ui:selectTab() end
	function ui:hasTab(): boolean
		return false
	end
	function ui:isVisible(): boolean
		return false
	end
	function ui:getPanelLeftScreenX(): number?
		return nil
	end
	function ui:getRoot(): Instance
		local created = Instance.new("ScreenGui")
		created.ResetOnSpawn = false
		return created
	end
	return ui
end

return function(_deps: {}?)
	-- The 10 s wait lost a race with the loading screen: `07-MenuGUI` is known to land
	-- ~30 s in on a cold boot (event-board fix, 2026-09-24), and a lost race here silently
	-- disabled the whole menu — including the FreeTitleEvent card's wiring. The GUI is
	-- StarterGui-cloned place data, so it always arrives — but "always" must stay
	-- observable: a buyer who deleted or renamed the GUI would otherwise hang this task
	-- forever with no trace. So: wait past the boot window, then warn once if it is still
	-- absent, then keep waiting. Slow boot = a late but working menu; missing GUI = a
	-- diagnosed one.
	local gui = MenuGuiRefs.waitForPlayerGui()
	if not gui then
		warn("[MenuShellUI] 07-MenuGUI has not arrived after the boot window — still waiting (deleting or renaming the GUI disables the menu entirely)")
	end
	while not gui do
		task.wait(1)
		gui = MenuGuiRefs.waitForPlayerGui()
	end

	local ok, shell = pcall(function()
		return MenuShellUI.new(gui)
	end)
	if not ok then
		warn("[MenuShellUI] " .. tostring(shell))
		return createDisabledUI()
	end
	return shell
end
