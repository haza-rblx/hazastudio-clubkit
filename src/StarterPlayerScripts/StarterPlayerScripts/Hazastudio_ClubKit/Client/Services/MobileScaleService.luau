--!strict
-- Client/Services/MobileScaleService.luau
-- Applies per-GUI UIScale values on touch-only (mobile) devices.
-- Call MobileScaleService.init(playerGui) once during bootstrap.
-- Uses ChildAdded so it handles GUIs that load asynchronously.
--
-- Hotbar: scales are applied to the HotbarWrapper child (it already has its own UIScale),
--   NOT to the root ScreenGui.
-- Loading screen: Content Size.Y and UIPadding.PaddingBottom are adjusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)
local ms = Config.MobileScale
local mpm = Config.MobilePanelManager

-- "IconGroup" is intentionally excluded here; it gets per-child scaling below.
local TOPBAR_PLUS_NAMES = { "TopbarPlusGui", "TopbarPlus", "TopbarPlusHolder", "TopbarIcons" }

-- Hotbar child frame names that each have their own UIScale.
local HOTBAR_FRAME_NAMES = { "HotbarWrapper" }

-- Root ScreenGui name → mobile UIScale value.
-- Hotbar root is intentionally excluded; handled per-child below.
local SCALE_MAP: { [string]: number } = {
	[mpm.COUPLE_GUI_NAME] = ms.COUPLE_GUI,
	[mpm.SHOP_GUI_NAME] = ms.SHOP_GUI,
	[Config.Gift.GUI_NAME] = ms.GIFT_GUI,
	[mpm.STREAK_GUI_NAME] = ms.STREAK_GUI,
	[Config.Music.GUI_NAME] = ms.MUSIC_GUI,
	[Config.Settings.GUI_NAME] = ms.MENU_GUI,
	[Config.Donation.GUI_NAME] = ms.DONATION_GUI,
	[Config.NotificationCenter.GUI_NAME] = ms.NOTIF_GUI,
	[Config.NotificationCenter.GUI_NAME_V2] = ms.NOTIF_GUI,
	[Config.CommandLibrary.GUI_NAME] = ms.COMMAND_GUI,
	[Config.Admin.GUI_NAME_V3] = ms.ADMIN_PANEL_V3_GUI,
	[Config.CustomTitle.GUI_NAME] = ms.CUSTOM_TITLE_GUI,
	["AvatarContextMenu"] = ms.ACM_GUI,
}

for _, name in ipairs(TOPBAR_PLUS_NAMES) do
	SCALE_MAP[name] = ms.ICON_GROUP
end

local MobileScaleService = {}

local function isPhoneLayout(): boolean
	return PhoneLayout.isPhoneLayout()
end

local function isMobile(): boolean
	return isPhoneLayout()
end

local function findMainContentWrapper(panel: Instance): GuiObject?
	local host = panel
	local mainWrapper = panel:FindFirstChild("MainWrapper")
	if mainWrapper and mainWrapper:IsA("GuiObject") then
		host = mainWrapper
	end
	local wrapper = host:FindFirstChild("03-MainContentWrapper")
	if wrapper and wrapper:IsA("GuiObject") then
		return wrapper :: GuiObject
	end
	return nil
end

local function applyMainContentHeight(panel: GuiObject, heightOffset: number): ()
	local mainContentWrapper = findMainContentWrapper(panel)
	if not mainContentWrapper then
		return
	end
	mainContentWrapper.Size = UDim2.new(mainContentWrapper.Size.X.Scale, mainContentWrapper.Size.X.Offset, 0, heightOffset)
end

local function getOrCreateRootScale(parent: Instance): UIScale
	local existing = parent:FindFirstChildWhichIsA("UIScale")
	if existing then
		return existing :: UIScale
	end
	local s = Instance.new("UIScale")
	s.Scale = 1
	s.Parent = parent
	return s
end

local function applyPaidBroadcastLayout(gui: Instance): ()
	local cfg = Config.PaidBroadcast
	local scale = if isPhoneLayout()
		then (tonumber(cfg.GUI_SCALE_MOBILE) or 0.75)
		else (tonumber(cfg.GUI_SCALE_DESKTOP) or 0.88)
	getOrCreateRootScale(gui).Scale = scale
end

local function applyAdminPanelLayout(gui: Instance): ()
	local cfg = Config.Admin
	local scale = if isPhoneLayout()
		then (tonumber(cfg.GUI_SCALE_MOBILE) or ms.ADMIN_GUI)
		else (tonumber(cfg.GUI_SCALE_DESKTOP) or cfg.GUI_SCALE_BAKED or 0.84)
	getOrCreateRootScale(gui).Scale = scale
end

local function applyAdminHubLayout(gui: Instance): ()
	local cfg = Config.Admin
	local scale = if isPhoneLayout()
		then (tonumber(cfg.HUB_GUI_SCALE_MOBILE) or ms.ADMIN_HUB_GUI)
		else (tonumber(cfg.HUB_GUI_SCALE_DESKTOP) or 0.88)
	getOrCreateRootScale(gui).Scale = scale
end

local function applyJoinCommunLayout(gui: Instance): ()
	local cfg = Config.JoinCommunityPrompt
	local scale = if isPhoneLayout()
		then (tonumber(cfg.GUI_SCALE_MOBILE) or ms.JOIN_COMMUN_GUI)
		else (tonumber(cfg.GUI_SCALE_DESKTOP) or 1)
	getOrCreateRootScale(gui).Scale = scale
end

local function applyBackpackLayout(gui: Instance): ()
	local cfg = Config.Backpack
	local wrapper = gui:FindFirstChild(cfg.WRAPPER_NAME, true)
	if wrapper and wrapper:IsA("GuiObject") then
		local scale = if isPhoneLayout()
			then (tonumber(cfg.GUI_SCALE_MOBILE) or ms.BACKPACK_GUI)
			else (tonumber(cfg.GUI_SCALE_DESKTOP) or ms.BACKPACK_GUI)
		getOrCreateRootScale(wrapper).Scale = scale
	end
end

-- Applies UIScale to the individual wrapper frames inside the hotbar root GUI.
local function applyHotbarChildScales(hotbarGui: Instance): ()
	for _, frameName in ipairs(HOTBAR_FRAME_NAMES) do
		local frame = hotbarGui:FindFirstChild(frameName)
		if frame ~= nil and frame:IsA("GuiObject") then
			local uiScale = getOrCreateRootScale(frame)
			uiScale.Scale = ms.HOTBAR_GUI
		end
	end
end

-- IconGroup: dance panel UIScale + MainContentWrapper height; root ScreenGui scale stays 1.
local function applyIconGroupLayout(iconGroupGui: Instance): ()
	if iconGroupGui:IsA("ScreenGui") then
		iconGroupGui.IgnoreGuiInset = Config.MobileScale.ICON_GROUP_IGNORE_GUI_INSET == true
	end

	local syncCfg = Config.Sync
	local mobile = isPhoneLayout()
	local useMobileLayout = syncCfg.DANCE_PANEL_USE_MOBILE_LAYOUT ~= false
	local roots = syncCfg.DANCE_PANEL_UI_ROOTS
	local v2Name = if type(roots) == "table" then roots.v2 else "DancePanelGUIWrapperv2"
	local v2MobileName = if type(roots) == "table" and type(roots.v2Mobile) == "string"
		then roots.v2Mobile
		else "DancePanelGUIWrapperv2Mobile"

	getOrCreateRootScale(iconGroupGui).Scale = 1

	local heightMobile = syncCfg.DANCE_MAIN_CONTENT_WRAPPER_HEIGHT_MOBILE
	local heightDesktop = syncCfg.DANCE_MAIN_CONTENT_WRAPPER_HEIGHT_DESKTOP

	local panelNames: { string } = {}
	if type(roots) == "table" then
		for _, panelName in pairs(roots) do
			if type(panelName) == "string" then
				table.insert(panelNames, panelName)
			end
		end
	end

	for _, panelName in ipairs(panelNames) do
		local panel = iconGroupGui:FindFirstChild(panelName)
		if panel == nil or not panel:IsA("GuiObject") then
			continue
		end
		local panelGui = panel :: GuiObject

		-- v3 has one layout. On phones it is scaled to fit the screen height and moved right of
			-- DancePanelButton; on desktop it keeps its authored size and position.
			if panelName == (if type(roots) == "table" then roots.v3 else "DancePanelGUIWrapperv3") then
				panelGui:SetAttribute("DancePanelPhoneScale", mobile)
				-- The open/close motion tweens this same UIScale; it settles here instead of at 1.
				panelGui:SetAttribute("UIScaleRest", if mobile then syncCfg.DANCE_PANEL_V3_SCALE_MOBILE else nil)
				-- Size and position are DancePanelUIBinder's (DancePanelV3Look.applyPhone), which also
				-- records the open position the panel returns to.
				if mobile then
					getOrCreateRootScale(panelGui).Scale = syncCfg.DANCE_PANEL_V3_SCALE_MOBILE
				end
				continue
			end

			local isV2Mobile = panelName == v2MobileName
		local isV2Desktop = panelName == v2Name

		if isV2Mobile then
			if mobile and useMobileLayout then
				applyMainContentHeight(panelGui, heightMobile)
			end
			continue
		end

		if isV2Desktop then
			if mobile and useMobileLayout then
				continue
			end
			getOrCreateRootScale(panelGui).Scale = if mobile
				then syncCfg.DANCE_PANEL_V2_SCALE_MOBILE
				else syncCfg.DANCE_PANEL_V2_SCALE_DESKTOP
			applyMainContentHeight(panelGui, if mobile then heightMobile else heightDesktop)
			continue
		end

		if panelName == (if type(roots) == "table" then roots.v1 else "DancePanelGUIWrapper") then
			getOrCreateRootScale(panelGui).Scale = ms.ICON_GROUP
		end
	end

	local trigger = iconGroupGui:FindFirstChild("DancePanelButton")
	if trigger ~= nil and trigger:IsA("GuiObject") then
		getOrCreateRootScale(trigger).Scale = 1
	end
end

-- Applies loading-screen mobile overrides:
--   ContentWrapper > Content: Size.X.Scale = 1 (full width)
--   ContentWrapper > Content > UIPadding: PaddingBottom = UDim.new(0, 12)
local function applyLoadingScreenFixes(loadingGui: Instance): ()
	local contentWrapper = loadingGui:FindFirstChild("ContentWrapper")
	if contentWrapper == nil then
		return
	end

	local content = contentWrapper:FindFirstChild("Content")
	if content == nil or not content:IsA("GuiObject") then
		return
	end

	local g = content :: GuiObject
	g.Size = UDim2.new(1, 0, g.Size.Y.Scale, g.Size.Y.Offset)

	local padding = content:FindFirstChildWhichIsA("UIPadding")
	if padding ~= nil then
		(padding :: UIPadding).PaddingBottom = UDim.new(0, 12)
	end
end

-- The music panel's fixed phone scale is too tall for short phones (measured 2026-09-23 on the
-- Galaxy A06 preset: the screen is 339 px tall, the panel 360 px at 0.56, so its top — the
-- tab bar — and its bottom were off screen and the tabs unreachable). The panel is centred in the
-- ScreenGui, so it fits when its design height times the scale fits the ScreenGui's height minus a
-- margin. Only sizes go in, never the panel's position (it moves while the open animation runs),
-- and the same sizes give the same scale, so the refit a resize triggers settles at once.
local MUSIC_EDGE_MARGIN = 8
local MUSIC_MIN_SCALE = 0.3
local fittedMusic: { [Instance]: boolean } = {}

local function fitMusicPanel(gui: Instance, base: number): ()
	local main = gui:FindFirstChild("MainWrapper")
	local uiScale = gui:FindFirstChildWhichIsA("UIScale")
	if not (main and main:IsA("GuiObject") and uiScale and gui:IsA("ScreenGui")) then
		return
	end
	local panel = main :: GuiObject
	local scale = uiScale :: UIScale
	local screen = gui :: ScreenGui
	local function fit()
		local height = panel.AbsoluteSize.Y
		local room = screen.AbsoluteSize.Y - 2 * MUSIC_EDGE_MARGIN
		if height <= 0 or room <= 0 or scale.Scale <= 0 then
			return
		end
		local designHeight = height / scale.Scale
		local wanted = math.clamp(room / designHeight, MUSIC_MIN_SCALE, base)
		if math.abs(scale.Scale - wanted) > 0.002 then
			scale.Scale = wanted
		end
	end
	if not fittedMusic[gui] then
		fittedMusic[gui] = true
		panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		gui.Destroying:Connect(function()
			fittedMusic[gui] = nil
		end)
	end
	task.defer(fit)
end

local function applyToGui(child: Instance): ()
	local name = child.Name

	-- Loading screen: special structural fixes
	if name == "00-LoadingScreen" then
		applyLoadingScreenFixes(child)
		return
	end

	-- Hotbar: scale child wrapper frames, not the root GUI
	if name == "10-HotbarGUI" or name == "HotbarGUI" then
		applyHotbarChildScales(child)
		return
	end

	-- IconGroup: layout applied for all devices (see applyIconGroupLayout).
	if name == "IconGroup" then
		applyIconGroupLayout(child)
		return
	end

	if name == Config.PaidBroadcast.GUI_NAME then
		applyPaidBroadcastLayout(child)
		return
	end

	if name == Config.Admin.GUI_NAME then
		applyAdminPanelLayout(child)
		return
	end

	local hubName = Config.Admin.HUB_GUI_NAME
	if type(hubName) == "string" and name == hubName then
		applyAdminHubLayout(child)
		return
	end

	local joinName = Config.JoinCommunityPrompt.GUI_NAME
	if type(joinName) == "string" and name == joinName then
		applyJoinCommunLayout(child)
		return
	end

	if name == Config.Backpack.GUI_NAME then
		applyBackpackLayout(child)
		return
	end

	local scale = SCALE_MAP[name]
	if scale == nil then
		return
	end

	local uiScale = getOrCreateRootScale(child)
	uiScale.Scale = scale
	if name == Config.Music.GUI_NAME then
		fitMusicPanel(child, scale)
	end

	-- ACM: remove the designer Y-offset baked into MainWrapper
	if name == "AvatarContextMenu" then
		local mainWrapper = child:FindFirstChild("MainWrapper")
		if mainWrapper ~= nil and mainWrapper:IsA("GuiObject") then
			local g = mainWrapper :: GuiObject
			local pos = g.Position
			g.Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, 0)
		end
	end
end

local function processPlayerGuiChild(child: Instance): ()
	if child.Name == "IconGroup" then
		applyIconGroupLayout(child)
	end
	if child.Name == Config.PaidBroadcast.GUI_NAME then
		applyPaidBroadcastLayout(child)
	end
	if child.Name == Config.Admin.GUI_NAME then
		applyAdminPanelLayout(child)
	end
	local hubName = Config.Admin.HUB_GUI_NAME
	if type(hubName) == "string" and child.Name == hubName then
		applyAdminHubLayout(child)
	end
	local joinName = Config.JoinCommunityPrompt.GUI_NAME
	if type(joinName) == "string" and child.Name == joinName then
		applyJoinCommunLayout(child)
	end
	if child.Name == Config.Backpack.GUI_NAME then
		applyBackpackLayout(child)
	end
	-- Desktop ACM: 0.8 so its 5px gaps land on whole screen pixels (4px). Phones keep ACM_GUI.
	if child.Name == "AvatarContextMenu" and not isMobile() and type(ms.ACM_GUI_DESKTOP) == "number" then
		getOrCreateRootScale(child).Scale = ms.ACM_GUI_DESKTOP
	end
	if isMobile() then
		applyToGui(child)
	end
end

function MobileScaleService.init(playerGui: PlayerGui): ()
	for _, child in ipairs(playerGui:GetChildren()) do
		processPlayerGuiChild(child)
	end

	playerGui.ChildAdded:Connect(processPlayerGuiChild)

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local iconGroup = playerGui:FindFirstChild("IconGroup")
			if iconGroup then
				applyIconGroupLayout(iconGroup)
			end
			local paidBroadcast = playerGui:FindFirstChild(Config.PaidBroadcast.GUI_NAME)
			if paidBroadcast then
				applyPaidBroadcastLayout(paidBroadcast)
			end
			local adminPanel = playerGui:FindFirstChild(Config.Admin.GUI_NAME)
			if adminPanel then
				applyAdminPanelLayout(adminPanel)
			end
			local hubName = Config.Admin.HUB_GUI_NAME
			if type(hubName) == "string" then
				local adminHub = playerGui:FindFirstChild(hubName)
				if adminHub then
					applyAdminHubLayout(adminHub)
				end
			end
			local joinName = Config.JoinCommunityPrompt.GUI_NAME
			if type(joinName) == "string" then
				local joinGui = playerGui:FindFirstChild(joinName)
				if joinGui then
					applyJoinCommunLayout(joinGui)
				end
			end
			local backpackGui = playerGui:FindFirstChild(Config.Backpack.GUI_NAME)
			if backpackGui then
				applyBackpackLayout(backpackGui)
			end
			-- The phone layout can start after boot (the Studio emulator sizes the viewport later,
			-- a phone rotated or split-screened): scale and fit the music panel again for the new
			-- screen instead of leaving the value baked into the template.
			if isMobile() then
				local musicGui = playerGui:FindFirstChild(Config.Music.GUI_NAME)
				if musicGui then
					applyToGui(musicGui)
				end
			end
		end)
	end
end

function MobileScaleService.applyAdminPanelLayout(gui: Instance): ()
	applyAdminPanelLayout(gui)
end

function MobileScaleService.applyAdminHubLayout(gui: Instance): ()
	applyAdminHubLayout(gui)
end

function MobileScaleService.applyJoinCommunLayout(gui: Instance): ()
	applyJoinCommunLayout(gui)
end

function MobileScaleService.applyBackpackLayout(gui: Instance): ()
	applyBackpackLayout(gui)
end

return MobileScaleService
