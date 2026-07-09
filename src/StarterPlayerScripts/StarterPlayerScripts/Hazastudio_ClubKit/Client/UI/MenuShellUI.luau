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
local MenuGuiRefs = require(script.Parent.MenuGuiRefs)
local ProfileTabBinder = require(script.Parent.ProfileTabBinder)
local SettingsTabBinder = require(script.Parent.SettingsTabBinder)

type SettingsPayload = Types.SettingsPayload
type ProfileMenuPayload = Types.ProfileMenuPayload
type OverheadPayload = Types.OverheadPayload

local SIDEBAR_HIDDEN_MARGIN = 24
local SIDEBAR_TWEEN_IN = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local SIDEBAR_TWEEN_OUT = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BLUR_OPTIONS = {
	enableBlur = true,
	blurName = Config.Settings.BACKDROP_BLUR_NAME,
}

local TAB_KEYS = { "profile", "settings" }

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

	refs.profileTab.Visible = true
	refs.settingsTab.Visible = false
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

	return self
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
		button.Activated:Connect(function()
			self:_selectTab(tabKey)
		end)
	end

	-- Dua tab terpisah di TabSwitcher: Profile + Settings (bukan satu tombol toggle).
	wireButton(buttons.profileButton, "profile")
	wireButton(buttons.settingsButton, "settings")
	wireButton(buttons.profileIdle, "profile")
	wireButton(buttons.profileActive, "profile")
	wireButton(buttons.settingsIdle, "settings")
	wireButton(buttons.settingsActive, "settings")

	self:_applyTabButtonStyles()
end

function MenuShellUI:_applyTabButtonStyles()
	local buttons = self._refs.tabButtons
	local isProfile = self._activeTabKey == "profile"
	local profileBtn = buttons.profileButton
	local settingsBtn = buttons.settingsButton

	if profileBtn then
		profileBtn.Visible = true
		if isProfile and self._tabActiveStyle then
			applyButtonVisual(profileBtn, self._tabActiveStyle)
		elseif self._tabIdleStyle then
			applyButtonVisual(profileBtn, self._tabIdleStyle)
		end
	end

	if settingsBtn then
		settingsBtn.Visible = true
		if not isProfile and self._tabActiveStyle then
			applyButtonVisual(settingsBtn, self._tabActiveStyle)
		elseif self._tabIdleStyle then
			applyButtonVisual(settingsBtn, self._tabIdleStyle)
		end
	end
end

function MenuShellUI:_selectTab(tabKey: string)
	if tabKey ~= "profile" and tabKey ~= "settings" then
		return
	end
	self:_hideProfileFieldModal(nil, true)
	self._activeTabKey = tabKey
	self._refs.profileTab.Visible = tabKey == "profile"
	self._refs.settingsTab.Visible = tabKey == "settings"
	self:_applyTabButtonStyles()

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
end

function MenuShellUI:ensureTabBuilt(tabKey: string)
	if tabKey == "settings" then
		self._settings:buildIfNeeded(self._settings:getPayload())
	end
end

function MenuShellUI:selectTab(tabKey: "profile" | "settings")
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
		refs.modalCancelButton.Activated:Connect(function()
			self:_hideProfileFieldModal()
		end)
	end
	if refs.modalUpdateButton then
		disableAutoButtonColor(refs.modalUpdateButton)
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

function MenuShellUI:_showProfileFieldModal(request: ProfileTabBinder.ProfileFieldModalRequest)
	local modal = self._refs.universalModal
	local input = self._refs.modalInput
	if not modal or not input then
		return
	end

	if not request.canEdit then
		if request.field == "specialTitle" then
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
	self._wrapperTween = TweenService:Create(wrapper, SIDEBAR_TWEEN_IN, wrapperTweenGoal)
	self._wrapperTween:Play()

	if not wasVisible then
		self._anim:presentBackdropEffects(BLUR_OPTIONS)
		self._backdropActive = true
		LeaderstatsVisibilityService.pushHidden()
	end

	self:_selectTab(self._activeTabKey)
	
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
	local wrapperTween = TweenService:Create(wrapper, SIDEBAR_TWEEN_OUT, wrapperTweenGoal)
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
	local gui = MenuGuiRefs.waitForPlayerGui(10)
	if not gui then
		warn("[MenuShellUI] GUI '07-MenuGUI' not found in PlayerGui")
		return createDisabledUI()
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
