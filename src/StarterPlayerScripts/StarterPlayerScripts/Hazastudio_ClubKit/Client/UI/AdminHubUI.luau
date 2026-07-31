--!strict
-- Client/UI/AdminHubUI.luau — binder for StarterGui/04-AdminHub shell.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local PressFeedback = require(script.Parent.Parent.Utils.PressFeedback)
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
	self._headerTitle = waitChild(waitChild(content, "01-HeaderWrapper"), "1-HeaderTitle") :: TextLabel
	self._searchInput = waitChild(waitChild(waitChild(content, "01-HeaderWrapper"), "02-SearchBox"), "Input") :: TextBox
	self._closeButton = waitChild(waitChild(content, "01-HeaderWrapper"), "3-CloseModalButton") :: TextButton
	self._gallery = waitChild(content, "02-GalleryScroll") :: ScrollingFrame
	self._dim = waitChild(content, "DimOverlay") :: Frame
	self._playerPopup = waitChild(content, "03-PlayerPopup") :: Frame
	self._actionPopup = waitChild(content, "04-ActionPopup") :: Frame

	self._popupTitle = waitChild(waitChild(self._playerPopup, "01-Header"), "1-Title") :: TextLabel
	self._popupClose = waitChild(waitChild(self._playerPopup, "01-Header"), "CloseModalButton") :: TextButton
	self._popupSearch = waitChild(waitChild(self._playerPopup, "02-SearchBox"), "Input") :: TextBox
	self._playerList = waitChild(self._playerPopup, "ScrollablePlayerList") :: ScrollingFrame
	self._playerCardTemplate = waitChild(self._playerList, "PlayerSelectorCard") :: TextButton

	self._sheetHead = waitChild(self._actionPopup, "SheetHead") :: Frame
	self._sheetIconCircle = waitChild(self._sheetHead, "IconCircle") :: Frame
	self._sheetTitle = waitChild(self._sheetHead, "1-Title") :: TextLabel
	self._sheetClose = waitChild(self._sheetHead, "CloseModalButton") :: TextButton
	self._sheetBody = waitChild(self._actionPopup, "SheetBody") :: ScrollingFrame
	self._sheetFoot = waitChild(self._actionPopup, "SheetFoot") :: Frame
	self._targetTemplate = self._sheetBody:FindFirstChild("SelectedPlayerInfo") :: TextButton?

	self._sidebar = waitChild(self._mainWrapper, "01-SidebarWrapper") :: Frame

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
	self._overlay = nil :: string?
	self._keepDim = false
	self._dimTween = nil :: Tween?
	self._pressHandles = {} :: { { Destroy: (self: any) -> () } }
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
	self:_applyFilterVisibility()

	return self
end

function AdminHubUI:_bindPress(target: GuiObject?)
	if not target then
		return
	end
	table.insert(self._pressHandles, PressFeedback.bindPressScale(target))
end

function AdminHubUI:_bindPressFeedback()
	self:_bindPress(self._closeButton)
	self:_bindPress(self._popupClose)
	self:_bindPress(self._sheetClose)
	for _, child in ipairs(self._sidebar:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("Filter") ~= nil then
			self:_bindPress(child)
		end
	end
	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and string.sub(desc.Name, 1, 11) == "ActionTile_" then
			self:_bindPress(desc)
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
	clearChildren(self._sheetFoot)
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
				self:_track(desc.MouseButton1Click:Connect(function()
					if self._onAction then
						self._onAction(actionId)
					end
				end))
				local gear = desc:FindFirstChild("GearButton")
				if gear and gear:IsA("TextButton") then
					self:_track(gear.MouseButton1Click:Connect(function()
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

function AdminHubUI:_syncGearLabels()
	for _, desc in ipairs(self._gallery:GetDescendants()) do
		if desc:IsA("TextButton") and desc.Name == "GearButton" then
			local label = desc:FindFirstChildWhichIsA("TextLabel", true)
			if label then
				label.Text = tostring(self._floatSpeed)
			elseif desc.Text == "" or tonumber(desc.Text) ~= nil then
				desc.Text = tostring(self._floatSpeed)
			end
		end
	end
end

function AdminHubUI:setFilter(filter: string)
	self._filter = filter
	for _, child in ipairs(self._sidebar:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("Filter") ~= nil then
			local isCurrent = tostring(child:GetAttribute("Filter")) == filter
			child.BackgroundTransparency = if isCurrent then 0 else 1
			child.BackgroundColor3 = if isCurrent then COLORS.accent else COLORS.fill
			local corner = child:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(1, 0)
			end
		end
	end
	local groupLabels = {
		all = "Admin Panel",
		utilities = "Utilities",
		access = "Access",
		identity = "Identity",
		donations = "Donations",
	}
	self._headerTitle.Text = groupLabels[filter] or "Admin Panel"
	self:_applyFilterVisibility()
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

function AdminHubUI:_applyFilterVisibility()
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
					end
				end
			end
		end
		section.Visible = anyVisible
	end
end

function AdminHubUI:show()
	self._gui.Enabled = true
	self._mainWrapper.Visible = true
	self._anim:presentCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "AdminHubUIBlur",
		enableZoom = true,
	})
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
	self:_renderPlayers()
	-- Switching from sheet → player: snap-hide sheet, keep dim
	if self._actionPopup.Visible then
		self:_snapHideModal(self._actionPopup)
		clearChildren(self._sheetFoot)
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
	clearChildren(self._playerList, { PlayerSelectorCard = true })
	local q = self._playerQuery
	for _, entry in ipairs(self._players) do
		local hay = string.lower(entry.displayName .. " " .. entry.username)
		if q ~= "" and string.find(hay, q, 1, true) == nil then
			continue
		end
		local card = self._playerCardTemplate:Clone()
		card.Name = "PlayerCard_" .. tostring(entry.userId)
		card.Visible = true
		card.Parent = self._playerList
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
		local avatar = card:FindFirstChild("PlayerProfilePicture")
		if avatar and avatar:IsA("ImageLabel") then
			task.spawn(function()
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(
						entry.userId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size48x48
					)
				end)
				if ok and type(url) == "string" and avatar.Parent then
					avatar.Image = url
					avatar.ImageTransparency = 0
				end
			end)
		end
		-- HTML .prow hover → fill-strong
		card.BackgroundColor3 = COLORS.fill
		card.BackgroundTransparency = 1
		card.MouseEnter:Connect(function()
			if card.Parent then
				card.BackgroundTransparency = 0.94
			end
		end)
		card.MouseLeave:Connect(function()
			if card.Parent then
				card.BackgroundTransparency = 1
			end
		end)
		PressFeedback.bindPressScale(card)
		card.MouseButton1Click:Connect(function()
			local cb = self._onPlayerPicked
			self:closePlayerPopup(true)
			if cb then
				cb(entry)
			end
		end)
	end
end

function AdminHubUI:openSheet(actionId: string, title: string, buildBody: (ScrollingFrame) -> (), footButtons: { SheetFootButton }?)
	self._sheetTitle.Text = title
	self._sheetIconCircle.BackgroundColor3 = ACTION_COLORS[actionId] or COLORS.gBlue
	clearChildren(self._sheetBody, { SelectedPlayerInfo = true })
	if self._targetTemplate then
		self._targetTemplate.Visible = false
	end
	clearChildren(self._sheetFoot)
	buildBody(self._sheetBody)
	if footButtons then
		self:setSheetFoot(footButtons)
	end
	if self._playerPopup.Visible then
		self:_snapHideModal(self._playerPopup)
	end
	self._overlay = "sheet"
	self:_showDim()
	self._anim:presentDialog(self._actionPopup)
end

function AdminHubUI:closeSheet(keepDim: boolean?)
	clearChildren(self._sheetFoot)
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

function AdminHubUI:setSheetFoot(buttons: { SheetFootButton })
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
		PressFeedback.bindPressScale(btn)
		btn.MouseButton1Click:Connect(def.onClick)
	end
end

function AdminHubUI:showSelectedPlayer(parent: Instance, entry: PlayerEntry?, onChange: (() -> ())?)
	if not entry then
		return
	end
	-- HTML .target chip
	local row = makeButton(parent, "SelectedPlayerInfoLive", "", {
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

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = COLORS.surfaceRaised
	avatar.BorderSizePixel = 0
	avatar.Size = UDim2.fromOffset(SPACE.av, SPACE.av)
	avatar.ImageTransparency = 1
	avatar.LayoutOrder = 1
	avatar.Parent = row
	local avCorner = Instance.new("UICorner")
	avCorner.CornerRadius = UDim.new(1, 0)
	avCorner.Parent = avatar

	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -(SPACE.av + 72), 1, 0)
	info.LayoutOrder = 2
	info.Parent = row
	local infoLay = Instance.new("UIListLayout")
	infoLay.FillDirection = Enum.FillDirection.Vertical
	infoLay.VerticalAlignment = Enum.VerticalAlignment.Center
	infoLay.Padding = UDim.new(0, SPACE.titleSub)
	infoLay.Parent = info
	makeLabel(info, "Title", entry.displayName, 14, Enum.FontWeight.Bold, COLORS.text, {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	makeLabel(info, "Sub", "@" .. entry.username, 12, Enum.FontWeight.Medium, COLORS.muted, {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	makeLabel(row, "Change", if onChange then "Change" else "", 12, Enum.FontWeight.SemiBold, COLORS.muted, {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(56, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 3,
	})

	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(entry.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and type(url) == "string" and avatar.Parent then
			avatar.Image = url
			avatar.ImageTransparency = 0
		end
	end)

	if onChange then
		PressFeedback.bindPressScale(row)
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

	local function sync()
		for _, btn in ipairs(buttons) do
			local key = tostring(btn:GetAttribute("PickKey") or "")
			local on = key == picked
			btn.BackgroundTransparency = if on then 0.90 else 0.96
			btn.BackgroundColor3 = COLORS.fill
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if on then 0 else 1
				stroke.Color = COLORS.ring
				stroke.Thickness = 1.5
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
		PressFeedback.bindPressScale(btn)
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
	local function sync()
		for _, chip in ipairs(chips) do
			local on = tostring(chip:GetAttribute("ChipValue") or chip.Text) == picked
			-- HTML .chip[aria-pressed] → white CTA / ink
			chip.BackgroundTransparency = if on then 0 else 0.94
			chip.BackgroundColor3 = if on then COLORS.cta else COLORS.fill
			chip.TextColor3 = if on then COLORS.ink else COLORS.muted
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
		PressFeedback.bindPressScale(chip)
		table.insert(chips, chip)
	end
	sync()
	return function()
		return picked
	end
end

function AdminHubUI:destroy()
	for _, handle in ipairs(self._pressHandles) do
		handle:Destroy()
	end
	table.clear(self._pressHandles)
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
