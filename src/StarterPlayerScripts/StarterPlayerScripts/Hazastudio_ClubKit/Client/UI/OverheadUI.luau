--!strict
-- DISPLAY ONLY. Zero business logic. Zero remote calls.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Types = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LoadingScreenUI = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.LoadingScreenUI)
local UIShadowHelper = require(script.Parent.Parent.Utils.UIShadowHelper)
local SpecialTitleRenderer = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SpecialTitleRenderer)
local TitleFontUtil = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local ChatBubbleAdornee = require(script.Parent.Parent.Services.ChatBubbleAdornee)

type OverheadPayload = Types.OverheadPayload

-- Subtle pop animation constants
local POP_IN_DURATION = 0.22
local POP_IN_START_SCALE = 0.88
local POP_OUT_DURATION = 0.16
local POP_OUT_END_SCALE = 0.88
local POP_FADE_IN_DURATION = 0.18
local POP_FADE_OUT_DURATION = 0.14
local TEXT_OUTLINE_NAME = "__OverheadTextOutline"
local TEXT_OUTLINE_CLONE_PREFIX = "__OverheadTextOutlineClone_"
local TEXT_OUTLINE_TRANSPARENCY = 0.48
local TEXT_OUTLINE_THICKNESS = 1.0
local SPECIAL_TITLE_ROW_NAME = "01-SpecialTitle"
local DISPLAY_NAME_OUTLINE_LABELS = { "PlayerDisplayName", "MembershipLevel" }
local TEXT_OUTLINE_SKIP_LABEL_NAMES: { [string]: boolean } = {
	RobloxPlusBadge = true,
	RobloxPremiumBadge = true,
	Separator = true,
}
local PREMIUM_BADGE_NAMES = { "RobloxPlusBadge", "RobloxPremiumBadge" }

local ALL_BADGES = {
	"01-OwnerCoOwnerBadge",
	"02-DeveloperBadge",
	"03-AdminBadge",
	"04-MemberBadge",
	"05-VIPMemberBadge",
	"06-VVIPMemberBagde",
	"07-ELITEMemberBadge",
	"08-StreakBadge",
	"09-LikeCounterBadge",
	"10-CommunityBadge",
	"11-DJBadge",
	"12-InfluencerBadge",
}

-- Daftar key yang dipakai `isLayerVisible()` di seluruh file. Dipakai untuk
-- mendaftarkan prefix attribute di attribute watcher (lihat watchAttr).
local _LAYER_ATTR_KEYS = {
	"SpecialTitle",
	"BadgeGroup",
	"Level",
	"SpecialStatus",
	"SpecialRank",
	"TopSpender",
	"TopDonate",
	"Rank",
	"DisplayName",
	"CoupleName",
}

-- Daftar key yang dipakai `isBadgeVisible()` (lihat BADGE_SETTING_KEY_BY_FRAME).
local _BADGE_ATTR_KEYS = {
	"OwnerCoOwner",
	"Developer",
	"Admin",
	"Member",
	"VIP",
	"VVIP",
	"Elite",
	"Streak",
	"LikeCounter",
	"Community",
	"DJ",
	"Influencer",
}

local BADGE_SETTING_KEY_BY_FRAME: { [string]: string } = {
	["01-OwnerCoOwnerBadge"] = "OwnerCoOwner",
	["02-DeveloperBadge"] = "Developer",
	["03-AdminBadge"] = "Admin",
	["04-MemberBadge"] = "Member",
	["05-VIPMemberBadge"] = "VIP",
	["06-VVIPMemberBagde"] = "VVIP",
	["07-ELITEMemberBadge"] = "Elite",
	["08-StreakBadge"] = "Streak",
	["09-LikeCounterBadge"] = "LikeCounter",
	["10-CommunityBadge"] = "Community",
	["11-DJBadge"] = "DJ",
	["12-InfluencerBadge"] = "Influencer",
}

local RELATIONSHIP_GRADIENT_MAP: { [string]: string } = {
	Single = "UIGradientSingle",
	Fun = "UIGradientFun",
	Taken = "UIGradient",
}

local RANK_GRADIENT_MAP: { [string]: string } = {
	["ELITE MEMBER"] = "UIGradientElite",
	["VVIP MEMBER"] = "UIGradientVVIP",
	["VIP MEMBER"] = "UIGradientVIP",
	["MEMBER"] = "UIGradientMember",
	["GUEST"] = "UIGradientGuest",
}

local AFTER_TEAM_GRADIENT_NAME = "UIGradientAfterTeam"
local AFTER_TEAM_GRADIENT_COLOR = Color3.fromRGB(0, 0, 0)

-- ============================================================
-- SHARED GRADIENT ANIMATION LOOP (data tables - connection set up after animateTextGradient)
-- ============================================================
type GradientAnimData = {
	animMode: string,
	animSpeed: number,
	textRotation: number,
	startTime: number,
}
local animatedGradients: { [UIGradient]: GradientAnimData } = {}
local sharedGradientConn: RBXScriptConnection? = nil
local ensureSharedGradientLoop: () -> () -- forward declare, assigned after animateTextGradient

local OverheadUI = {}
OverheadUI.__index = OverheadUI

type OverheadUIImpl = {
	_gui: BillboardGui,
	_wrapper: GuiObject,
	_renderer: string,
	_preserveLayoutOrder: boolean,
	_popScale: UIScale,
	_titleAnimThread: thread?,
	_lastPayload: OverheadPayload?,
	_connections: { RBXScriptConnection },
	_wasEnabled: boolean,
	-- P1-1 lazy row pool (ENABLE_LAZY_ROWS): rows parked outside hierarchy when hidden
	_lazyRowPool: { [string]: GuiObject }?,
	-- P1-1 pending pool-return timers keyed by rowName
	_lazyPoolTimers: { [string]: thread }?,
	-- P1-1 single shared UIShadow instance parented to wrapper (R4.5)
	_sharedShadow: Instance?,
	apply: (self: OverheadUIImpl, payload: OverheadPayload) -> (),
	destroy: (self: OverheadUIImpl) -> (),
}

local function disconnectConnections(self: OverheadUIImpl)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

local function trackConnection(self: OverheadUIImpl, connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

local function resetGuiUntilPayload(gui: BillboardGui, wrapper: GuiObject?)
	gui.Enabled = false
	if not wrapper then
		return
	end

	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	local badgeGroup = wrapper:FindFirstChild("02-BadgeGroup")
	if badgeGroup and badgeGroup:IsA("Frame") then
		for _, badgeName in ipairs(ALL_BADGES) do
			local badge = badgeGroup:FindFirstChild(badgeName)
			if badge and badge:IsA("GuiObject") then
				badge.Visible = false
			end
		end
	end
end

local function ensurePopScale(wrapper: GuiObject): UIScale
	local existing = wrapper:FindFirstChild("_OverheadPopScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "_OverheadPopScale"
	scale.Scale = POP_IN_START_SCALE
	scale.Parent = wrapper
	return scale
end

local function setWrapperGroupTransparency(wrapper: GuiObject, value: number)
	if wrapper:IsA("CanvasGroup") then
		(wrapper :: CanvasGroup).GroupTransparency = value
	end
end

local function playPopIn(wrapper: GuiObject, popScale: UIScale)
	popScale.Scale = POP_IN_START_SCALE
	setWrapperGroupTransparency(wrapper, 1)
	TweenService
		:Create(
			popScale,
			TweenInfo.new(POP_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		:Play()
	if wrapper:IsA("CanvasGroup") then
		TweenService:Create(
			wrapper,
			TweenInfo.new(POP_FADE_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0 }
		):Play()
	end
end

local function playPopOut(wrapper: GuiObject, popScale: UIScale, gui: BillboardGui)
	TweenService:Create(
		popScale,
		TweenInfo.new(POP_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = POP_OUT_END_SCALE }
	):Play()
	if wrapper:IsA("CanvasGroup") then
		local fadeTween = TweenService:Create(
			wrapper,
			TweenInfo.new(POP_FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeTween:Play()
		fadeTween.Completed:Once(function()
			gui.Enabled = false
		end)
	else
		task.delay(POP_OUT_DURATION, function()
			if gui.Parent then
				gui.Enabled = false
			end
		end)
	end
end

local function getActiveGuiVariant(): any
	return Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
end

local function findOverheadWrapper(gui: BillboardGui, variant: any): GuiObject?
	local wrapperName = if type(variant) == "table" then variant.wrapperName else nil
	local candidates = {
		wrapperName,
		"OverheadGUIMainWrapper",
		"Frame",
	}

	for _, name in ipairs(candidates) do
		if type(name) == "string" and name ~= "" then
			local child = gui:FindFirstChild(name)
			if child and child:IsA("GuiObject") then
				return child :: GuiObject
			end
		end
	end

	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") then
			return child :: GuiObject
		end
	end
	return nil
end

local function findOverheadListLayout(wrapper: GuiObject): UIListLayout?
	local direct = wrapper:FindFirstChildWhichIsA("UIListLayout")
	if direct then
		return direct :: UIListLayout
	end

	-- Some template variants nest the main rows under an inner container.
	-- Fallback to recursive search so specialTitlePosition always applies.
	local recursive = wrapper:FindFirstChildWhichIsA("UIListLayout", true)
	if recursive then
		return recursive :: UIListLayout
	end

	return nil
end

-- Forward declaration for applyOverheadTextEffects (assigned after animateTextGradient section).
local applyOverheadTextEffects: (Instance?) -> ()


local LAZY_POOL_RETURN_DELAY = 1 -- seconds before a hidden row leaves the hierarchy (R4.4)
local SHARED_SHADOW_NAME = "__OverheadSharedShadow"

-- Ensure a named row is parented into wrapper (take from pool or find existing).
-- Returns the row GuiObject if found, nil if the template has no such row.
local function lazyEnsureRow(self: OverheadUIImpl, rowName: string): GuiObject?
	local overheadSelf = self :: any
	local pool: { [string]: GuiObject }? = overheadSelf._lazyRowPool
	if not pool then
		return nil
	end
	local wrapper = (overheadSelf._wrapper :: any) :: GuiObject

	-- Cancel any pending pool-return timer for this row.
	local timers: { [string]: thread }? = overheadSelf._lazyPoolTimers
	if timers and timers[rowName] then
		task.cancel(timers[rowName])
		timers[rowName] = nil :: any
	end

	-- If already parented in the wrapper, return it directly.
	local existing = wrapper:FindFirstChild(rowName)
	if existing and existing:IsA("GuiObject") then
		return existing :: GuiObject
	end

	-- If we have a pooled instance, re-parent it back.
	if pool[rowName] then
		local row = pool[rowName]
		pool[rowName] = nil :: any
		row.Parent = wrapper
		return row
	end

	-- No instance exists yet and none in pool: the row lives in the template
	-- hierarchy normally (FindFirstChild will find it). Return nil so callers
	-- fall back to the standard FindFirstChild path.
	return nil
end

-- Schedule a row to be removed from wrapper into the pool after LAZY_POOL_RETURN_DELAY (R4.4).
-- If the row is already hidden and is NOT currently visible, this is a no-op.
local function lazyReleaseRow(self: OverheadUIImpl, rowName: string)
	local overheadSelf = self :: any
	local pool: { [string]: GuiObject }? = overheadSelf._lazyRowPool
	local timers: { [string]: thread }? = overheadSelf._lazyPoolTimers
	if not pool or not timers then
		return
	end
	local wrapper = (overheadSelf._wrapper :: any) :: GuiObject

	-- Don't schedule a second timer if one is already pending.
	if timers[rowName] then
		return
	end

	timers[rowName] = task.delay(LAZY_POOL_RETURN_DELAY, function()
		timers[rowName] = nil :: any
		local row = wrapper:FindFirstChild(rowName)
		if row and row:IsA("GuiObject") then
			local guiRow = row :: GuiObject
			-- Only park it if it's actually hidden (visible=false means we are
			-- safe to remove from hierarchy).
			if not guiRow.Visible then
				guiRow.Parent = nil
				pool[rowName] = guiRow
			end
		end
	end)
end

-- Ensure the single shared UIShadow for this nametag exists on the wrapper (R4.5).
-- Returns the shared shadow instance, or nil if UIShadow is not supported.
local function ensureSharedShadow(self: OverheadUIImpl): Instance?
	local overheadSelf = self :: any
	if overheadSelf._sharedShadow then
		return overheadSelf._sharedShadow
	end
	if not UIShadowHelper.isSupported() then
		return nil
	end
	local wrapper = (overheadSelf._wrapper :: any) :: GuiObject
	-- Check if one was already created (e.g. from a previous call).
	local existing = wrapper:FindFirstChild(SHARED_SHADOW_NAME)
	if existing and existing.ClassName == "UIShadow" then
		overheadSelf._sharedShadow = existing
		return existing
	end
	local ok, result = pcall(function()
		local shadow = Instance.new("UIShadow")
		shadow.Name = SHARED_SHADOW_NAME
		shadow.Parent = wrapper
		return shadow
	end)
	if ok and result then
		-- Apply the OVERHEAD_TEXT preset properties to the shared shadow via UIShadowHelper.
		-- We reuse apply() which creates one under wrapper, but we already created it above,
		-- so just configure properties by applying the preset manually through the helper's
		-- internal path. The simplest approach: call apply on a dummy target then steal the
		-- shadow, but that's complex. Instead, we call apply on wrapper, which is idempotent
		-- because UIShadowHelper.apply checks for an existing __NativeUIShadow first.
		-- Since we used SHARED_SHADOW_NAME (not __NativeUIShadow), we configure it directly:
		local cfg = Config.UIShadow :: any
		local preset = cfg and cfg["OVERHEAD_TEXT"] :: any
		if preset and result then
			local shadow = result :: any
			for k, v in pairs(preset) do
				if k ~= "VisibleAlpha" and k ~= "PulseMin" and k ~= "PulseMax" then
					pcall(function()
						if k == "Offset" and typeof(v) == "Vector2" then
							shadow.Offset = UDim2.fromOffset(v.X, v.Y)
						else
							shadow[k] = v
						end
					end)
				end
			end
		end
		overheadSelf._sharedShadow = result
		return result
	end
	return nil
end



function OverheadUI.new(gui: BillboardGui): OverheadUIImpl
	local self = setmetatable({}, OverheadUI) :: any
	local variant = getActiveGuiVariant()
	self._gui = gui
	self._wrapper = findOverheadWrapper(gui, variant) :: GuiObject
	self._renderer = if type(variant.renderer) == "string" then variant.renderer else "V1"
	self._preserveLayoutOrder = variant.preserveLayoutOrder == true
	self._popScale = ensurePopScale(self._wrapper)
	self._titleAnimThread = nil
	self._lastPayload = nil
	self._connections = {}
	self._wasEnabled = false
	self._loadingRetryThread = nil :: thread?
	-- P1-1: lazy row pool state (R4.3, R4.4, R4.5)
	if Config.Overhead.ENABLE_LAZY_ROWS then
		self._lazyRowPool = {}
		self._lazyPoolTimers = {}
		self._sharedShadow = nil
		-- Create the single shared UIShadow immediately (R4.5).
		-- ensureSharedShadow is safe to call here even before the first apply().
		ensureSharedShadow(self)
		-- When ENABLE_LAZY_ROWS is true, applyOverheadTextEffects at build time
		-- still applies text stroke but skips per-label UIShadow (shared shadow covers it).
		applyOverheadTextEffects(self._wrapper)
	else
		self._lazyRowPool = nil
		self._lazyPoolTimers = nil
		self._sharedShadow = nil
		applyOverheadTextEffects(self._wrapper)
	end
	-- P2: Build per-nametag effect cache once after initial text effect application (R8.1).
	-- Subsequent apply() calls reuse this cache to avoid GetDescendants() tree walks (R8.2, R8.3).
	-- Discarded on destroy() (R8.4). Gated behind Config.Overhead.ENABLE_EFFECT_CACHE (task 1.1).
	if Config.Overhead.ENABLE_EFFECT_CACHE then
		self._effectCache = self._wrapper:GetDescendants()
	else
		self._effectCache = nil
	end
	resetGuiUntilPayload(gui, self._wrapper)
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		-- Consolidated attribute watcher: 1 connection instead of 22+.
		-- Watch top-level toggle + jarak, plus prefix untuk per-layer / per-badge
		-- visibility yang ditulis SettingsController saat user toggle hide/show layer.
		local watchedExactAttrs: { [string]: boolean } = {
			SettingsOverheadVisible = true,
			SettingsOverheadDistance = true,
		}
		local watchedPrefixes: { string } = {
			"SettingsOverheadLayerVisible_",
			"SettingsOverheadBadgeVisible_",
		}
		local function isWatchedAttr(attrName: string): boolean
			if watchedExactAttrs[attrName] then
				return true
			end
			for _, prefix in ipairs(watchedPrefixes) do
				if string.sub(attrName, 1, #prefix) == prefix then
					return true
				end
			end
			return false
		end
		trackConnection(
			self,
			localPlayer.AttributeChanged:Connect(function(attrName: string)
				if isWatchedAttr(attrName) and self._lastPayload then
					self:apply(self._lastPayload)
				end
			end)
		)
	end
	trackConnection(
		self,
		gui.Destroying:Connect(function()
			disconnectConnections(self)
		end)
	)
	return self
end


local function setRow(wrapper: GuiObject, rowName: string, visible: boolean, text: string?)
	local row = wrapper:FindFirstChild(rowName)
	if not row then
		return
	end
	(row :: Frame).Visible = visible
	if text and visible then
		local label = row:FindFirstChildWhichIsA("TextLabel")
		if label then
			(label :: TextLabel).Text = text
		end
	end
end

-- P1-1: Lazy-aware row setter (used when ENABLE_LAZY_ROWS = true).
-- Ensures the row is in the wrapper hierarchy before showing (R4.3) and
-- schedules pool return after hiding (R4.4).
local function lazySetRow(
	self: OverheadUIImpl,
	wrapper: GuiObject,
	rowName: string,
	visible: boolean,
	text: string?
)
	if visible then
		-- Ensure row is in hierarchy (re-parent from pool if needed).
		lazyEnsureRow(self, rowName)
	end
	-- Standard visibility + text update.
	setRow(wrapper, rowName, visible, text)
	if not visible then
		-- Schedule removal from hierarchy after 1s (R4.4).
		lazyReleaseRow(self, rowName)
	end
end

local function applyTextShadowIfBackgroundless(row: Instance?)
	if not row or not row:IsA("GuiObject") or row.BackgroundTransparency < 0.95 then
		return
	end
	-- P1-1: When ENABLE_LAZY_ROWS is active the shared UIShadow replaces per-label shadows (R4.5).
	if Config.Overhead.ENABLE_LAZY_ROWS then
		return
	end
	for _, descendant in ipairs(row:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			UIShadowHelper.apply(descendant :: GuiObject, "OVERHEAD_TEXT")
		end
	end
end

local function isUnderSpecialTitleRow(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if current.Name == SPECIAL_TITLE_ROW_NAME then
			return true
		end
		current = current.Parent
	end
	return false
end

local function shouldSkipTextOutline(textObject: GuiObject): boolean
	return TEXT_OUTLINE_SKIP_LABEL_NAMES[textObject.Name] == true
end

local function clearTextOutline(textObject: GuiObject)
	local textElement = textObject :: any
	textElement.TextStrokeTransparency = 1

	local outline = textObject:FindFirstChild(TEXT_OUTLINE_NAME)
	if outline then
		outline:Destroy()
	end
end

local function applyTextOutline(textObject: GuiObject)
	if shouldSkipTextOutline(textObject) then
		clearTextOutline(textObject)
		return
	end

	local textElement = textObject :: any
	-- TextStroke is screen-pixel based and blobs when the billboard shrinks on zoom-out.
	textElement.TextStrokeTransparency = 1

	local chosenStroke: UIStroke? = nil
	for _, child in ipairs(textObject:GetChildren()) do
		if child:IsA("UIStroke") then
			if child.Name == TEXT_OUTLINE_NAME then
				chosenStroke = child :: UIStroke
				break
			end
			if not chosenStroke then
				chosenStroke = child :: UIStroke
			else
				child:Destroy()
			end
		end
	end

	if not chosenStroke then
		chosenStroke = Instance.new("UIStroke")
		chosenStroke.Parent = textObject
	end

	chosenStroke.Name = TEXT_OUTLINE_NAME
	chosenStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	chosenStroke.Color = Color3.fromRGB(0, 0, 0)
	chosenStroke.Transparency = TEXT_OUTLINE_TRANSPARENCY
	chosenStroke.Thickness = TEXT_OUTLINE_THICKNESS
	chosenStroke.LineJoinMode = Enum.LineJoinMode.Round
	chosenStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
end

local function hidePremiumBadgesInRow(row: Instance)
	for _, descendant in ipairs(row:GetDescendants()) do
		for _, badgeName in ipairs(PREMIUM_BADGE_NAMES) do
			if descendant.Name == badgeName and descendant:IsA("GuiObject") then
				(descendant :: GuiObject).Visible = false
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
					clearTextOutline(descendant :: GuiObject)
				end
			end
		end
	end
end

local function normalizeDisplayNameMembershipRow(row: Instance)
	hidePremiumBadgesInRow(row)

	local separators: { TextLabel } = {}
	for _, descendant in ipairs(row:GetDescendants()) do
		if descendant.Name == "Separator" and descendant:IsA("TextLabel") then
			table.insert(separators, descendant :: TextLabel)
		end
	end

	table.sort(separators, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	for index, separator in ipairs(separators) do
		if index > 1 then
			separator.Visible = false
		end
		clearTextOutline(separator :: GuiObject)
	end
end

local function applyDisplayNameMembershipOutlines(row: Instance?)
	if not row then
		return
	end

	for _, labelName in ipairs(DISPLAY_NAME_OUTLINE_LABELS) do
		local node = row:FindFirstChild(labelName, true)
		if node and (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then
			applyTextOutline(node :: GuiObject)
		end
	end
end

applyOverheadTextEffects = function(root: Instance?, effectCache: { Instance }?)
	if not root then
		return
	end

	-- P2: ENABLE_EFFECT_CACHE — use pre-built descendant list to avoid GetDescendants()
	-- walks on every delta update (R8.2, R8.3). The cache is populated once at build
	-- time and reused for all subsequent apply() calls until destroy.
	-- Lazy rows are re-parented after cache build; always walk live descendants then.
	local descendants: { Instance }
	if Config.Overhead.ENABLE_LAZY_ROWS then
		descendants = root:GetDescendants()
	elseif Config.Overhead.ENABLE_EFFECT_CACHE and effectCache then
		descendants = effectCache
	else
		descendants = root:GetDescendants()
	end

	for _, descendant in ipairs(descendants) do
		if string.sub(descendant.Name, 1, #TEXT_OUTLINE_CLONE_PREFIX) == TEXT_OUTLINE_CLONE_PREFIX then
			descendant:Destroy()
		end
	end

	-- P1-1: When ENABLE_LAZY_ROWS is active the shared UIShadow on the wrapper
	-- replaces per-label shadows, so we skip individual UIShadowHelper.apply calls (R4.5).
	local skipPerLabelShadow = Config.Overhead.ENABLE_LAZY_ROWS == true

	local function applyToText(descendant: Instance)
		if string.sub(descendant.Name, 1, #TEXT_OUTLINE_CLONE_PREFIX) == TEXT_OUTLINE_CLONE_PREFIX then
			return
		end
		if isUnderSpecialTitleRow(descendant) then
			return
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local textObject = descendant :: GuiObject
			applyTextOutline(textObject)

			if not skipPerLabelShadow then
				UIShadowHelper.apply(textObject, "OVERHEAD_TEXT")
			end
		end
	end

	applyToText(root)
	for _, descendant in ipairs(descendants) do
		applyToText(descendant)
	end
end

local function getRelationshipStatusLabel(row: Instance): TextLabel?
	local named = row:FindFirstChild("CoupleDisplayNameText", true)
	if named and named:IsA("TextLabel") then
		return named
	end
	local label = row:FindFirstChildWhichIsA("TextLabel")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function applyRelationshipGradients(root: Instance, activeGradient: string?)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("UIGradient") then
			(child :: UIGradient).Enabled = activeGradient ~= nil and child.Name == activeGradient
		end
	end
end

local function applyRelationshipStatusStyle(row: Instance?, mode: string)
	if not row or not row:IsA("GuiObject") then
		return
	end

	row.BackgroundTransparency = 1

	local label = getRelationshipStatusLabel(row)
	if not label then
		return
	end

	label.BackgroundTransparency = 1

	local gradientName = RELATIONSHIP_GRADIENT_MAP[mode]
	if gradientName then
		applyRelationshipGradients(label, gradientName)
	end

	applyTextOutline(label)
end

local function getRelationshipDisplay(payload: OverheadPayload): string
	local mode = payload.relationshipMode
	if mode == "Fun" then
		return "DOWN TO FUN"
	end
	if mode == "Taken" then
		if payload.showCoupleName and type(payload.couplePartner) == "string" and payload.couplePartner ~= "" then
			local emoji = Config.Chat.COUPLE_TAG_EMOJI
			return string.upper(emoji .. " " .. payload.couplePartner .. " " .. emoji)
		end
		return "TAKEN"
	end
	return "SINGLE"
end

local function getLocalBoolAttribute(name: string, defaultValue: boolean): boolean
	local player = Players.LocalPlayer
	if not player then
		return defaultValue
	end
	local value = player:GetAttribute(name)
	if type(value) == "boolean" then
		return value
	end
	return defaultValue
end

local function getLocalStringAttribute(name: string, defaultValue: string): string
	local player = Players.LocalPlayer
	if not player then
		return defaultValue
	end
	local value = player:GetAttribute(name)
	if type(value) == "string" and #value > 0 then
		return value
	end
	return defaultValue
end

local function getOverheadMaxDistance(): number
	local mode = getLocalStringAttribute("SettingsOverheadDistance", "Medium")
	if mode == "Near" then
		return 28
	elseif mode == "Far" then
		return 0
	end
	return 48
end

-- Gate public visibility (subject-controlled) dengan local viewer preference.
-- SettingsController menulis `SettingsOverheadLayerVisible_<key>` / `SettingsOverheadBadgeVisible_<key>`
-- ke LocalPlayer setiap kali user toggle layer/badge di Settings. Tanpa gate ini,
-- setting hide-layer user tidak berpengaruh ke OverheadUI sampai payload baru datang.
-- defaultValue adalah nilai dari payload.publicOverheadLayerVisible (atau publicOverheadBadgeVisible).
-- Jika defaultValue=false, tidak perlu cek attribute (public sudah hide). Kalau true,
-- attribute local viewer yang jadi penentu — default ke true saat attribute belum di-set.
local function isLayerVisible(key: string, defaultValue: boolean): boolean
	if not defaultValue then
		return false
	end
	return getLocalBoolAttribute("SettingsOverheadLayerVisible_" .. key, true)
end

local function getPublicMapValue(map: { [string]: boolean }?, key: string, defaultValue: boolean): boolean
	if type(map) ~= "table" then
		return defaultValue
	end
	local value = map[key]
	if type(value) == "boolean" then
		return value
	end
	return defaultValue
end

local function isCoupleRelationshipRowVisible(payload: OverheadPayload): boolean
	local publicDefault = getPublicMapValue(payload.publicOverheadLayerVisible, "CoupleName", false)
	local localPlayer = Players.LocalPlayer
	if localPlayer and payload.userId == localPlayer.UserId then
		if not getLocalBoolAttribute("SettingsOverheadLayerVisible_CoupleName", true) then
			return false
		end
		local mode = payload.relationshipMode
		return mode == "Single" or mode == "Taken" or mode == "Fun"
	end
	return isLayerVisible("CoupleName", publicDefault)
end

local function isBadgeVisible(key: string, defaultValue: boolean): boolean
	if not defaultValue then
		return false
	end
	return getLocalBoolAttribute("SettingsOverheadBadgeVisible_" .. key, true)
end

local function setBadges(
	badgeGroup: Frame,
	visibleBadges: { string },
	publicBadgeVisible: { [string]: boolean }
): number
	local visibleSet: { [string]: true } = {}
	for _, name in ipairs(visibleBadges) do
		visibleSet[name] = true
	end
	local visibleCount = 0
	for _, badgeName in ipairs(ALL_BADGES) do
		local frame = badgeGroup:FindFirstChild(badgeName)
		if frame then
			local badgeKey = BADGE_SETTING_KEY_BY_FRAME[badgeName]
			local shouldShow = badgeKey ~= nil
				and visibleSet[badgeName] == true
				and isBadgeVisible(badgeKey, getPublicMapValue(publicBadgeVisible, badgeKey, true))
			local badgeFrame = frame :: Frame
			badgeFrame.Visible = shouldShow
			if shouldShow then
				visibleCount += 1
			end
		end
	end
	return visibleCount
end

local function setStreakCount(badgeGroup: Frame, streakDays: number)
	local streakFrame = badgeGroup:FindFirstChild("08-StreakBadge")
	if not streakFrame then
		return
	end
	local label = streakFrame:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		(label :: TextLabel).Text = tostring(streakDays)
	end
end

local function setLevelRow(levelRow: Frame, payload: OverheadPayload)
	local levelText = payload.levelText
	if type(levelText) ~= "string" or levelText == "" then
		local levelValue = tonumber(payload.level) or 1
		levelText = string.format(Config.Level.OVERHEAD_TEXT or "Lv.%d", levelValue)
	end

	local label = levelRow:FindFirstChild("LevelText", true)
		or levelRow:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		(label :: TextLabel).Text = levelText
	end

	local progress = tonumber(payload.xpProgress)
	if progress == nil then
		return
	end
	progress = math.clamp(progress, 0, 1)

	local fill = levelRow:FindFirstChild("XPBarFill", true)
		or levelRow:FindFirstChild("Fill", true)
		or levelRow:FindFirstChild("ProgressFill", true)
	if fill and fill:IsA("GuiObject") then
		local gui = fill :: GuiObject
		gui.Size = UDim2.new(progress, 0, gui.Size.Y.Scale, gui.Size.Y.Offset)
	end
end

local function formatCompactCount(value: number): string
	local count = math.max(0, math.floor(value))
	if count < 100 then
		return string.format("%02d", count)
	end
	if count < 1000 then
		return tostring(count)
	end
	if count < 100000 then
		return string.format("%dK", math.floor(count / 1000))
	end
	return "99+"
end

local function setLikeCount(badgeGroup: Frame, likesCount: number)
	local likeFrame = badgeGroup:FindFirstChild("09-LikeCounterBadge")
	if not likeFrame then
		return
	end
	local label = likeFrame:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		(label :: TextLabel).Text = formatCompactCount(likesCount)
	end
end

local function setCommunityBadge(badgeGroup: Frame, communityLogo: string?)
	local communityFrame = badgeGroup:FindFirstChild("10-CommunityBadge")
	if not communityFrame then
		return
	end

	local logo = communityFrame:FindFirstChild("CommunityLogo", true)
	if logo and logo:IsA("ImageLabel") then
		logo.Image = communityLogo or ""
	end
end

-- ============================================================
-- V3 DONATION LAYERS (00-DonationLayers)
-- Renderer V3 menampilkan ranking donasi sebagai chip:
--   RobuxRankWrapper > RobuxRanking  -> "#N ROBUX" (topDonateRank)
--   RupiahRankWrapper > RupiahRank   -> "#N RUPIAH" (topSpenderRank / Saweria)
-- Wrapper disembunyiin kalau rank-nya nil. Aman dipanggil di template
-- yang gak punya "00-DonationLayers" (langsung return).
-- UIGradient di wrapper (kalau ada di template) ikut shared gradient loop:
--   Robux = sheen (flow/sweep), Rupiah = prism (offset + rotation).
-- ============================================================
local DONATION_CHIP_ANIM: { [string]: { mode: string, speed: number } } = {
	RobuxRankWrapper = { mode = "sheen", speed = 0.9 },
	RupiahRankWrapper = { mode = "prism", speed = 0.75 },
}

local function setChipGradientAnim(chip: GuiObject, wrapperName: string, active: boolean)
	local grad = chip:FindFirstChildWhichIsA("UIGradient") :: UIGradient?
	if not grad then
		return
	end
	if active then
		-- Jangan re-seed startTime / base Rotation tiap apply (biar animasi mulus).
		if animatedGradients[grad] then
			return
		end
		local preset = DONATION_CHIP_ANIM[wrapperName]
		animatedGradients[grad] = {
			animMode = if preset then preset.mode else "sheen",
			animSpeed = if preset then preset.speed else 0.85,
			textRotation = grad.Rotation,
			startTime = os.clock(),
		}
		ensureSharedGradientLoop()
	else
		local data = animatedGradients[grad]
		if data then
			animatedGradients[grad] = nil
			grad.Offset = Vector2.zero
			grad.Rotation = data.textRotation
		end
	end
end

local function setDonationLayers(wrapper: GuiObject, payload: OverheadPayload)
	local layers = wrapper:FindFirstChild("00-DonationLayers")
	if not layers or not layers:IsA("GuiObject") then
		return
	end

	local function applyChip(wrapperName: string, _labelName: string, rank: number?, suffix: string)
		local chip = layers:FindFirstChild(wrapperName)
		if not chip or not chip:IsA("GuiObject") then
			return
		end
		local hasRank = type(rank) == "number" and (rank :: number) > 0
		chip.Visible = hasRank
		if hasRank then
			local label = chip:FindFirstChildWhichIsA("TextLabel")
			if label then
				(label :: TextLabel).Text = "#" .. tostring(rank) .. " " .. suffix
			end
		end
		local animEnabled = Config.Overhead.ANIMATE_DONATION_RANK_GRADIENT == true
		setChipGradientAnim(chip, wrapperName, hasRank and animEnabled)
	end

	-- Robux ranking = topDonateRank, Rupiah/Saweria ranking = topSpenderRank
	applyChip("RobuxRankWrapper", "RobuxRanking", payload.topDonateRank, "ROBUX")
	applyChip("RupiahRankWrapper", "RupiahRank", payload.topSpenderRank, "RUPIAH")

	-- Sembunyiin container kalau dua-duanya kosong, supaya gak makan slot layout.
	local anyVisible = false
	for _, child in ipairs(layers:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			anyVisible = true
			break
		end
	end
	layers.Visible = anyVisible
end

local function buildCS(keypoints: { { number } }): ColorSequence
	local kps = {}
	for _, point in ipairs(keypoints) do
		table.insert(
			kps,
			ColorSequenceKeypoint.new(
				point[1] :: number,
				Color3.fromRGB(point[2] :: number, point[3] :: number, point[4] :: number)
			)
		)
	end
	return ColorSequence.new(kps)
end

local function colorFromArray(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function getSolidBackgroundColor(style: any): Color3
	if type(style) == "table" and style.family == "admin_custom" and type(style.bgColors) == "table" then
		local point = style.bgColors[1]
		if
			type(point) == "table"
			and type(point[2]) == "number"
			and type(point[3]) == "number"
			and type(point[4]) == "number"
		then
			return Color3.fromRGB(point[2], point[3], point[4])
		end
	end

	local strokeColor = if type(style) == "table" then style.strokeColor else style
	local r = math.max(18, math.floor((strokeColor[1] or 255) * 0.34))
	local g = math.max(18, math.floor((strokeColor[2] or 255) * 0.34))
	local b = math.max(18, math.floor((strokeColor[3] or 255) * 0.34))
	return Color3.fromRGB(r, g, b)
end

local function resetTextGradient(textGrad: UIGradient?, rotation: number?)
	if not textGrad then
		return
	end
	textGrad.Offset = Vector2.zero
	if rotation then
		textGrad.Rotation = rotation
	end
end

local function animateTextGradient(
	textGrad: UIGradient,
	animMode: string,
	animSpeed: number,
	baseRotation: number,
	elapsed: number
)
	local speed = math.max(animSpeed, 0.05)
	local phase = elapsed * speed
	local offsetX = 0
	local offsetY = 0
	local rotation = baseRotation

	if animMode == "scan" then
		offsetX = math.sin(phase * 1.6) * 0.85
	elseif animMode == "bounce" then
		offsetX = math.sin(phase * 2.2) * 0.72
		offsetY = math.cos(phase * 1.1) * 0.08
	elseif animMode == "sheen" then
		offsetX = (phase * 0.9 % 2) - 1
		rotation += math.sin(phase * 1.2) * 8
	elseif animMode == "drift" then
		offsetX = math.sin(phase * 0.7) * 0.42
		offsetY = math.cos(phase * 0.9) * 0.12
		rotation += math.sin(phase * 0.55) * 6
	elseif animMode == "pulse" then
		offsetX = math.sin(phase * 1.35) * 0.24
		rotation += math.sin(phase * 2.1) * 10
	elseif animMode == "prism" then
		offsetX = math.sin(phase * 1.45) * 0.66
		offsetY = math.cos(phase * 1.95) * 0.1
		rotation += math.sin(phase * 1.3) * 18
	else
		offsetX = math.sin(phase) * 0.3
	end

	textGrad.Offset = Vector2.new(offsetX, offsetY)
	textGrad.Rotation = rotation
end

-- Assigned here after animateTextGradient is defined, so the shared loop can call it correctly
ensureSharedGradientLoop = function()
	if sharedGradientConn then
		return
	end
	-- v2.2: throttle overhead gradient animation from 60Hz to ~30Hz.
	-- animateTextGradient computes its position from os.clock() - startTime,
	-- so frequency is independent of correctness. With many players online
	-- (e.g. 30 CCU all with animated nametags), 60Hz iteration over the
	-- gradient set is the most expensive shared client loop. 30Hz is
	-- visually indistinguishable for sin-based gradient motion.
	local gradientAccum = 0
	local GRADIENT_INTERVAL = 0.033
	sharedGradientConn = RunService.Heartbeat:Connect(function(dt)
		gradientAccum += dt
		if gradientAccum < GRADIENT_INTERVAL then
			return
		end
		gradientAccum = 0
		for grad, data in pairs(animatedGradients) do
			if not grad.Parent then
				animatedGradients[grad] = nil
				continue
			end
			animateTextGradient(grad, data.animMode, data.animSpeed, data.textRotation, os.clock() - data.startTime)
		end
		if next(animatedGradients) == nil and sharedGradientConn then
			sharedGradientConn:Disconnect()
			sharedGradientConn = nil
		end
	end)
end

local function startGeneratedTextAnimation(self: OverheadUIImpl, textGrad: UIGradient, style: any)
	if self._titleAnimThread then
		task.cancel(self._titleAnimThread)
		self._titleAnimThread = nil
	end

	-- Register into the shared module-level gradient loop
	-- instead of spawning a per-player Heartbeat:Wait() loop
	animatedGradients[textGrad] = {
		animMode = style.animMode or "scan",
		animSpeed = style.animSpeed or 1,
		textRotation = style.textRotation or 0,
		startTime = os.clock(),
	}
	ensureSharedGradientLoop()
end

local function applyGeneratedStyle(specialTitleRow: Frame, payload: OverheadPayload): boolean
	local style = payload.specialTitleStyle
	if not style then
		return false
	end

	local bgGrad = specialTitleRow:FindFirstChildWhichIsA("UIGradient") :: UIGradient?
	local textLabel = specialTitleRow:FindFirstChild("SpecialTitleText") :: TextLabel?
	local textGrad = textLabel and textLabel:FindFirstChildWhichIsA("UIGradient") :: UIGradient?
	local rowStroke = specialTitleRow:FindFirstChildWhichIsA("UIStroke") :: UIStroke?

	if bgGrad then
		if style.family == "admin_custom" then
			bgGrad.Color = buildCS(style.bgColors)
		else
			local solidColor = getSolidBackgroundColor(style)
			bgGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, solidColor),
				ColorSequenceKeypoint.new(1, solidColor),
			})
		end
		bgGrad.Rotation = 0
		bgGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.14, 0.4),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.86, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	if textGrad then
		textGrad.Color = buildCS(style.textColors)
		textGrad.Rotation = style.textRotation
		textGrad.Offset = Vector2.zero
	end
	if rowStroke then
		rowStroke.Color = colorFromArray(style.strokeColor)
	end
	return true
end

local function applyTitleSize(specialTitleRow: Frame, payload: OverheadPayload)
	SpecialTitleRenderer.applyRowSize(specialTitleRow, payload.specialTitleSize or "M")
end

local function ensureSpecialTitleRow(wrapper: GuiObject): Frame?
	local existing = wrapper:FindFirstChild("01-SpecialTitle")
	if existing and existing:IsA("Frame") then
		return existing
	end

	local row = Instance.new("Frame")
	row.Name = "01-SpecialTitle"
	row.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	row.LayoutOrder = 1
	row.Size = UDim2.new(1, 0, Config.Admin.TITLE_SIZE_HEIGHT_SCALE.M or 0.2, 0)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(100, 108, 130)
	stroke.Transparency = 0.35
	stroke.Parent = row

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new(Color3.fromRGB(31, 35, 48), Color3.fromRGB(18, 20, 28))
	bgGrad.Rotation = 0
	bgGrad.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "SpecialTitleText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	local textGrad = Instance.new("UIGradient")
	textGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 230, 255))
	textGrad.Parent = label

	row.Parent = wrapper
	return row
end

local function uppercaseText(text: string?): string?
	return if text then string.upper(text) else nil
end

local function getPayloadMembershipLabel(payload: OverheadPayload): string
	local label = (payload :: any).membershipLabel
	if type(label) == "string" and label ~= "" then
		return label
	end
	local tier = tostring(payload.effectiveMembership or "")
	return Config.MembershipChatLabel[tier] or payload.rankText or tier
end

local function getPayloadMembershipGradientName(payload: OverheadPayload): string?
	if payload.role == "AfterTeam" then
		return AFTER_TEAM_GRADIENT_NAME
	end
	local gradientName = (payload :: any).membershipGradientName
	if type(gradientName) == "string" and gradientName ~= "" then
		return gradientName
	end
	return RANK_GRADIENT_MAP[payload.rankText]
end

local function setNamedText(root: Instance, name: string, text: string)
	local label = root:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		(label :: TextLabel).Text = text
	end
end

local function setNamedGuiVisible(root: Instance, name: string, visible: boolean)
	local guiObject = root:FindFirstChild(name, true)
	if guiObject and guiObject:IsA("GuiObject") then
		(guiObject :: GuiObject).Visible = visible
	end
end

local function applyMembershipGradients(root: Instance, activeGradient: string?)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("UIGradient") then
			(child :: UIGradient).Enabled = activeGradient ~= nil and child.Name == activeGradient
		end
	end
end

-- Auto-inject a solid black UIGradient for the AfterTeam role since the
-- template has no gradient instance for it. Idempotent on subsequent calls.
local function ensureAfterTeamGradient(root: Instance)
	local existing = root:FindFirstChild(AFTER_TEAM_GRADIENT_NAME)
	if existing and existing:IsA("UIGradient") then
		return
	end
	local gradient = Instance.new("UIGradient")
	gradient.Name = AFTER_TEAM_GRADIENT_NAME
	gradient.Color = ColorSequence.new(AFTER_TEAM_GRADIENT_COLOR)
	gradient.Parent = root
end

function OverheadUI:apply(payload: OverheadPayload)
	local overheadSelf = self :: any
	self._lastPayload = payload
	local wrapper = (self._wrapper :: any) :: GuiObject
	if not wrapper then
		return
	end

	-- Batalkan retry thread sebelumnya kalau ada
	if overheadSelf._loadingRetryThread then
		pcall(task.cancel, overheadSelf._loadingRetryThread)
		overheadSelf._loadingRetryThread = nil
	end

	local overheadVisible = getLocalBoolAttribute("SettingsOverheadVisible", true)
	local loadingUi = LoadingScreenUI.get()
	local loadingBlocking = loadingUi and loadingUi:isBlockingGameplay()
	self._gui.MaxDistance = getOverheadMaxDistance()

	local shouldBeEnabled = overheadVisible and not loadingBlocking
	local wasEnabled = overheadSelf._wasEnabled

	-- Transition: hidden → visible (pop in)
	if shouldBeEnabled and not wasEnabled then
		self._gui.Enabled = true
		playPopIn(wrapper, overheadSelf._popScale)
		overheadSelf._wasEnabled = true
	-- Transition: visible → hidden (pop out)
	elseif not shouldBeEnabled and wasEnabled then
		overheadSelf._wasEnabled = false
		playPopOut(wrapper, overheadSelf._popScale, self._gui)
		-- gui.Enabled = false is handled by playPopOut after fade completes
	elseif not shouldBeEnabled then
		self._gui.Enabled = false
	end

	-- Jika loading sedang blocking, spawn retry agar overhead muncul setelah loading selesai
	if loadingBlocking and overheadVisible then
		overheadSelf._loadingRetryThread = task.spawn(function()
			while true do
				task.wait(0.5)
				local retryLoadingUi = LoadingScreenUI.get()
				local stillBlocking = retryLoadingUi and retryLoadingUi:isBlockingGameplay()
				if not stillBlocking then
					-- Loading selesai, re-apply payload
					if overheadSelf._lastPayload then
						overheadSelf:apply(overheadSelf._lastPayload)
					end
					break
				end
			end
		end)
	end

	if not overheadVisible then
		ChatBubbleAdornee.scheduleSync(payload.userId, self._gui, wrapper, false)
		return
	end


	local listLayout = findOverheadListLayout(wrapper)
	if listLayout then
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local position = payload.specialTitlePosition
		if position ~= "Stacked" then
			position = "Top"
		end
		if position == "Stacked" then
			listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		else
			listLayout.SortOrder = Enum.SortOrder.Name
		end
	end

	-- P1-1: lazy row routing (R4.3, R4.4).
	-- When ENABLE_LAZY_ROWS is true, use lazySetRow to park/restore rows from the pool.
	local useLazyRows = Config.Overhead.ENABLE_LAZY_ROWS == true
	local function rowSet(rowName: string, visible: boolean, text: string?)
		if useLazyRows then
			lazySetRow(self, wrapper, rowName, visible, text)
		else
			setRow(wrapper, rowName, visible, text)
		end
	end

	-- P1-1: For badge/effect rows that contain lazily-managed content, ensure they are
	-- in hierarchy before FindFirstChild lookups below.
	if useLazyRows then
		lazyEnsureRow(self, "00-SpecialStatus")
		lazyEnsureRow(self, "01-SpecialTitle")
		lazyEnsureRow(self, "04-SpecialRank")
		lazyEnsureRow(self, "05-TopSpender")
		lazyEnsureRow(self, "06-TopDonate")
		lazyEnsureRow(self, "03-Level")
		lazyEnsureRow(self, "07-Rank")
		lazyEnsureRow(self, "08-DisplayName")
		lazyEnsureRow(self, "08-DisplayNameAndMembership")
		lazyEnsureRow(self, "09-CoupleDisplayName")
		lazyEnsureRow(self, "00-DonationLayers")
		lazyEnsureRow(self, "02-BadgeGroup")
	end

	local specialTitleRow = ensureSpecialTitleRow(wrapper)
	if specialTitleRow then
		local specialTitleVisible = payload.specialTitle ~= nil
			and isLayerVisible(
				"SpecialTitle",
				getPublicMapValue(payload.publicOverheadLayerVisible, "SpecialTitle", true)
			)
		specialTitleRow.Visible = specialTitleVisible
		specialTitleRow.BackgroundTransparency = 1
		SpecialTitleRenderer.clearRowBackground(specialTitleRow)

		local specialTitleLabel = specialTitleRow:FindFirstChild("SpecialTitleText")
		if specialTitleLabel and specialTitleLabel:IsA("GuiObject") then
			clearTextOutline(specialTitleLabel :: GuiObject)
		end

		if useLazyRows and not specialTitleVisible then
			lazyReleaseRow(self, "01-SpecialTitle")
		end

		specialTitleRow.Rotation = 0

		if self._titleAnimThread then
			task.cancel((overheadSelf._titleAnimThread :: any) :: thread)
			overheadSelf._titleAnimThread = nil
		end

		if payload.specialTitle then
			local label = specialTitleRow:FindFirstChild("SpecialTitleText") :: TextLabel?
			local textGrad = label and label:FindFirstChildWhichIsA("UIGradient") :: UIGradient?
			if label then
				label.Text = payload.specialTitle
				TitleFontUtil.applyToTextLabel(label, payload.specialTitleFont)
			end

			applyTitleSize(specialTitleRow, payload)

			local presetMode = payload.specialTitlePreset
			if type(presetMode) == "string" and presetMode ~= "" then
				SpecialTitleRenderer.apply(specialTitleRow, {
					text = payload.specialTitle,
					font = payload.specialTitleFont,
					size = payload.specialTitleSize,
					presetMode = presetMode,
				})
			else
				SpecialTitleRenderer.destroy(specialTitleRow)
				local hasGeneratedStyle = applyGeneratedStyle(specialTitleRow, payload)
				if not hasGeneratedStyle then
					resetTextGradient(textGrad)
				elseif textGrad and payload.specialTitleStyle then
					startGeneratedTextAnimation(self, textGrad, payload.specialTitleStyle)
				end
				SpecialTitleRenderer.clearRowBackground(specialTitleRow)
				SpecialTitleRenderer.normalizeLayout(specialTitleRow)
				if label then
					TitleFontUtil.applyToTextLabel(label, payload.specialTitleFont)
				end
			end
		else
			SpecialTitleRenderer.destroy(specialTitleRow)
			local textGrad = (specialTitleRow:FindFirstChild("SpecialTitleText") :: TextLabel?)
				and (specialTitleRow:FindFirstChild("SpecialTitleText") :: TextLabel):FindFirstChildWhichIsA(
					"UIGradient"
				) :: UIGradient?
			resetTextGradient(textGrad)
		end
	end

	local badgeGroup = wrapper:FindFirstChild("02-BadgeGroup") :: Frame
	if badgeGroup then
		local visibleBadgeCount = setBadges(badgeGroup, payload.visibleBadges, payload.publicOverheadBadgeVisible)
		local badgeGroupVisible = visibleBadgeCount > 0
			and isLayerVisible("BadgeGroup", getPublicMapValue(payload.publicOverheadLayerVisible, "BadgeGroup", true))
		badgeGroup.Visible = badgeGroupVisible
		setStreakCount(badgeGroup, payload.streakDays)
		setLikeCount(badgeGroup, payload.likesCount)
		setCommunityBadge(badgeGroup, payload.communityLogo)
		if useLazyRows and not badgeGroupVisible then
			lazyReleaseRow(self, "02-BadgeGroup")
		end
	end

	-- V3-only: render donation ranking chips (no-op di template tanpa 00-DonationLayers)
	setDonationLayers(wrapper, payload)
	if useLazyRows then
		local donationLayers = wrapper:FindFirstChild("00-DonationLayers")
		if donationLayers and donationLayers:IsA("GuiObject") and not (donationLayers :: GuiObject).Visible then
			lazyReleaseRow(self, "00-DonationLayers")
		end
	end

	local specialStatusRow = wrapper:FindFirstChild("00-SpecialStatus")
	local specialStatusVisible = payload.statusText ~= nil
		and isLayerVisible(
			"SpecialStatus",
			getPublicMapValue(payload.publicOverheadLayerVisible, "SpecialStatus", true)
		)
	rowSet("00-SpecialStatus", specialStatusVisible, payload.statusText)
	applyTextShadowIfBackgroundless(specialStatusRow)

	local hasSpecialRank = payload.specialRank ~= nil
	local specialRankRow = wrapper:FindFirstChild("04-SpecialRank")
	local specialRankVisible = hasSpecialRank
		and isLayerVisible(
			"SpecialRank",
			getPublicMapValue(payload.publicOverheadLayerVisible, "SpecialRank", true)
		)
	rowSet("04-SpecialRank", specialRankVisible, payload.specialRank)
	applyTextShadowIfBackgroundless(specialRankRow)

	-- 05-TopSpender legacy (#N INVESTOR) — superseded by 00-DonationLayers RupiahRank chip.
	local topSpenderRow = wrapper:FindFirstChild("05-TopSpender")
	local showLegacyTopSpenderRow = Config.Donation.SHOW_LEGACY_TOP_SPENDER_ROW == true
	local topSpenderVisible = showLegacyTopSpenderRow
		and payload.topSpenderText ~= nil
		and isLayerVisible("TopSpender", getPublicMapValue(payload.publicOverheadLayerVisible, "TopSpender", true))
	rowSet("05-TopSpender", topSpenderVisible, uppercaseText(payload.topSpenderText))
	applyTextShadowIfBackgroundless(topSpenderRow)

	local topDonateRow = wrapper:FindFirstChild("06-TopDonate")
	local topDonateVisible = payload.topDonateText ~= nil
		and isLayerVisible("TopDonate", getPublicMapValue(payload.publicOverheadLayerVisible, "TopDonate", true))
	rowSet("06-TopDonate", topDonateVisible, uppercaseText(payload.topDonateText))
	applyTextShadowIfBackgroundless(topDonateRow)

	local rankRow = wrapper:FindFirstChild("07-Rank") :: Frame?
	if rankRow then
		local rankVisible =
			isLayerVisible("Rank", getPublicMapValue(payload.publicOverheadLayerVisible, "Rank", true))
		rankRow.Visible = rankVisible
		local rankLabel = rankRow:FindFirstChildWhichIsA("TextLabel")
		if rankLabel then
			(rankLabel :: TextLabel).Text = payload.rankText
		end
		if payload.role == "AfterTeam" then
			ensureAfterTeamGradient(rankRow)
		end
		applyMembershipGradients(rankRow, getPayloadMembershipGradientName(payload))
		if useLazyRows and not rankVisible then
			lazyReleaseRow(self, "07-Rank")
		end
	end
	applyTextShadowIfBackgroundless(rankRow)

	if Config.FeatureFlags.LevelSystemEnabled then
		local levelRow = wrapper:FindFirstChild("03-Level") :: Frame?
		if levelRow then
			local levelVisible = payload.level ~= nil
				and isLayerVisible("Level", getPublicMapValue(payload.publicOverheadLayerVisible, "Level", true))
			levelRow.Visible = levelVisible
			if levelVisible then
				setLevelRow(levelRow, payload)
			end
			if useLazyRows and not levelVisible then
				lazyReleaseRow(self, "03-Level")
			end
			applyTextShadowIfBackgroundless(levelRow)
		end
	else
		local levelRow = wrapper:FindFirstChild("03-Level")
		if levelRow then
			levelRow.Visible = false
		end
	end

	local displayNameVisible =
		isLayerVisible("DisplayName", getPublicMapValue(payload.publicOverheadLayerVisible, "DisplayName", true))
	local displayNameRow = wrapper:FindFirstChild("08-DisplayName")
	local displayNameMembershipRow = wrapper:FindFirstChild("08-DisplayNameAndMembership")
	if displayNameMembershipRow and displayNameMembershipRow:IsA("GuiObject") then
		(displayNameMembershipRow :: GuiObject).Visible = displayNameVisible
		setNamedText(displayNameMembershipRow, "PlayerDisplayName", payload.displayName)
		local membershipLabel = getPayloadMembershipLabel(payload)
		local showMembership = membershipLabel ~= ""
		setNamedText(displayNameMembershipRow, "MembershipLevel", membershipLabel)
		setNamedGuiVisible(displayNameMembershipRow, "MembershipLevel", showMembership)
		for _, descendant in ipairs(displayNameMembershipRow:GetDescendants()) do
			if descendant.Name == "Separator" and descendant:IsA("GuiObject") then
				(descendant :: GuiObject).Visible = showMembership
			end
		end
		normalizeDisplayNameMembershipRow(displayNameMembershipRow)
		local membershipLabelNode = displayNameMembershipRow:FindFirstChild("MembershipLevel", true)
		if membershipLabelNode then
			if payload.role == "AfterTeam" then
				ensureAfterTeamGradient(membershipLabelNode)
			end
			applyMembershipGradients(membershipLabelNode, getPayloadMembershipGradientName(payload))
		end
		applyDisplayNameMembershipOutlines(displayNameMembershipRow)
		applyTextShadowIfBackgroundless(displayNameMembershipRow)
		if useLazyRows and not displayNameVisible then
			lazyReleaseRow(self, "08-DisplayNameAndMembership")
		end
	else
		rowSet("08-DisplayName", displayNameVisible, payload.displayName)
		applyTextShadowIfBackgroundless(displayNameRow)
	end

	local relationshipRow = wrapper:FindFirstChild("09-CoupleDisplayName")
	local relationshipVisible = isCoupleRelationshipRowVisible(payload)
	local relationshipText = getRelationshipDisplay(payload)
	rowSet("09-CoupleDisplayName", relationshipVisible, relationshipText)
	applyRelationshipStatusStyle(relationshipRow, payload.relationshipMode)
	applyOverheadTextEffects(wrapper, overheadSelf._effectCache)

	-- Enable after content is set (if not already handled by pop-in transition above)
	if shouldBeEnabled and not self._gui.Enabled then
		self._gui.Enabled = true
		playPopIn(wrapper, overheadSelf._popScale)
		overheadSelf._wasEnabled = true
	end

	ChatBubbleAdornee.scheduleSync(payload.userId, self._gui, wrapper, shouldBeEnabled == true)
end

-- Hapus semua animated gradients yang dimiliki GUI ini dari shared pool.
-- Dipanggil saat OverheadUI di-destroy (e.g. respawn, player leave).
local function removeGradientsForGui(gui: BillboardGui)
	for grad in pairs(animatedGradients) do
		-- Gradient milik GUI ini kalau parent-chain-nya mengarah ke gui
		local inst: Instance? = grad
		local isOwned = false
		while inst do
			if inst == gui then
				isOwned = true
				break
			end
			inst = inst.Parent
		end
		if isOwned then
			animatedGradients[grad] = nil
		end
	end
end

function OverheadUI:destroy()
	local overheadSelf = self :: any
	local wrapper = overheadSelf._wrapper
	if wrapper then
		local specialTitleRow = wrapper:FindFirstChild("01-SpecialTitle")
		if specialTitleRow and specialTitleRow:IsA("Frame") then
			SpecialTitleRenderer.destroy(specialTitleRow)
		end
	end
	-- Stop title animation thread jika ada
	if overheadSelf._titleAnimThread then
		task.cancel(overheadSelf._titleAnimThread)
		overheadSelf._titleAnimThread = nil
	end
	-- Cancel loading retry thread jika ada
	if overheadSelf._loadingRetryThread then
		pcall(task.cancel, overheadSelf._loadingRetryThread)
		overheadSelf._loadingRetryThread = nil
	end
	-- P1-1: flush lazy row pool — cancel timers and destroy parked instances (R4.4).
	if overheadSelf._lazyPoolTimers then
		for rowName, timerThread in pairs(overheadSelf._lazyPoolTimers) do
			pcall(task.cancel, timerThread)
			overheadSelf._lazyPoolTimers[rowName] = nil :: any
		end
		overheadSelf._lazyPoolTimers = nil
	end
	if overheadSelf._lazyRowPool then
		for rowName, row in pairs(overheadSelf._lazyRowPool) do
			pcall(function()
				row:Destroy()
			end)
			overheadSelf._lazyRowPool[rowName] = nil :: any
		end
		overheadSelf._lazyRowPool = nil
	end
	-- P1-1: shared shadow is parented to wrapper which will be destroyed with the gui;
	-- clear the reference so we don't hold onto a stale instance.
	overheadSelf._sharedShadow = nil
	-- P2: Discard per-nametag effect cache on destroy/rebuild (R8.4).
	if Config.Overhead.ENABLE_EFFECT_CACHE then
		overheadSelf._effectCache = nil
	end
	-- Remove gradients milik GUI ini dari shared animation loop (fix H-03)
	if overheadSelf._gui then
		removeGradientsForGui(overheadSelf._gui)
	end
	-- Disconnect semua koneksi (AttributeChanged, Destroying)
	disconnectConnections(overheadSelf)
	local lastPayload = overheadSelf._lastPayload
	if type(lastPayload) == "table" and type(lastPayload.userId) == "number" then
		ChatBubbleAdornee.clear(lastPayload.userId)
	end
	overheadSelf._lastPayload = nil
end

return OverheadUI
