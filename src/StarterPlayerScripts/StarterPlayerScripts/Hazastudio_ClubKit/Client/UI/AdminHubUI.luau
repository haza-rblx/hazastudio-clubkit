--!strict
-- Client/UI/AdminHubUI.luau — binder for StarterGui/04-AdminHub shell.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local NotifService = require(script.Parent.Parent.Services.NotifService)

export type PlayerEntry = {
	userId: number,
	username: string,
	displayName: string,
	role: string?,
}

export type SheetFootButton = {
	text: string,
	primary: boolean?,
	onClick: () -> (),
}

local FONT_ASSET = "rbxassetid://" .. tostring(Config.TopbarMenu.FONT_ASSET_ID or 12187365364)
local DIM_TARGET_T = 0.45 -- HTML --dim rgba(0,0,0,0.55)

-- Top-header 2-SliderSelector tabs (Option1–5). Same shell as Music / Dance / Gift.
local FILTER_TAB_SPECS = {
	{ filter = "all", optionIndex = 1, label = "All", headerTitle = "Admin Panel" },
	{ filter = "utilities", optionIndex = 2, label = "Utilities", headerTitle = "Utilities" },
	{ filter = "access", optionIndex = 3, label = "Access", headerTitle = "Access" },
	{ filter = "identity", optionIndex = 4, label = "Identity", headerTitle = "Identity" },
	{ filter = "donations", optionIndex = 5, label = "Donations", headerTitle = "Donations" },
}

local FILTER_HEADER_TITLES: { [string]: string } = {}
for _, spec in ipairs(FILTER_TAB_SPECS) do
	FILTER_HEADER_TITLES[spec.filter] = spec.headerTitle
end

local function applyFilterTabLabel(button: TextButton, labelText: string)
	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = labelText
	else
		button.Text = labelText
	end
end

-- Tokens aligned to tools/prototypes/admin-hub-v1.html :root
local COLORS = {
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(160, 160, 160),
	faint = Color3.fromRGB(92, 92, 92),
	fill = Color3.fromRGB(255, 255, 255),
	panel = Color3.fromRGB(12, 12, 12),
	surface = Color3.fromRGB(20, 20, 20), -- --surface
	surfaceRaised = Color3.fromRGB(26, 26, 26),
	accent = Color3.fromRGB(10, 132, 255),
	danger = Color3.fromRGB(255, 59, 48),
	cta = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(10, 10, 10),
	ring = Color3.fromRGB(255, 255, 255),
	info = Color3.fromRGB(96, 165, 250),
	infoBg = Color3.fromRGB(96, 165, 250),
	ok = Color3.fromRGB(74, 222, 128),
	okBg = Color3.fromRGB(74, 222, 128),
	warn = Color3.fromRGB(251, 191, 36),
	warnBg = Color3.fromRGB(251, 191, 36),
	gBlue = Color3.fromRGB(59, 130, 246),
	gViolet = Color3.fromRGB(124, 58, 237),
	gPink = Color3.fromRGB(219, 39, 119),
	gRose = Color3.fromRGB(225, 29, 72),
	gAmber = Color3.fromRGB(217, 119, 6),
	gCyan = Color3.fromRGB(8, 145, 178),
	gGreen = Color3.fromRGB(34, 197, 94),
}

local SPACE = {
	s0 = 2,
	s1 = 4,
	micro = 6,
	s2 = 10,
	s3 = 14,
	s4 = 18,
	pad = 24,
	stack = 18,
	titleSub = 3,
	rSm = 10,
	rMd = 14,
	ctrl = 40,
	btn = 36,
	av = 40,
	ico = 42,
}

local ACTION_COLORS: { [string]: Color3 } = {
	bring = COLORS.gBlue,
	to = COLORS.gViolet,
	announce = COLORS.gAmber,
	ungravity = COLORS.gCyan,
	gravity = COLORS.gBlue,
	role = COLORS.gAmber,
	gift = COLORS.gPink,
	title = COLORS.gViolet,
	donate = COLORS.gRose,
	refresh = COLORS.gCyan,
	floatSpeed = COLORS.gCyan,
}

local function face(weight: Enum.FontWeight): Font
	return Font.new(FONT_ASSET, weight, Enum.FontStyle.Normal)
end

local function waitChild(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end
	return parent:WaitForChild(name, 5) or error("[AdminHubUI] missing " .. name)
end

local function clearChildren(parent: Instance, keepNames: { [string]: boolean }?)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UIPadding") or child:IsA("UIGridLayout") then
			continue
		end
		if keepNames and keepNames[child.Name] then
			continue
		end
		child:Destroy()
	end
end

-- Everything UIMotion could fade under `root` (it skips whatever has no transparency channel).
-- A designed value is recorded once per instance: a second capture while a fade is running
-- would bank the mid-fade value as the resting one, and the element would stay ghosted.
local function collectFadeTargets(root: Instance, bases: { [GuiObject]: number }): { GuiObject }
	local targets: { GuiObject } = {}
	local pending: { GuiObject } = {}
	-- Hidden subtrees stay out of it: SheetBody keeps the design masters that openSheet clones
	-- from, and a clone taken while its master was mid-fade would bank 1 as its resting value.
	local function onScreen(node: Instance): boolean
		local current: Instance? = node
		while current ~= nil and current ~= root do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			current = current.Parent
		end
		return true
	end
	local function consider(node: Instance)
		if node:IsA("GuiObject") and node.Visible and onScreen(node) then
			table.insert(targets, node)
			if bases[node] == nil then
				table.insert(pending, node)
			end
		end
	end
	consider(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		consider(descendant)
	end
	if #pending > 0 then
		UIMotion.captureBases(pending, bases)
	end
	return targets
end

local function makeLabel(parent: Instance, name: string, text: string, size: number, weight: Enum.FontWeight, color: Color3, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.FontFace = face(weight)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 0)
	if props then
		for k, v in pairs(props) do
			(label :: any)[k] = v
		end
	end
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string, props: { [string]: any }?): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = COLORS.text
	btn.TextSize = 13
	btn.FontFace = face(Enum.FontWeight.SemiBold)
	btn.BackgroundColor3 = COLORS.fill
	btn.BackgroundTransparency = 0.92
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.ZIndex = 6
	if props then
		for k, v in pairs(props) do
			(btn :: any)[k] = v
		end
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn
	btn.Parent = parent
	return btn
end

local AdminHubUI = {}
AdminHubUI.__index = AdminHubUI

function AdminHubUI.new(gui: ScreenGui)
	local self = setmetatable({}, AdminHubUI)

	self._gui = gui
	self._anim = AnimationHelper.new()
	self._mainWrapper = waitChild(gui, "MainWrapper") :: Frame
	local content = waitChild(self._mainWrapper, "02-MainContentWrapper") :: Frame
	self._content = content
	-- Inner content chrome (title + search). Close + section tabs live on the
	-- top shell header (MainWrapper.01-HeaderWrapper) after the sidebar redesign.
	local contentHeader = waitChild(content, "01-HeaderWrapper") :: Frame
	local shellHeader = waitChild(self._mainWrapper, "01-HeaderWrapper") :: Frame
	self._headerTitle = waitChild(contentHeader, "1-HeaderTitle") :: TextLabel
	self._searchInput = waitChild(waitChild(contentHeader, "02-SearchBox"), "Input") :: TextBox
	self._closeButton = waitChild(shellHeader, "3-CloseModalButton") :: TextButton
	self._gallery = waitChild(content, "02-GalleryScroll") :: ScrollingFrame
	self._dim = waitChild(content, "DimOverlay") :: Frame
	self._playerPopup = waitChild(content, "03-PlayerPopup") :: Frame
	self._actionPopup = waitChild(content, "04-ActionPopup") :: Frame

	self._popupTitle = waitChild(waitChild(self._playerPopup, "01-Header"), "1-Title") :: TextLabel
	-- Close may live on the popup root (current shell) or inside 01-Header (older layouts).
	local popupClose = self._playerPopup:FindFirstChild("CloseModalButton")
	if not (popupClose and popupClose:IsA("TextButton")) then
		popupClose = waitChild(waitChild(self._playerPopup, "01-Header"), "CloseModalButton")
	end
	self._popupClose = popupClose :: TextButton
	self._popupSearch = waitChild(waitChild(self._playerPopup, "02-SearchBox"), "Input") :: TextBox
	self._playerList = waitChild(self._playerPopup, "ScrollablePlayerList") :: ScrollingFrame
	self._playerCardTemplate = waitChild(self._playerList, "PlayerSelectorCard") :: TextButton

	self._sheetHead = waitChild(self._actionPopup, "SheetHead") :: Frame
	self._sheetIconCircle = waitChild(self._sheetHead, "IconCircle") :: Frame
	self._sheetIcon = self._sheetIconCircle:FindFirstChild("Icon") :: ImageLabel?
	self._sheetTitle = waitChild(self._sheetHead, "1-Title") :: TextLabel
	self._sheetClose = waitChild(self._sheetHead, "CloseModalButton") :: TextButton
	self._sheetBody = waitChild(self._actionPopup, "SheetBody") :: ScrollingFrame
	self._sheetFoot = waitChild(self._actionPopup, "SheetFoot") :: Frame
	self._targetTemplate = self._sheetBody:FindFirstChild("SelectedPlayerInfo") :: TextButton?

	-- Section tabs: Option1–5 under the top slider (same 2-SliderSelector + BackgroundPill shell as Music/Dance/Gift).
	local sliderOuter = waitChild(shellHeader, "2-SliderSelector") :: Frame
	self._sliderOuter = sliderOuter
	self._sidebar = SliderSelectorUtil.getOptionsContainer(sliderOuter) :: Frame
	self._backgroundPill = SliderSelectorUtil.getBackgroundPill(sliderOuter)
	self._tabButtons = {} :: { TextButton }

	local allButtons = SliderSelectorUtil.collectTabButtons(self._sidebar)
	for _, spec in ipairs(FILTER_TAB_SPECS) do
		local button = SliderSelectorUtil.resolveTabButton(self._sidebar, {
			optionIndex = spec.optionIndex,
			defaultLabel = spec.label,
		}, allButtons)
		if button then
			button.LayoutOrder = spec.optionIndex - 1
			button:SetAttribute("Filter", spec.filter)
			applyFilterTabLabel(button, spec.label)
			-- Keep hits transparent — selection is communicated by BackgroundPill, not button fill.
			button.BackgroundTransparency = 1
			table.insert(self._tabButtons, button)
		end
	end

	-- Legacy Toast frame in shell is unused — feedback goes through NotifService /
	-- GeneralNotificationCenter (99-NotificationCenter).
	local legacyToast = content:FindFirstChild("Toast")
	if legacyToast and legacyToast:IsA("GuiObject") then
		legacyToast.Visible = false
	end

	self._filter = "all"
	self._galleryQuery = ""
	self._playerQuery = ""
	self._players = {} :: { PlayerEntry }
	self._allowedActions = {} :: { [string]: boolean }
	self._floatSpeed = tonumber(Config.Gravity.DEFAULT_SPEED) or 3
	self._restoreSpeed = tonumber(Config.Gravity.DEFAULT_SPEED) or 3
	self._overlay = nil :: string?
	self._keepDim = false
	self._dimTween = nil :: Tween?
	self._greetingRole = "Player"
	self._footConnections = {} :: { RBXScriptConnection }
	-- Press/hover connections split by lifetime: player rows die on every re-render, sheet
	-- content dies on every openSheet, static chrome lives as long as the panel.
	self._rowConnections = {} :: { RBXScriptConnection }
	self._sheetConnections = {} :: { RBXScriptConnection }
	-- Designed transparency of every element UIMotion fades here. Strong keys on purpose (ADR 0011
	-- addendum, 2026-09-17): a weak entry is dropped while the element is alive, and the next capture
	-- would then record a mid-cascade transparency as the design. Rows and sheet content are cloned
	-- and destroyed, so their entries stay with this panel until it is destroyed — bytes per row.
	self._fadeBases = {} :: { [GuiObject]: number }
	self._filterIndex = 0
	self._galleryEmpty = false
	self._playerListEmpty = false
	self._playerListSignature = nil :: string?
	self._onPlayerPicked = nil :: ((PlayerEntry) -> ())?
	self._onAction = nil :: ((string) -> ())?
	self._onGear = nil :: ((string) -> ())?
	self._onFilter = nil :: ((string) -> ())?
	self._onClose = nil :: (() -> ())?
	self._connections = {} :: { RBXScriptConnection }

	self._playerCardTemplate.Visible = false
	if self._targetTemplate then
		self._targetTemplate.Visible = false
	end
	-- Hide SheetBody design masters (ActionId frames) so they don't flash before openSheet.
	for _, child in ipairs(self._sheetBody:GetChildren()) do
		if child:IsA("GuiObject") and type(child:GetAttribute("ActionId")) == "string" then
			child.Visible = false
		end
	end
	self._dim.Visible = false
	self._dim.Active = true
	self._dim.BackgroundTransparency = DIM_TARGET_T
	self._playerPopup.Visible = false
	self._actionPopup.Visible = false
	self._gui.Enabled = false
	self._mainWrapper.Visible = false

	self:_bindStatic()
	self:_bindPressFeedback()
	self:_syncGearLabels()
	self:setFilter("all")

	return self
end

-- Press squash + hover lift (ADR 0011), bound once per instance: the controller rebuilds a
-- sheet's chip row in place when the currency changes, and a second bind would stack two
-- squashes on one press. `into` decides how long the connections live — UIMotion's pair holds
-- a UserInputService connection that the instance's own Destroy cannot clean up.
function AdminHubUI:_bindPress(target: GuiObject?, into: { RBXScriptConnection }?)
	if not target or target:GetAttribute("AdminHubMotionBound") then
		return
	end
	target:SetAttribute("AdminHubMotionBound", true)
	local sink = into or self._connections
	for _, connection in ipairs(UIMotion.bindPress(target)) do
		table.insert(sink, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(target)) do
		table.insert(sink, connection)
	end
end

function AdminHubUI:_clearMotionConnections(list: { RBXScriptConnection })
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

function AdminHubUI:_bindPressFeedback()
	self:_bindPress(self._closeButton)
	self:_bindPress(self._popupClose)
	self:_bindPress(self._sheetClose)
	-- The two foot CTAs are place instances that outlive every sheet, so they are bound here
	-- rather than in setSheetFoot: a sheet that supplies only a primary would otherwise leave
	-- GhostButton unbound until some later sheet happened to fill both slots.
	for _, name in ipairs({ "GhostButton", "PrimaryButton" }) do
		local footButton = self._sheetFoot:FindFirstChild(name)
		if footButton and footButton:IsA("GuiButton") then
			self:_bindPress(footButton)
		end
	end
	for _, child in ipairs(self._sidebar:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("Filter") ~= nil then
			self:_bindPress(child)
		end
	end
	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and string.sub(desc.Name, 1, 11) == "ActionTile_" then
			self:_bindPress(desc)
			-- Tiles live in the place GUI for the panel's whole life, so their designed
			-- transparencies are captured here, once, before any stagger fades them.
			collectFadeTargets(desc, self._fadeBases)
			local gear = desc:FindFirstChild("GearButton")
			if gear and gear:IsA("GuiButton") then
				self:_bindPress(gear)
			end
		end
	end
end

function AdminHubUI:_snapHideModal(modal: Frame)
	self._anim:cancelPanel(modal)
	modal.Visible = false
	local scale = modal:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1
	end
end

-- The dim backdrop stays on its own pair of tweens rather than UIMotion: it is open/close
-- chrome (AnimationHelper's half of ADR 0011), the two halves arbitrate through one shared
-- self._dimTween handle, and _hideDim needs the Completed hook to drop Visible afterwards.
function AdminHubUI:_showDim()
	if self._dimTween then
		self._dimTween:Cancel()
		self._dimTween = nil
	end
	local fromTransparent = not self._dim.Visible or self._dim.BackgroundTransparency >= 0.98
	self._dim.Visible = true
	if fromTransparent then
		self._dim.BackgroundTransparency = 1
	end
	local tw = TweenService:Create(
		self._dim,
		MotionPresets.makeInfo(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = DIM_TARGET_T }
	)
	self._dimTween = tw
	tw:Play()
end

function AdminHubUI:_hideDim()
	if self._dimTween then
		self._dimTween:Cancel()
		self._dimTween = nil
	end
	if not self._dim.Visible then
		return
	end
	local tw = TweenService:Create(
		self._dim,
		MotionPresets.makeInfo(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	self._dimTween = tw
	tw.Completed:Once(function()
		if self._overlay == nil then
			self._dim.Visible = false
			self._dim.BackgroundTransparency = DIM_TARGET_T
		end
		if self._dimTween == tw then
			self._dimTween = nil
		end
	end)
	tw:Play()
end

function AdminHubUI:_forceCloseOverlays()
	self:_snapHideModal(self._playerPopup)
	self:_snapHideModal(self._actionPopup)
	if self._dimTween then
		self._dimTween:Cancel()
		self._dimTween = nil
	end
	self._dim.Visible = false
	self._dim.BackgroundTransparency = DIM_TARGET_T
	self._overlay = nil
	self._onPlayerPicked = nil
	self:_disconnectFoot()
	self:_clearMotionConnections(self._sheetConnections)
	self:_clearMotionConnections(self._rowConnections)
	clearChildren(self._sheetFoot, { GhostButton = true, PrimaryButton = true, UIListLayout = true, UIPadding = true, UICorner = true })
end

function AdminHubUI:_track(conn: RBXScriptConnection)
	table.insert(self._connections, conn)
	return conn
end

function AdminHubUI:_bindStatic()
	self:_track(self._closeButton.MouseButton1Click:Connect(function()
		if self._onClose then
			self._onClose()
		end
	end))
	self:_track(self._dim.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:closeOverlay()
		end
	end))
	self:_track(self._popupClose.MouseButton1Click:Connect(function()
		self:closePlayerPopup()
	end))
	self:_track(self._sheetClose.MouseButton1Click:Connect(function()
		self:closeSheet()
	end))
	self:_track(self._searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		self._galleryQuery = string.lower(string.gsub(self._searchInput.Text, "^%s*(.-)%s*$", "%1"))
		self:_applyFilterVisibility()
	end))
	self:_track(self._popupSearch:GetPropertyChangedSignal("Text"):Connect(function()
		self._playerQuery = string.lower(string.gsub(self._popupSearch.Text, "^%s*(.-)%s*$", "%1"))
		self:_renderPlayers()
	end))

	for _, child in ipairs(self._sidebar:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("Filter") ~= nil then
			local filter = tostring(child:GetAttribute("Filter"))
			self:_track(child.MouseButton1Click:Connect(function()
				self:setFilter(filter)
				if self._onFilter then
					self._onFilter(filter)
				end
			end))
		end
	end

	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and string.sub(desc.Name, 1, 11) == "ActionTile_" then
			local actionId = desc:GetAttribute("ActionId")
			if type(actionId) == "string" then
				-- A tile is only clickable while its action is allowed, so every press here is
				-- an accepted one: the tile's icon pops as the sheet comes up.
				local tileIconNode = desc:FindFirstChild("Icon", true)
				local tileIcon: GuiObject? = if tileIconNode and tileIconNode:IsA("GuiObject") then tileIconNode else nil
				self:_track(desc.MouseButton1Click:Connect(function()
					UIMotion.pop(tileIcon, 1.2)
					if self._onAction then
						self._onAction(actionId)
					end
				end))
				local gear = desc:FindFirstChild("GearButton")
				if gear and gear:IsA("TextButton") then
					local gearButton = gear
					self:_track(gear.MouseButton1Click:Connect(function()
						-- Rotation never touches layout, so the gear can spin where it sits.
						UIMotion.spin(gearButton, 1)
						if self._onGear then
							self._onGear(actionId)
						end
					end))
				end
			end
		end
	end
end

function AdminHubUI:bindClose(callback: () -> ())
	self._onClose = callback
end

function AdminHubUI:bindAction(callback: (string) -> ())
	self._onAction = callback
end

function AdminHubUI:bindGear(callback: (string) -> ())
	self._onGear = callback
end

function AdminHubUI:bindFilter(callback: (string) -> ())
	self._onFilter = callback
end

function AdminHubUI:setAllowedActions(allowed: { [string]: boolean })
	self._allowedActions = allowed
	self:_applyFilterVisibility()
end

function AdminHubUI:setFloatSpeed(speed: number)
	self._floatSpeed = speed
	self:_syncGearLabels()
end

function AdminHubUI:getFloatSpeed(): number
	return self._floatSpeed
end

function AdminHubUI:setRestoreSpeed(speed: number)
	self._restoreSpeed = speed
	self:_syncGearLabels()
end

function AdminHubUI:getRestoreSpeed(): number
	return self._restoreSpeed
end

-- Gear dials are the panel's only counters: a changed value rolls while the panel is on
-- screen, and snaps whenever it is hidden, fractional, or already showing the new number.
function AdminHubUI:_setDialValue(label: TextLabel, value: number)
	local text = tostring(value)
	if label.Text == text then
		return
	end
	local from = tonumber(label.Text)
	if from == nil or value % 1 ~= 0 or not self:isVisible() then
		label.Text = text
		return
	end
	UIMotion.countTo(label, from, value, 0.25)
end

function AdminHubUI:_syncGearLabels()
	-- Separate dials: Ungravity gear → float/rise speed, Gravity gear → drop intensity.
	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and string.sub(desc.Name, 1, 11) == "ActionTile_" then
			local gear = desc:FindFirstChild("GearButton")
			if not (gear and gear:IsA("TextButton")) then
				continue
			end
			local actionId = tostring(desc:GetAttribute("ActionId") or "")
			local value = if actionId == "gravity" then self._restoreSpeed else self._floatSpeed
			local label = gear:FindFirstChild("Value")
			if not (label and label:IsA("TextLabel")) then
				label = gear:FindFirstChildWhichIsA("TextLabel", true)
			end
			if label and label:IsA("TextLabel") then
				self:_setDialValue(label, value)
			elseif gear.Text == "" or tonumber(gear.Text) ~= nil then
				gear.Text = tostring(value)
			end
		end
	end
end

function AdminHubUI:setGreetingRole(role: string?)
	self._greetingRole = if type(role) == "string" and role ~= "" then role else "Player"
	self:_refreshHeaderTitle()
end

function AdminHubUI:_refreshHeaderTitle()
	local role = self._greetingRole or "Player"
	local displayName = Players.LocalPlayer.DisplayName
	self._headerTitle.Text = string.format("Hi, %s %s!", role, displayName)
end

function AdminHubUI:setFilter(filter: string)
	local previousIndex = self._filterIndex
	self._filter = filter
	local selectedButton: TextButton? = nil
	local index = 0
	for i, button in ipairs(self._tabButtons) do
		local isCurrent = tostring(button:GetAttribute("Filter")) == filter
		SliderSelectorUtil.setTabButtonSelected(button, isCurrent)
		button.BackgroundTransparency = 1
		if isCurrent then
			selectedButton = button
			index = i
		end
	end
	self._filterIndex = index
	if self._backgroundPill and selectedButton then
		task.defer(function()
			if selectedButton.Parent and self._backgroundPill and self._backgroundPill.Parent then
				SliderSelectorUtil.animateSlidingPill(self._backgroundPill, selectedButton, self._tabButtons)
			end
		end)
	end
	-- A real section switch, not show()'s re-assert of the current one: the gallery travels in
	-- from the side the new section sits on (slideIn moves content through equal and opposite
	-- UIPadding, so the scroll frame never changes size) and the chosen tab's label pops.
	local switched = index ~= 0 and previousIndex ~= 0 and index ~= previousIndex and self._mainWrapper.Visible
	if switched then
		UIMotion.slideIn(self._gallery, if index > previousIndex then 1 else -1)
		UIMotion.pop(UIMotion.scaleTargetOf(selectedButton :: TextButton), 1.12)
	end
	-- Keep designer greeting on 1-HeaderTitle (not section names).
	self:_refreshHeaderTitle()
	self:_applyFilterVisibility(switched)
end

function AdminHubUI:_tileMatchesQuery(tile: TextButton): boolean
	if self._galleryQuery == "" then
		return true
	end
	local title = tile:FindFirstChild("1-Title", true)
	local desc = tile:FindFirstChild("2-SubTitle", true)
	local titleText = if title and title:IsA("TextLabel") then string.lower(title.Text) else ""
	local descText = if desc and desc:IsA("TextLabel") then string.lower(desc.Text) else ""
	local id = string.lower(tostring(tile:GetAttribute("ActionId") or ""))
	return string.find(titleText, self._galleryQuery, 1, true) ~= nil
		or string.find(descText, self._galleryQuery, 1, true) ~= nil
		or string.find(id, self._galleryQuery, 1, true) ~= nil
end

-- `animate` is only ever true on a real re-render (a section switch or the panel opening),
-- never on a search keystroke or an allowed-actions echo from the server.
function AdminHubUI:_applyFilterVisibility(animate: boolean?)
	local shown: { GuiObject } = {}
	for _, section in ipairs(self._gallery:GetChildren()) do
		if not section:IsA("Frame") then
			continue
		end
		local grid = section:FindFirstChild("2-TileGrid")
		local anyVisible = false
		if grid then
			for _, tile in ipairs(grid:GetChildren()) do
				if tile:IsA("TextButton") and string.sub(tile.Name, 1, 11) == "ActionTile_" then
					local actionId = tostring(tile:GetAttribute("ActionId") or "")
					local groupId = tostring(tile:GetAttribute("GroupId") or "")
					local allowed = self._allowedActions[actionId] == true
					local groupOk = self._filter == "all" or groupId == self._filter
					local queryOk = self:_tileMatchesQuery(tile)
					local visible = allowed and groupOk and queryOk
					tile.Visible = visible
					if visible then
						anyVisible = true
						table.insert(shown, tile)
					end
				end
			end
		end
		section.Visible = anyVisible
	end
	-- A search that found nothing shakes the field that caused it — once, on the transition
	-- into empty, not on every keystroke of a long miss.
	local empty = #shown == 0 and self._galleryQuery ~= ""
	if empty ~= self._galleryEmpty then
		self._galleryEmpty = empty
		if empty and self._mainWrapper.Visible then
			UIMotion.wiggle(self._searchInput, 5)
		end
	end
	if animate then
		UIMotion.stagger(shown, self._fadeBases)
	end
end

function AdminHubUI:show()
	self._gui.Enabled = true
	self._mainWrapper.Visible = true
	-- Re-assert pill after layout is visible (same pattern as Dance/Music).
	self:setFilter(self._filter)
	self._anim:presentCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "AdminHubUIBlur",
		enableZoom = true,
	})
	-- Tiles cascade in under the panel's own pop (same pass that decides their visibility).
	self:_applyFilterVisibility(true)
end

function AdminHubUI:hide()
	self:_forceCloseOverlays()
	if not self._mainWrapper.Visible and not self._gui.Enabled then
		return
	end
	self._anim:dismissCenterPanel(self._mainWrapper, function()
		self._gui.Enabled = false
		self._mainWrapper.Visible = false
	end, {
		enableBlur = true,
		blurName = "AdminHubUIBlur",
		enableZoom = true,
	})
end

function AdminHubUI:isVisible(): boolean
	return self._gui.Enabled and self._mainWrapper.Visible
end

function AdminHubUI:getScreenGui(): ScreenGui
	return self._gui
end

function AdminHubUI:getMainWrapper(): Frame
	return self._mainWrapper
end

-- Prefer AdminHubController → NotifService. Kept as a thin alias so any leftover
-- UI-layer call still hits General Notification Center.
function AdminHubUI:toast(message: string, notifType: NotifService.NotifType?)
	if type(message) ~= "string" or message == "" then
		return
	end
	NotifService.show({
		message = message,
		notifType = notifType or "INFO",
		domain = "admin",
		title = "Admin Panel",
	})
end

function AdminHubUI:setPlayers(players: { PlayerEntry })
	self._players = players
	if self._overlay == "player" then
		self:_renderPlayers()
	end
end

function AdminHubUI:openPlayerPopup(title: string, onPick: (PlayerEntry) -> ())
	self._onPlayerPicked = onPick
	self._popupTitle.Text = title
	self._popupSearch.Text = ""
	self._playerQuery = ""
	-- A fresh open always cascades, even when the roster is the one we last rendered.
	self._playerListSignature = nil
	self:_renderPlayers()
	-- Switching from sheet → player: snap-hide sheet, keep dim
	if self._actionPopup.Visible then
		self:_snapHideModal(self._actionPopup)
		self:_disconnectFoot()
		clearChildren(self._sheetFoot, { GhostButton = true, PrimaryButton = true, UIListLayout = true, UIPadding = true, UICorner = true })
	end
	self._overlay = "player"
	self:_showDim()
	self._anim:presentDialog(self._playerPopup)
end

function AdminHubUI:closePlayerPopup(keepDim: boolean?)
	self._onPlayerPicked = nil
	if not self._playerPopup.Visible then
		if keepDim then
			self._overlay = "sheet"
		elseif self._overlay == "player" then
			self._overlay = nil
			self:_hideDim()
		end
		return
	end

	if keepDim then
		-- Transition into sheet: snap-hide so sheet can open immediately
		self:_snapHideModal(self._playerPopup)
		self._overlay = "sheet"
		return
	end

	self._overlay = nil
	self._anim:dismissDialog(self._playerPopup, function()
		if self._overlay == nil then
			self:_hideDim()
		end
	end)
end

function AdminHubUI:_renderPlayers()
	-- Rows are rebuilt from the template, so last render's press/hover connections go first.
	self:_clearMotionConnections(self._rowConnections)
	clearChildren(self._playerList, { PlayerSelectorCard = true })
	local q = self._playerQuery
	local entering: { GuiObject } = {}
	local ids: { string } = {}
	for _, entry in ipairs(self._players) do
		local hay = string.lower(entry.displayName .. " " .. entry.username)
		if q ~= "" and string.find(hay, q, 1, true) == nil then
			continue
		end
		local card = self._playerCardTemplate:Clone()
		card.Name = "PlayerCard_" .. tostring(entry.userId)
		card.Visible = true
		card.Parent = self._playerList
		-- Bases are captured at creation, before any stagger has touched this clone's labels.
		collectFadeTargets(card, self._fadeBases)
		table.insert(entering, card)
		table.insert(ids, tostring(entry.userId))
		local title = card:FindFirstChild("1-Title", true)
		local sub = card:FindFirstChild("2-SubTitle", true)
		local badge = card:FindFirstChild("RoleBadge")
		if title and title:IsA("TextLabel") then
			title.Text = entry.displayName
		end
		if sub and sub:IsA("TextLabel") then
			sub.Text = "@" .. entry.username
		end
		if badge and badge:IsA("TextLabel") then
			badge.Text = entry.role or "Player"
		end
		local avatarNode = card:FindFirstChild("PlayerProfilePicture")
		local avatar: ImageLabel? = if avatarNode and avatarNode:IsA("ImageLabel") then avatarNode else nil
		if avatar then
			local image = avatar
			task.spawn(function()
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(
						entry.userId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size48x48
					)
				end)
				if ok and type(url) == "string" and image.Parent then
					image.Image = url
					-- The headshot arrives long after the row did: fade it in on its own.
					UIMotion.tween(image, 0.22, { ImageTransparency = 0 })
				end
			end)
		end
		-- HTML .prow hover → fill-strong
		card.BackgroundColor3 = COLORS.fill
		card.BackgroundTransparency = 1
		card.MouseEnter:Connect(function()
			if card.Parent then
				UIMotion.tween(card, 0.14, { BackgroundTransparency = 0.94 })
			end
		end)
		card.MouseLeave:Connect(function()
			if card.Parent then
				UIMotion.tween(card, 0.18, { BackgroundTransparency = 1 })
			end
		end)
		self:_bindPress(card, self._rowConnections)
		card.MouseButton1Click:Connect(function()
			local cb = self._onPlayerPicked
			-- The chosen row's avatar pops before the popup travels away.
			UIMotion.pop(avatar, 1.18)
			self:closePlayerPopup(true)
			if cb then
				cb(entry)
			end
		end)
	end
	-- An empty search shakes the field; a roster the server merely echoed re-renders without
	-- re-cascading, so an open popup does not flicker every time a player joins.
	local empty = #entering == 0 and q ~= ""
	if empty ~= self._playerListEmpty then
		self._playerListEmpty = empty
		if empty and self._playerPopup.Visible then
			UIMotion.wiggle(self._popupSearch, 5)
		end
	end
	local signature = table.concat(ids, ",")
	if signature ~= self._playerListSignature then
		self._playerListSignature = signature
		UIMotion.stagger(entering, self._fadeBases)
	end
end

function AdminHubUI:_sheetBodyKeepNames(): { [string]: boolean }
	-- Preserve in-SheetBody design masters (ActionId frames) + SelectedPlayerInfo.
	-- Ephemeral SheetContent clones are destroyed on each open.
	local keep: { [string]: boolean } = { SelectedPlayerInfo = true }
	for _, child in ipairs(self._sheetBody:GetChildren()) do
		if child:IsA("GuiObject") and type(child:GetAttribute("ActionId")) == "string" then
			keep[child.Name] = true
			child.Visible = false
		end
	end
	if self._targetTemplate then
		self._targetTemplate.Visible = false
	end
	return keep
end

function AdminHubUI:_findActionTemplate(actionId: string): GuiObject?
	local templates = self._gui:FindFirstChild("ActionTemplates")
	if templates then
		local nested = templates:FindFirstChild(actionId, true)
		if nested and nested:IsA("GuiObject") and nested.Name == actionId then
			return nested
		end
	end
	-- Design-in-place: masters live directly under SheetBody (ActionId attr).
	local direct = self._sheetBody:FindFirstChild(actionId)
	if direct and direct:IsA("GuiObject") then
		return direct
	end
	return nil
end

function AdminHubUI:_findActionTile(actionId: string): TextButton?
	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and string.sub(desc.Name, 1, 11) == "ActionTile_" then
			if tostring(desc:GetAttribute("ActionId") or "") == actionId then
				return desc
			end
		end
	end
	return nil
end

function AdminHubUI:_applySheetChrome(chromeActionId: string)
	-- Match SheetHead IconCircle/Icon to the gallery ActionTile the user opened.
	local fallbackColor = ACTION_COLORS[chromeActionId] or COLORS.gBlue
	self._sheetIconCircle.BackgroundColor3 = fallbackColor

	local tile = self:_findActionTile(chromeActionId)
	if tile then
		local circle = tile:FindFirstChild("IconCircle", true)
		if circle and circle:IsA("GuiObject") then
			self._sheetIconCircle.BackgroundColor3 = circle.BackgroundColor3
			local tileIcon = circle:FindFirstChild("Icon")
			if tileIcon and (tileIcon:IsA("ImageLabel") or tileIcon:IsA("ImageButton")) then
				local sheetIcon = self._sheetIcon
				if not (sheetIcon and sheetIcon:IsA("ImageLabel")) then
					sheetIcon = self._sheetIconCircle:FindFirstChild("Icon") :: ImageLabel?
					self._sheetIcon = sheetIcon
				end
				if sheetIcon and sheetIcon:IsA("ImageLabel") and tileIcon.Image ~= "" then
					sheetIcon.Image = tileIcon.Image
				end
			end
		end
	end
end

function AdminHubUI:openSheet(
	actionId: string,
	title: string,
	buildBody: (GuiObject) -> (),
	footButtons: { SheetFootButton }?,
	chromeActionId: string?
)
	self._sheetTitle.Text = title
	self:_applySheetChrome(chromeActionId or actionId)
	-- The content that owned these is about to be destroyed and rebuilt.
	self:_clearMotionConnections(self._sheetConnections)
	clearChildren(self._sheetBody, self:_sheetBodyKeepNames())
	clearChildren(self._sheetFoot, { GhostButton = true, PrimaryButton = true, UIListLayout = true, UIPadding = true, UICorner = true })
	-- Prefer editable sheet masters (ActionTemplates/* or SheetBody/<actionId>).
	-- Fallback root is SheetBody itself for legacy script builders / places without templates.
	local contentRoot: GuiObject = self._sheetBody
	local template = self:_findActionTemplate(actionId)
	if template then
		local clone = template:Clone()
		clone.Name = "SheetContent"
		clone.Visible = true
		clone.Parent = self._sheetBody
		contentRoot = clone
		local attrTitle = clone:GetAttribute("SheetTitle")
		if type(attrTitle) == "string" and attrTitle ~= "" and (title == "" or title == "Action") then
			self._sheetTitle.Text = attrTitle
		end
	end
	buildBody(contentRoot)
	if footButtons then
		self:setSheetFoot(footButtons)
	end
	if self._playerPopup.Visible then
		self:_snapHideModal(self._playerPopup)
	end
	self._overlay = "sheet"
	self:_showDim()
	self._anim:presentDialog(self._actionPopup)
	-- The dialog travels first (dialogOpen snap + settle ≈ 0.39s since the 2026-09-16 feel pass;
	-- the 0.14 delay below is still well inside it, so the ordering is unchanged); its content
	-- drops in under that and fades up once the sheet has arrived. slideInVertical moves the
	-- content through equal and opposite UIPadding, so the sheet itself never changes size.
	UIMotion.fadeIn(collectFadeTargets(contentRoot, self._fadeBases), self._fadeBases, 0.14)
	UIMotion.slideInVertical(contentRoot, -1, 14)
	UIMotion.popIn(self._sheetIcon, 0.7)
end

function AdminHubUI:closeSheet(keepDim: boolean?)
	self:_disconnectFoot()
	clearChildren(self._sheetFoot, { GhostButton = true, PrimaryButton = true, UIListLayout = true, UIPadding = true, UICorner = true })
	if not self._actionPopup.Visible then
		if keepDim then
			-- stay dimmed for player popup
		elseif self._overlay == "sheet" then
			self._overlay = nil
			self:_hideDim()
		end
		return
	end

	if keepDim then
		self:_snapHideModal(self._actionPopup)
		return
	end

	self._overlay = nil
	self._anim:dismissDialog(self._actionPopup, function()
		if self._overlay == nil then
			self:_hideDim()
		end
	end)
end

function AdminHubUI:closeOverlay(force: boolean?)
	if force then
		self:_forceCloseOverlays()
		return
	end
	if self._overlay == "player" then
		self:closePlayerPopup()
	elseif self._overlay == "sheet" then
		self:closeSheet()
	end
end

function AdminHubUI:_disconnectFoot()
	if self._footConnections then
		for _, conn in ipairs(self._footConnections) do
			conn:Disconnect()
		end
		table.clear(self._footConnections)
	end
end

-- The first visible field the sheet is still waiting on, or nil when anything is filled in.
-- Amount wins the shake when a sheet has several empty boxes: it is the one the controller
-- refuses on, and the message beside it is usually optional.
function AdminHubUI:_emptySheetField(): TextBox?
	local candidate: TextBox? = nil
	-- Only boxes the admin can actually see: SheetBody also holds the hidden design masters,
	-- whose fields are always empty and would shake in place of the real one.
	local function onScreen(node: Instance): boolean
		local current: Instance? = node
		while current ~= nil and current ~= self._sheetBody do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			current = current.Parent
		end
		return true
	end
	for _, node in ipairs(self._sheetBody:GetDescendants()) do
		if node:IsA("TextBox") and node.Visible and onScreen(node) then
			if string.gsub(node.Text, "^%s*(.-)%s*$", "%1") ~= "" then
				return nil
			end
			if candidate == nil or node.Name == "Amount" then
				candidate = node
			end
		end
	end
	return candidate
end

-- A primary foot press is the sheet's commit: empty-handed, it shakes the field that is
-- missing; otherwise the sheet's own icon pops as the action goes out.
function AdminHubUI:_acknowledgePrimary()
	local field = self:_emptySheetField()
	if field then
		UIMotion.wiggle(field, 6)
		return
	end
	UIMotion.pop(self._sheetIcon, 1.2)
end

function AdminHubUI:setSheetFoot(buttons: { SheetFootButton })
	self:_disconnectFoot()
	self._footConnections = {} :: { RBXScriptConnection }

	local ghost = self._sheetFoot:FindFirstChild("GhostButton")
	local primary = self._sheetFoot:FindFirstChild("PrimaryButton")
	local useTemplateFoot = ghost and ghost:IsA("TextButton") and primary and primary:IsA("TextButton")

	if useTemplateFoot then
		local ghostBtn = ghost :: TextButton
		local primaryBtn = primary :: TextButton
		local secondaryDef: SheetFootButton? = nil
		local primaryDef: SheetFootButton? = nil
		for _, def in ipairs(buttons) do
			if def.primary == false then
				secondaryDef = def
			else
				primaryDef = def
			end
		end
		if #buttons == 1 and not secondaryDef then
			primaryDef = buttons[1]
		elseif #buttons >= 2 then
			-- Prefer last primary; first non-primary as ghost
			for _, def in ipairs(buttons) do
				if def.primary == true then
					primaryDef = def
				elseif def.primary == false then
					secondaryDef = def
				end
			end
			if not primaryDef then
				primaryDef = buttons[#buttons]
			end
			if not secondaryDef and #buttons >= 2 then
				secondaryDef = buttons[1]
			end
		end

		if secondaryDef then
			ghostBtn.Visible = true
			ghostBtn.Text = secondaryDef.text
			table.insert(
				self._footConnections,
				ghostBtn.MouseButton1Click:Connect(secondaryDef.onClick)
			)
		else
			ghostBtn.Visible = false
		end
		if primaryDef then
			local commit = primaryDef.onClick
			primaryBtn.Visible = true
			primaryBtn.Text = primaryDef.text
			table.insert(
				self._footConnections,
				primaryBtn.MouseButton1Click:Connect(function()
					self:_acknowledgePrimary()
					commit()
				end)
			)
		end
		return
	end

	clearChildren(self._sheetFoot)
	local count = #buttons
	for i, def in ipairs(buttons) do
		local isPrimary = def.primary == true or (def.primary == nil and i == count)
		-- HTML .cta flex:1 / .cta.ghost flex:0.55
		local flex = if count == 1 then 1 elseif isPrimary then 1 else 0.55
		local gapPad = if count > 1 then SPACE.s2 else 0
		local btn = makeButton(self._sheetFoot, "Foot_" .. tostring(i), def.text, {
			LayoutOrder = i,
			Size = UDim2.new(flex / (if count == 1 then 1 else 1.55), -gapPad, 1, 0),
			BackgroundColor3 = if isPrimary then COLORS.cta else COLORS.fill,
			BackgroundTransparency = if isPrimary then 0 else 0.94,
			TextColor3 = if isPrimary then COLORS.ink else COLORS.text,
			TextSize = 14,
			FontFace = face(if isPrimary then Enum.FontWeight.Bold else Enum.FontWeight.SemiBold),
		})
		local corner = btn:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(1, 0)
		end
		self:_bindPress(btn, self._sheetConnections)
		local commit = def.onClick
		table.insert(
			self._footConnections,
			btn.MouseButton1Click:Connect(function()
				if isPrimary then
					self:_acknowledgePrimary()
				end
				commit()
			end)
		)
	end
end

function AdminHubUI:showSelectedPlayer(parent: Instance, entry: PlayerEntry?, onChange: (() -> ())?)
	if not entry then
		return
	end

	local existing = parent:FindFirstChild("SelectedPlayerInfo")
	if existing and existing ~= self._targetTemplate then
		existing:Destroy()
	end

	local row: TextButton
	local template = self._targetTemplate
	if template and template:IsA("GuiButton") then
		-- Prefer the designer SheetBody/SelectedPlayerInfo chrome.
		row = template:Clone() :: TextButton
		row.Name = "SelectedPlayerInfo"
		row.Visible = true
		row.LayoutOrder = -10
		row.AutoButtonColor = onChange ~= nil
		row.Parent = parent
	else
		-- Legacy fallback if the place template is missing.
		row = makeButton(parent, "SelectedPlayerInfo", "", {
			Size = UDim2.new(1, 0, 0, SPACE.av + SPACE.s2 * 2),
			BackgroundColor3 = COLORS.fill,
			BackgroundTransparency = 0.94,
			Text = "",
			AutoButtonColor = onChange ~= nil,
			LayoutOrder = -10,
		})
		local corner = row:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, SPACE.rMd)
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, SPACE.s3)
		pad.PaddingRight = UDim.new(0, SPACE.s3)
		pad.PaddingTop = UDim.new(0, SPACE.s2)
		pad.PaddingBottom = UDim.new(0, SPACE.s2)
		pad.Parent = row
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, SPACE.s3)
		layout.Parent = row

		local avatarFb = Instance.new("ImageLabel")
		avatarFb.Name = "PlayerProfilePicture"
		avatarFb.BackgroundColor3 = COLORS.surfaceRaised
		avatarFb.BorderSizePixel = 0
		avatarFb.Size = UDim2.fromOffset(SPACE.av, SPACE.av)
		avatarFb.ImageTransparency = 1
		avatarFb.LayoutOrder = 1
		avatarFb.Parent = row
		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatarFb

		local info = Instance.new("Frame")
		info.Name = "TargetInfoWrapper"
		info.BackgroundTransparency = 1
		info.Size = UDim2.new(1, -(SPACE.av + 72), 1, 0)
		info.LayoutOrder = 2
		info.Parent = row
		local infoLay = Instance.new("UIListLayout")
		infoLay.FillDirection = Enum.FillDirection.Vertical
		infoLay.VerticalAlignment = Enum.VerticalAlignment.Center
		infoLay.Padding = UDim.new(0, SPACE.titleSub)
		infoLay.Parent = info
		makeLabel(info, "1-Title", entry.displayName, 14, Enum.FontWeight.Bold, COLORS.text, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, 0, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		makeLabel(info, "2-SubTitle", "@" .. entry.username, 12, Enum.FontWeight.Medium, COLORS.muted, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, 0, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		makeLabel(row, "ChangeButton", if onChange then "Change" else "", 12, Enum.FontWeight.SemiBold, COLORS.muted, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(56, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = 3,
		})
	end

	local title = row:FindFirstChild("1-Title", true)
	if title and title:IsA("TextLabel") then
		title.Text = entry.displayName
	end
	local sub = row:FindFirstChild("2-SubTitle", true)
	if sub and sub:IsA("TextLabel") then
		sub.Text = "@" .. entry.username
	end
	local change = row:FindFirstChild("ChangeButton", true)
	if change and change:IsA("TextLabel") then
		change.Visible = onChange ~= nil
	end

	local avatar = row:FindFirstChild("PlayerProfilePicture", true)
	if not (avatar and avatar:IsA("ImageLabel")) then
		avatar = row:FindFirstChild("Avatar", true)
	end
	if avatar and avatar:IsA("ImageLabel") then
		local image = avatar
		image.ImageTransparency = 1
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(
					entry.userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
			end)
			if ok and type(url) == "string" and image.Parent then
				image.Image = url
				UIMotion.tween(image, 0.22, { ImageTransparency = 0 })
			end
		end)
	end

	if onChange then
		self:_bindPress(row, self._sheetConnections)
		row.MouseButton1Click:Connect(onChange)
	end
end

function AdminHubUI:addCallout(parent: Instance, text: string, variant: string?, title: string?)
	-- HTML .callout / .soft / .ok / .warn — tinted fill + accent dot
	local kind = variant or "soft"
	local bg = COLORS.fill
	local bgT = 0.96
	local accent = COLORS.text
	if kind == "soft" then
		bg = COLORS.infoBg
		bgT = 0.90
		accent = COLORS.info
	elseif kind == "ok" then
		bg = COLORS.okBg
		bgT = 0.90
		accent = COLORS.ok
	elseif kind == "warn" then
		bg = COLORS.warnBg
		bgT = 0.90
		accent = COLORS.warn
	end

	local box = Instance.new("Frame")
	box.Name = "Callout"
	box.BackgroundColor3 = bg
	box.BackgroundTransparency = bgT
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, SPACE.rMd)
	corner.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SPACE.s3)
	pad.PaddingBottom = UDim.new(0, SPACE.s3)
	pad.PaddingLeft = UDim.new(0, SPACE.s3)
	pad.PaddingRight = UDim.new(0, SPACE.s3)
	pad.Parent = box
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.Padding = UDim.new(0, SPACE.s2)
	lay.VerticalAlignment = Enum.VerticalAlignment.Top
	lay.Parent = box

	local dot = Instance.new("Frame")
	dot.Name = "Accent"
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = accent
	dot.BackgroundTransparency = 0
	dot.BorderSizePixel = 0
	dot.LayoutOrder = 1
	dot.Parent = box
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local col = Instance.new("Frame")
	col.Name = "Body"
	col.BackgroundTransparency = 1
	col.Size = UDim2.new(1, -18, 0, 0)
	col.AutomaticSize = Enum.AutomaticSize.Y
	col.LayoutOrder = 2
	col.Parent = box
	local colLay = Instance.new("UIListLayout")
	colLay.FillDirection = Enum.FillDirection.Vertical
	colLay.Padding = UDim.new(0, SPACE.s0)
	colLay.Parent = col
	if title and title ~= "" then
		makeLabel(col, "Title", title, 12, Enum.FontWeight.Bold, COLORS.text, {
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
		})
	end
	makeLabel(col, "Text", text, 12, Enum.FontWeight.Medium, COLORS.muted, {
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
	})
end

function AdminHubUI:addHint(parent: Instance, text: string)
	-- HTML .hint
	makeLabel(parent, "Hint", text, 12, Enum.FontWeight.Medium, COLORS.muted, {
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
	})
end

function AdminHubUI:addFieldLabel(parent: Instance, text: string)
	-- HTML .field label — uppercase faint
	makeLabel(parent, "FieldLabel", string.upper(text), 11, Enum.FontWeight.Bold, COLORS.faint, {
		Size = UDim2.new(1, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.None,
	})
end

function AdminHubUI:addPreview(parent: Instance, text: string): TextLabel
	-- HTML .preview amount well
	local well = Instance.new("Frame")
	well.Name = "PreviewWell"
	well.BackgroundColor3 = Color3.new(0, 0, 0)
	well.BackgroundTransparency = 0.55
	well.BorderSizePixel = 0
	well.Size = UDim2.new(1, 0, 0, SPACE.ctrl + SPACE.s4)
	well.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, SPACE.rMd)
	corner.Parent = well
	local label = makeLabel(well, "Preview", text, 18, Enum.FontWeight.ExtraBold, COLORS.text, {
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return label
end

function AdminHubUI:addTextBox(parent: Instance, name: string, placeholder: string, multiLine: boolean?): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = COLORS.fill
	box.BackgroundTransparency = 0.94
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = COLORS.faint
	box.Text = ""
	box.TextColor3 = COLORS.text
	box.TextSize = 14
	box.FontFace = face(Enum.FontWeight.Medium)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = if multiLine then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	box.MultiLine = multiLine == true
	box.TextWrapped = multiLine == true
	box.Size = UDim2.new(1, 0, 0, if multiLine then 72 else SPACE.ctrl)
	box.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, SPACE.rMd)
	corner.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, SPACE.s3)
	pad.PaddingRight = UDim.new(0, SPACE.s3)
	pad.PaddingTop = UDim.new(0, if multiLine then SPACE.s2 else 0)
	pad.PaddingBottom = UDim.new(0, if multiLine then SPACE.s2 else 0)
	pad.Parent = box
	return box
end

local PICK_ICON_COLORS: { [string]: Color3 } = {
	CoOwner = COLORS.gRose,
	Staff = COLORS.gAmber,
	Moderator = COLORS.gBlue,
	DJ = COLORS.gViolet,
	LeadDance = COLORS.gPink,
	Streamer = COLORS.gCyan,
	Influencer = COLORS.gGreen,
	Tier1 = COLORS.gPink,
	Tier2 = COLORS.gViolet,
	Tier3 = COLORS.gAmber,
	test = COLORS.gCyan,
	fake = COLORS.gCyan,
	credit = COLORS.gGreen,
	edit = COLORS.gAmber,
}

function AdminHubUI:addPickGrid(
	parent: Instance,
	options: { { key: string, label: string, desc: string?, color: Color3? } },
	initialKey: string,
	onChanged: (string) -> (),
	columns: number?
): () -> string
	-- HTML .pick-grid (2-col) / .mode-list (1-col)
	local cols = columns or 2
	local wrap = Instance.new("Frame")
	wrap.Name = "PickGrid"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.Parent = parent

	local picked = initialKey
	local buttons: { TextButton } = {}
	local cardH = if cols == 1 then 56 else 96

	-- The first pass paints the resting state instantly; later passes cross-fade the
	-- highlight, and a repeat of the current selection is not a pass at all.
	local synced: string? = nil
	local function sync()
		if synced == picked then
			return
		end
		local time = if synced == nil then 0 else 0.16
		synced = picked
		for _, btn in ipairs(buttons) do
			local key = tostring(btn:GetAttribute("PickKey") or "")
			local on = key == picked
			btn.BackgroundColor3 = COLORS.fill
			UIMotion.tween(btn, time, { BackgroundTransparency = if on then 0.90 else 0.96 })
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = COLORS.ring
				stroke.Thickness = 1.5
				UIMotion.tween(stroke, time, { Transparency = if on then 0 else 1 })
			end
		end
	end

	if cols >= 2 then
		local grid = Instance.new("UIGridLayout")
		grid.CellPadding = UDim2.fromOffset(SPACE.s2, SPACE.s2)
		grid.CellSize = UDim2.new(0.5, -SPACE.s2 / 2, 0, cardH)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.FillDirectionMaxCells = cols
		grid.Parent = wrap
	else
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, SPACE.micro)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = wrap
	end

	for i, opt in ipairs(options) do
		local btn = makeButton(wrap, "Pick_" .. opt.key, "", {
			Size = if cols >= 2 then UDim2.fromOffset(0, cardH) else UDim2.new(1, 0, 0, cardH),
			Text = "",
			BackgroundTransparency = 0.96,
			LayoutOrder = i,
		})
		btn:SetAttribute("PickKey", opt.key)
		local corner = btn:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, SPACE.rMd)
		end
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = COLORS.ring
		stroke.Transparency = 1
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, SPACE.s3)
		pad.PaddingBottom = UDim.new(0, SPACE.s3)
		pad.PaddingLeft = UDim.new(0, SPACE.s3)
		pad.PaddingRight = UDim.new(0, SPACE.s3)
		pad.Parent = btn

		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Size = UDim2.fromScale(1, 1)
		col.Parent = btn
		local colLay = Instance.new("UIListLayout")
		colLay.FillDirection = if cols == 1 then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		colLay.VerticalAlignment = Enum.VerticalAlignment.Center
		colLay.Padding = UDim.new(0, SPACE.s2)
		colLay.Parent = col

		local icoColor = opt.color or PICK_ICON_COLORS[opt.key] or COLORS.gAmber
		local ico = Instance.new("Frame")
		ico.Name = "IconCircle"
		ico.Size = UDim2.fromOffset(if cols == 1 then 32 else SPACE.ico, if cols == 1 then 32 else SPACE.ico)
		ico.BackgroundColor3 = icoColor
		ico.BorderSizePixel = 0
		ico.LayoutOrder = 1
		ico.Parent = col
		local icoCorner = Instance.new("UICorner")
		icoCorner.CornerRadius = UDim.new(1, 0)
		icoCorner.Parent = ico

		local textCol = Instance.new("Frame")
		textCol.BackgroundTransparency = 1
		textCol.Size = if cols == 1 then UDim2.new(1, -40, 1, 0) else UDim2.new(1, 0, 0, 0)
		textCol.AutomaticSize = if cols == 1 then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
		textCol.LayoutOrder = 2
		textCol.Parent = col
		local textLay = Instance.new("UIListLayout")
		textLay.FillDirection = Enum.FillDirection.Vertical
		textLay.VerticalAlignment = Enum.VerticalAlignment.Center
		textLay.Padding = UDim.new(0, SPACE.titleSub)
		textLay.Parent = textCol
		makeLabel(textCol, "T", opt.label, if cols == 1 then 12 else 14, Enum.FontWeight.Bold, COLORS.text, {
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, if cols == 1 then 16 else 18),
			AutomaticSize = Enum.AutomaticSize.None,
		})
		if opt.desc then
			makeLabel(textCol, "D", opt.desc, if cols == 1 then 10 else 12, Enum.FontWeight.Medium, COLORS.muted, {
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, 0, 0, if cols == 1 then 14 else 16),
				AutomaticSize = Enum.AutomaticSize.None,
			})
		end

		btn.MouseButton1Click:Connect(function()
			picked = opt.key
			sync()
			onChanged(picked)
		end)
		self:_bindPress(btn, self._sheetConnections)
		table.insert(buttons, btn)
	end
	sync()

	-- Keep wrap height in sync with grid
	if cols >= 2 then
		local rows = math.ceil(#options / cols)
		wrap.AutomaticSize = Enum.AutomaticSize.None
		wrap.Size = UDim2.new(1, 0, 0, rows * cardH + math.max(0, rows - 1) * SPACE.s2)
	end

	return function()
		return picked
	end
end

function AdminHubUI:addChipRow(
	parent: Instance,
	values: { string },
	initial: string,
	onChanged: (string) -> ()
): () -> string
	local wrap = Instance.new("Frame")
	wrap.Name = "ChipRow"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, SPACE.ctrl)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SPACE.s2)
	layout.Wraps = true
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = wrap

	local picked = initial
	local chips: { TextButton } = {}
	local synced: string? = nil
	local function sync()
		if synced == picked then
			return
		end
		local time = if synced == nil then 0 else 0.16
		synced = picked
		for _, chip in ipairs(chips) do
			local on = tostring(chip:GetAttribute("ChipValue") or chip.Text) == picked
			-- HTML .chip[aria-pressed] → white CTA / ink
			UIMotion.tween(chip, time, {
				BackgroundTransparency = if on then 0 else 0.94,
				BackgroundColor3 = if on then COLORS.cta else COLORS.fill,
				TextColor3 = if on then COLORS.ink else COLORS.muted,
			})
		end
	end
	for i, value in ipairs(values) do
		local chip = makeButton(wrap, "Chip_" .. value, value, {
			Size = UDim2.fromOffset(0, SPACE.ctrl),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 12,
			LayoutOrder = i,
			BackgroundTransparency = 0.94,
			FontFace = face(Enum.FontWeight.SemiBold),
		})
		chip:SetAttribute("ChipValue", value)
		local corner = chip:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(1, 0)
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, SPACE.s3)
		pad.PaddingRight = UDim.new(0, SPACE.s3)
		pad.Parent = chip
		chip.MouseButton1Click:Connect(function()
			picked = value
			sync()
			onChanged(picked)
		end)
		self:_bindPress(chip, self._sheetConnections)
		table.insert(chips, chip)
	end
	sync()
	return function()
		return picked
	end
end

function AdminHubUI:usesActionTemplate(root: GuiObject): boolean
	return root.Name == "SheetContent" or type(root:GetAttribute("ActionId")) == "string"
end

function AdminHubUI:findChipRowContaining(parent: Instance, chipValue: string): Frame?
	for _, node in ipairs(parent:GetDescendants()) do
		if node:IsA("Frame") and node.Name == "ChipRow" then
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("GuiButton") and tostring(child:GetAttribute("ChipValue") or "") == chipValue then
					return node
				end
			end
		end
	end
	return nil
end

function AdminHubUI:applyPickCardLabels(host: Instance, options: { { key: string, label: string, desc: string? } })
	for _, opt in ipairs(options) do
		local btn: TextButton? = nil
		local named = host:FindFirstChild("Pick_" .. opt.key, true)
		if named and named:IsA("TextButton") then
			btn = named
		else
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("TextButton") and tostring(d:GetAttribute("PickKey") or "") == opt.key then
					btn = d
					break
				end
			end
		end
		if not btn then
			continue
		end
		local title = btn:FindFirstChild("1-Title", true)
		if title and title:IsA("TextLabel") then
			title.Text = opt.label
		end
		if type(opt.desc) == "string" then
			local sub = btn:FindFirstChild("2-SubTitle", true)
			if sub and sub:IsA("TextLabel") then
				sub.Text = opt.desc
			end
		end
	end
end

function AdminHubUI:bindPickCards(
	host: Instance,
	initialKey: string,
	onChanged: (string) -> (),
	allowedKeys: { [string]: boolean }?
): () -> string
	local buttons: { TextButton } = {}
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("TextButton") then
			local key = d:GetAttribute("PickKey")
			if type(key) == "string" and key ~= "" then
				if allowedKeys and not allowedKeys[key] then
					d.Visible = false
				else
					d.Visible = true
					table.insert(buttons, d)
				end
			end
		end
	end

	local picked = initialKey
	local hasInitial = false
	for _, btn in ipairs(buttons) do
		if tostring(btn:GetAttribute("PickKey") or "") == picked then
			hasInitial = true
			break
		end
	end
	if not hasInitial and buttons[1] then
		picked = tostring(buttons[1]:GetAttribute("PickKey") or picked)
	end

	local synced: string? = nil
	local function sync()
		if synced == picked then
			return
		end
		local time = if synced == nil then 0 else 0.16
		synced = picked
		for _, btn in ipairs(buttons) do
			local key = tostring(btn:GetAttribute("PickKey") or "")
			local on = key == picked
			btn.BackgroundColor3 = COLORS.fill
			UIMotion.tween(btn, time, { BackgroundTransparency = if on then 0.90 else 0.96 })
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = COLORS.ring
				stroke.Thickness = 1.5
				UIMotion.tween(stroke, time, { Transparency = if on then 0 else 1 })
			end
		end
	end

	for _, btn in ipairs(buttons) do
		-- The designer's card icon pops when the card is chosen; UIMotion refuses the scale
		-- where the icon is laid out or inside a CanvasGroup, and the highlight carries it.
		local iconNode = btn:FindFirstChild("IconCircle", true)
		local icon: GuiObject? = if iconNode and iconNode:IsA("GuiObject") then iconNode else nil
		btn.MouseButton1Click:Connect(function()
			picked = tostring(btn:GetAttribute("PickKey") or picked)
			sync()
			UIMotion.pop(icon, 1.15)
			onChanged(picked)
		end)
		self:_bindPress(btn, self._sheetConnections)
	end
	sync()
	return function()
		return picked
	end
end

function AdminHubUI:bindChipRowTemplate(
	wrap: Frame,
	initial: string,
	onChanged: (string) -> (),
	allowedValues: { [string]: boolean }?
): () -> string
	local chips: { TextButton } = {}
	for _, child in ipairs(wrap:GetChildren()) do
		if child:IsA("TextButton") then
			local value = tostring(child:GetAttribute("ChipValue") or child.Text)
			if allowedValues and not allowedValues[value] then
				child.Visible = false
			else
				child.Visible = true
				table.insert(chips, child)
			end
		end
	end

	local picked = initial
	local hasInitial = false
	for _, chip in ipairs(chips) do
		if tostring(chip:GetAttribute("ChipValue") or chip.Text) == picked then
			hasInitial = true
			break
		end
	end
	if not hasInitial and chips[1] then
		picked = tostring(chips[1]:GetAttribute("ChipValue") or chips[1].Text)
	end

	local synced: string? = nil
	local function sync()
		if synced == picked then
			return
		end
		local time = if synced == nil then 0 else 0.16
		synced = picked
		for _, chip in ipairs(chips) do
			local on = tostring(chip:GetAttribute("ChipValue") or chip.Text) == picked
			UIMotion.tween(chip, time, {
				BackgroundTransparency = if on then 0 else 0.94,
				BackgroundColor3 = if on then COLORS.cta else COLORS.fill,
				TextColor3 = if on then COLORS.ink else COLORS.muted,
			})
		end
	end

	for _, chip in ipairs(chips) do
		chip.MouseButton1Click:Connect(function()
			picked = tostring(chip:GetAttribute("ChipValue") or chip.Text)
			sync()
			onChanged(picked)
		end)
		self:_bindPress(chip, self._sheetConnections)
	end
	sync()
	return function()
		return picked
	end
end

function AdminHubUI:fillChipRow(
	wrap: Frame,
	values: { string },
	initial: string,
	onChanged: (string) -> ()
): () -> string
	for _, child in ipairs(wrap:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local picked = initial
	local chips: { TextButton } = {}
	local synced: string? = nil
	local function sync()
		if synced == picked then
			return
		end
		local time = if synced == nil then 0 else 0.16
		synced = picked
		for _, chip in ipairs(chips) do
			local on = tostring(chip:GetAttribute("ChipValue") or chip.Text) == picked
			UIMotion.tween(chip, time, {
				BackgroundTransparency = if on then 0 else 0.94,
				BackgroundColor3 = if on then COLORS.cta else COLORS.fill,
				TextColor3 = if on then COLORS.ink else COLORS.muted,
			})
		end
	end
	for i, value in ipairs(values) do
		local chip = makeButton(wrap, "Chip_" .. value, value, {
			Size = UDim2.fromOffset(0, SPACE.ctrl),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 12,
			LayoutOrder = i,
			BackgroundTransparency = 0.94,
			FontFace = face(Enum.FontWeight.SemiBold),
		})
		chip:SetAttribute("ChipValue", value)
		local corner = chip:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(1, 0)
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, SPACE.s3)
		pad.PaddingRight = UDim.new(0, SPACE.s3)
		pad.Parent = chip
		chip.MouseButton1Click:Connect(function()
			picked = value
			sync()
			onChanged(picked)
		end)
		self:_bindPress(chip, self._sheetConnections)
		table.insert(chips, chip)
	end
	sync()
	return function()
		return picked
	end
end

function AdminHubUI:destroy()
	self:_disconnectFoot()
	self:_clearMotionConnections(self._rowConnections)
	self:_clearMotionConnections(self._sheetConnections)
	if self._dimTween then
		self._dimTween:Cancel()
		self._dimTween = nil
	end
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return AdminHubUI
