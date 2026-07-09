--!strict
-- Premade ProfileTab: bind once, patch only (no rebuild).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local AvatarPrewarmShared = require(script.Parent.Parent.Utils.AvatarPrewarmShared)
local AvatarViewport3D = require(script.Parent.Parent.Utils.AvatarViewport3D)
local ButtonVisualUtil = require(script.Parent.ButtonVisualUtil)
local MenuGuiRefs = require(script.Parent.MenuGuiRefs)
local MenuSettingsCore = require(script.Parent.MenuSettingsCore)

type ProfileMenuPayload = Types.ProfileMenuPayload
type OverheadPayload = Types.OverheadPayload
type Refs = MenuGuiRefs.MenuGuiRefs
type ButtonStyleSnapshot = ButtonVisualUtil.ButtonStyleSnapshot

type CoupleModeStyleRefs = {
	button: TextButton,
	idle: ButtonStyleSnapshot?,
	selected: ButtonStyleSnapshot?,
}

local BADGE_FRAME_NAMES = {
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

-- Satu tombol per mode di Studio; Idle/Selected = gaya visual (gradient/child), bukan swap instance.
local COUPLE_MODES: { { key: string, buttonNames: { string } } } = {
	{ key = "Single", buttonNames = { "SingleIdle", "SingleSelected" } },
	{ key = "Taken", buttonNames = { "TakenIdle", "TakenSelected" } },
	{ key = "Fun", buttonNames = { "ForFunIdle", "ForFunSelected" } },
}

local ProfileTabBinder = {}
ProfileTabBinder.__index = ProfileTabBinder

local RELATIONSHIP_STATUS_PREFIX = "Relationship Status : "

local function hasStatusText(statusText: any): boolean
	if type(statusText) ~= "string" then
		return false
	end
	local trimmed = statusText:match("^%s*(.-)%s*$")
	return trimmed ~= nil and trimmed ~= ""
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
	local label = likeFrame:FindFirstChild("LikeCounts", true)
		or likeFrame:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = formatCompactCount(likesCount)
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

local function resolveCouplePartnerDisplay(payload: ProfileMenuPayload, overhead: OverheadPayload?): string?
	if payload.showCoupleName and type(payload.couplePartner) == "string" and payload.couplePartner ~= "" then
		return payload.couplePartner
	end
	if overhead and overhead.showCoupleName and type(overhead.couplePartner) == "string" and overhead.couplePartner ~= "" then
		return overhead.couplePartner
	end
	return nil
end

local function getRelationshipDisplay(payload: ProfileMenuPayload, overhead: OverheadPayload?): string
	local mode = payload.relationshipMode
	if mode == "Fun" then
		return RELATIONSHIP_STATUS_PREFIX .. "Fun"
	end
	if mode == "Taken" then
		local partner = resolveCouplePartnerDisplay(payload, overhead)
		if partner then
			return "Taken by " .. partner
		end
		return RELATIONSHIP_STATUS_PREFIX .. "Taken"
	end
	return RELATIONSHIP_STATUS_PREFIX .. "Single"
end

local function normalizeRelationshipMode(mode: any): string
	if mode == "Taken" or mode == "Fun" then
		return mode
	end
	return "Single"
end

local function applyCoupleModeButtonVisual(
	styleRefs: CoupleModeStyleRefs,
	selected: boolean,
	idleFallback: ButtonStyleSnapshot?,
	selectedFallback: ButtonStyleSnapshot?
)
	local button = styleRefs.button
	button.Visible = true
	button.AutoButtonColor = false

	local snapshot = if selected
		then styleRefs.selected or selectedFallback or styleRefs.idle or idleFallback
		else styleRefs.idle or idleFallback
	if snapshot then
		ButtonVisualUtil.apply(button, snapshot)
	end
	ButtonVisualUtil.setInternalIdleSelected(button, selected)
end

local function setToggleVisual(row: TextButton, enabled: boolean)
	local toggle = row:FindFirstChild("Toggle")
	if not toggle or not toggle:IsA("Frame") then
		return
	end
	local shell = toggle:FindFirstChildWhichIsA("Frame")
	if shell then
		shell.BackgroundColor3 = if enabled then Color3.fromRGB(223, 223, 223) else Color3.fromRGB(62, 62, 62)
		local inner = shell:FindFirstChildWhichIsA("Frame")
		if inner then
			inner.BackgroundColor3 = if enabled then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(255, 255, 255)
			inner.Position = if enabled then UDim2.new(1, 0, 0, 0) else UDim2.new(0, 0, 0, 0)
			inner.AnchorPoint = Vector2.new(if enabled then 1 else 0, 0)
		end
	end
end

local function findCoupleButton(root: Instance, name: string): TextButton?
	local inst = root:FindFirstChild(name, true)
	if inst and inst:IsA("TextButton") then
		return inst
	end
	return nil
end

local function resolveCoupleModeButton(profileTab: Instance, buttonNames: { string }): TextButton?
	for _, name in ipairs(buttonNames) do
		local button = findCoupleButton(profileTab, name)
		if button then
			return button
		end
	end
	return nil
end

local function hideCoupleStyleTemplateButton(template: TextButton?, primary: TextButton?)
	if template and primary and template ~= primary then
		template.Visible = false
	end
end

-- Studio: Single/Taken pakai *Idle sebagai pill; For Fun kadang cuma *Selected yang visible.
local function resolveCouplePrimaryButton(idleButton: TextButton?, selectedButton: TextButton?): TextButton?
	if idleButton and selectedButton then
		if idleButton.Visible and not selectedButton.Visible then
			return idleButton
		end
		if selectedButton.Visible and not idleButton.Visible then
			return selectedButton
		end
		return idleButton
	end
	return idleButton or selectedButton
end

local function resolveSharedCoupleSelectedStyle(styles: { [string]: CoupleModeStyleRefs }): ButtonStyleSnapshot?
	for _, key in ipairs({ "Single", "Taken", "Fun" }) do
		local styleRefs = styles[key]
		if styleRefs and styleRefs.selected then
			return styleRefs.selected
		end
	end
	return nil
end

local function resolveSharedCoupleIdleStyle(styles: { [string]: CoupleModeStyleRefs }): ButtonStyleSnapshot?
	for _, key in ipairs({ "Single", "Taken", "Fun" }) do
		local styleRefs = styles[key]
		if styleRefs and styleRefs.idle then
			return styleRefs.idle
		end
	end
	return nil
end

local function captureCoupleModeStyles(profileTab: ScrollingFrame): { [string]: CoupleModeStyleRefs }
	local styles: { [string]: CoupleModeStyleRefs } = {}
	for _, modeDef in ipairs(COUPLE_MODES) do
		local idleName = modeDef.buttonNames[1]
		local selectedName = modeDef.buttonNames[2]
		local idleButton = if idleName then findCoupleButton(profileTab, idleName) else nil
		local selectedButton = if selectedName then findCoupleButton(profileTab, selectedName) else nil
		local primary = resolveCouplePrimaryButton(idleButton, selectedButton)
		if not primary then
			continue
		end

		local idleTemplate = idleButton
		local selectedTemplate = selectedButton

		styles[modeDef.key] = {
			button = primary,
			idle = if idleTemplate then ButtonVisualUtil.capture(idleTemplate) else nil,
			selected = if selectedTemplate then ButtonVisualUtil.capture(selectedTemplate) else nil,
		}
		hideCoupleStyleTemplateButton(idleButton, primary)
		hideCoupleStyleTemplateButton(selectedButton, primary)
		primary.Visible = true
	end

	local sharedIdle = resolveSharedCoupleIdleStyle(styles)
	for _, modeDef in ipairs(COUPLE_MODES) do
		local styleRefs = styles[modeDef.key]
		if styleRefs and not styleRefs.idle and sharedIdle then
			styleRefs.idle = sharedIdle
		end
	end

	return styles
end

local function ensureCoupleSectionVisible(profileTab: ScrollingFrame)
	for _, name in ipairs({ "CoupleStatus", "CoupleStatusSection", "RelationshipSection" }) do
		local section = profileTab:FindFirstChild(name, true)
		if section and section:IsA("GuiObject") then
			section.Visible = true
			for _, child in ipairs(section:GetDescendants()) do
				if child:IsA("GuiObject") and child.Name == "SectionContentWrapper" then
					child.Visible = true
				end
			end
		end
	end
end

local function setCoupleModeVisual(
	coupleModeStyles: { [string]: CoupleModeStyleRefs }?,
	profileTab: ScrollingFrame,
	activeMode: string
)
	ensureCoupleSectionVisible(profileTab)
	local resolvedMode = normalizeRelationshipMode(activeMode)
	local idleFallback = if coupleModeStyles then resolveSharedCoupleIdleStyle(coupleModeStyles) else nil
	local selectedFallback = if coupleModeStyles then resolveSharedCoupleSelectedStyle(coupleModeStyles) else nil

	for _, modeDef in ipairs(COUPLE_MODES) do
		local styleRefs = if coupleModeStyles then coupleModeStyles[modeDef.key] else nil
		local button = if styleRefs then styleRefs.button else resolveCoupleModeButton(profileTab, modeDef.buttonNames)
		if button then
			button.Visible = true
			applyCoupleModeButtonVisual(
				styleRefs or {
					button = button,
					idle = nil,
					selected = nil,
				},
				modeDef.key == resolvedMode,
				idleFallback,
				selectedFallback
			)
		end
	end
end

local function setShowCoupleRowVisible(toggle: TextButton, visible: boolean)
	toggle.Visible = visible

	-- Jangan hide parent besar (SectionContentWrapper / CoupleStatus) — itu bikin 3 pill ikut hilang.
	local parent = toggle.Parent
	if not parent or not parent:IsA("GuiObject") then
		return
	end
	local parentName = string.lower(parent.Name)
	if parentName == "sectioncontentwrapper" or parentName == "couplestatus" or parentName == "profiletab" then
		return
	end
	if string.find(parentName, "showcouple", 1, true) or string.find(parentName, "couplename", 1, true) then
		parent.Visible = visible
	end
end

export type ProfileFieldModalRequest = {
	field: string,
	title: string,
	currentValue: string,
	canEdit: boolean,
}

local function trimText(text: any): string
	if type(text) ~= "string" then
		return ""
	end
	return text:match("^%s*(.-)%s*$") or ""
end

local PROFILE_FIELD_EMPTY_LABELS: { [string]: string } = {
	specialTitle = "No Title yet",
	bio = "No Bio yet",
	statusText = "No Status yet",
}

local function formatDisplayNameRowDisplay(payload: ProfileMenuPayload): string
	local override = trimText(payload.displayNameOverride)
	if override ~= "" then
		return override
	end
	return trimText(payload.displayName)
end

local function formatProfileFieldDisplay(field: string, rawValue: any): string
	local trimmed = trimText(rawValue)
	if trimmed ~= "" then
		return trimmed
	end
	return PROFILE_FIELD_EMPTY_LABELS[field] or ""
end

local function setProfileFieldRowDisplay(valueBox: TextBox?, field: string, rawValue: any)
	if not valueBox then
		return
	end
	valueBox.PlaceholderText = ""
	valueBox.Text = formatProfileFieldDisplay(field, rawValue)
end

local function getProfileFieldValue(payload: ProfileMenuPayload?, field: string): string
	if not payload then
		return ""
	end
	if field == "displayNameOverride" then
		local override = trimText(payload.displayNameOverride)
		if override ~= "" then
			return override
		end
		return trimText(payload.displayName)
	elseif field == "specialTitle" then
		return trimText(payload.specialTitle)
	elseif field == "bio" then
		return trimText(payload.bio)
	elseif field == "statusText" then
		return trimText(payload.statusText)
	end
	return ""
end

local function canEditProfileField(payload: ProfileMenuPayload?, field: string): boolean
	if field == "specialTitle" then
		return payload ~= nil and payload.canEditSpecialTitle == true
	end
	return true
end

local function wireProfileFieldRow(
	self: any,
	rowRefs: MenuGuiRefs.EditableInputRefs?,
	field: string,
	title: string
)
	if not rowRefs then
		return
	end
	rowRefs.row.Visible = true
	rowRefs.row.Active = true
	rowRefs.row.AutoButtonColor = false
	if rowRefs.valueBox then
		rowRefs.valueBox.TextEditable = false
		rowRefs.valueBox.ClearTextOnFocus = false
		rowRefs.valueBox.Active = false
		rowRefs.valueBox.PlaceholderText = ""
	end

	local function openModal()
		if not self._profileFieldModalCallback then
			return
		end
		local payload = self._currentPayload
		self._profileFieldModalCallback({
			field = field,
			title = title,
			currentValue = getProfileFieldValue(payload, field),
			canEdit = canEditProfileField(payload, field),
		} :: ProfileFieldModalRequest)
	end

	rowRefs.row.Activated:Connect(openModal)
	if rowRefs.actionButton then
		rowRefs.actionButton.Activated:Connect(openModal)
	end
end

function ProfileTabBinder.new(refs: Refs)
	local self = setmetatable({}, ProfileTabBinder) :: any
	self._refs = refs
	self._bound = false
	self._profileChangeCallback = nil :: ((string, any) -> ())?
	self._profileFieldModalCallback = nil :: ((ProfileFieldModalRequest) -> ())?
	self._avatar = nil :: AvatarViewport3D.AvatarViewport3D?
	if refs.avatarViewport then
		self._avatar = AvatarViewport3D.new(refs.avatarViewport)
		self._avatar:setPrewarmPool(AvatarPrewarmShared.getPool())
	end
	self._avatarLoadedUserId = nil :: number?
	self._currentPayload = nil :: ProfileMenuPayload?
	self._currentOverhead = nil :: OverheadPayload?
	self._showCoupleEnabled = false
	self._coupleModeStyles = nil :: { [string]: CoupleModeStyleRefs }?
	return self
end

function ProfileTabBinder:bindProfileChange(callback: (string, any) -> ())
	self._profileChangeCallback = callback
end

function ProfileTabBinder:bindProfileFieldModal(callback: (ProfileFieldModalRequest) -> ())
	self._profileFieldModalCallback = callback
end

function ProfileTabBinder:applyTabIdentity()
	local profileTab = self._refs.profileTab
	if not profileTab:FindFirstChild("TabIdentity") then
		warn("[ProfileTabBinder] ProfileTab.TabIdentity not found — TabTitle/TabSubtitle tidak terisi")
		return
	end
	MenuSettingsCore.applyProfileTabPageIdentity(profileTab)
end

function ProfileTabBinder:bindIfNeeded()
	if self._bound then
		return
	end
	self._bound = true

	local refs = self._refs
	local profileTab = refs.profileTab

	self:applyTabIdentity()

	local function fireProfileChange(field: string, value: any)
		if self._profileChangeCallback then
			self._profileChangeCallback(field, value)
		end
	end

	if not self._coupleModeStyles then
		self._coupleModeStyles = captureCoupleModeStyles(profileTab)
	end

	for _, modeDef in ipairs(COUPLE_MODES) do
		local styleRefs = self._coupleModeStyles[modeDef.key]
		local button = if styleRefs then styleRefs.button else resolveCoupleModeButton(profileTab, modeDef.buttonNames)
		if button then
			button.AutoButtonColor = false
			button.Activated:Connect(function()
				setCoupleModeVisual(self._coupleModeStyles, profileTab, modeDef.key)
				if self._currentPayload then
					self:patchProfileField("relationshipMode", modeDef.key)
				end
				fireProfileChange("relationshipMode", modeDef.key)
			end)
		end
	end

	if refs.showCoupleToggle then
		refs.showCoupleToggle.Activated:Connect(function()
			fireProfileChange("showCoupleName", not self._showCoupleEnabled)
		end)
	end

	wireProfileFieldRow(self, refs.displayNameInput, "displayNameOverride", "Display Name")
	wireProfileFieldRow(self, refs.specialTitleInput, "specialTitle", "Title")
	wireProfileFieldRow(self, refs.bioInput, "bio", "Bio")
	wireProfileFieldRow(self, refs.statusInput, "statusText", "Status")

	local function openStatusModal()
		if not self._profileFieldModalCallback then
			return
		end
		self._profileFieldModalCallback({
			field = "statusText",
			title = "Status",
			currentValue = getProfileFieldValue(self._currentPayload, "statusText"),
			canEdit = true,
		} :: ProfileFieldModalRequest)
	end

	if refs.statusPopup and not refs.statusInput then
		refs.statusPopup.Activated:Connect(openStatusModal)
	elseif refs.statusPopupFrame and not refs.statusInput then
		local statusFrame = refs.statusPopupFrame
		if statusFrame:IsA("GuiButton") then
			statusFrame.Activated:Connect(openStatusModal)
		else
			statusFrame.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					openStatusModal()
				end
			end)
		end
	end

	local localPlayer = Players.LocalPlayer
	if refs.usernameLabel and localPlayer then
		refs.usernameLabel.Text = "@" .. localPlayer.Name
	end
end

function ProfileTabBinder:ensureAvatarLoaded(userId: number)
	if not self._avatar or self._avatarLoadedUserId == userId then
		return
	end
	local pool = AvatarPrewarmShared.getPool()
	if type(pool.prewarmOnDemand) == "function" then
		pool:prewarmOnDemand(userId)
	end
	if self._avatar:load(userId) then
		self._avatarLoadedUserId = userId
		self._avatar:startAutoRotate()
	end
end

function ProfileTabBinder:_setBadges(visibleBadges: { string }?)
	local badgeGroup = self._refs.badgeGroup
	if not badgeGroup then
		return
	end

	local visibleSet: { [string]: boolean } = {}
	if type(visibleBadges) == "table" then
		for _, badgeName in visibleBadges do
			visibleSet[tostring(badgeName)] = true
		end
	end

	for _, frameName in ipairs(BADGE_FRAME_NAMES) do
		local frame = badgeGroup:FindFirstChild(frameName)
		if frame and frame:IsA("GuiObject") then
			frame.Visible = visibleSet[frameName] == true
		end
	end
end

function ProfileTabBinder:patchProfile(payload: ProfileMenuPayload, overhead: OverheadPayload?)
	self._currentPayload = payload
	self._currentOverhead = overhead
	self:bindIfNeeded()

	local refs = self._refs
	local localPlayer = Players.LocalPlayer

	if refs.displayNameLabel then
		refs.displayNameLabel.Text = payload.displayName
	end
	if refs.usernameLabel and localPlayer then
		refs.usernameLabel.Text = "@" .. localPlayer.Name
	end
	if refs.bioContent then
		refs.bioContent.Text = formatProfileFieldDisplay("bio", payload.bio)
	end
	if refs.statusPopupLabel or refs.statusPopupFrame or refs.statusPopup then
		local statusText = payload.statusText
		local showStatus = hasStatusText(statusText)
		if refs.statusPopupFrame then
			refs.statusPopupFrame.Visible = showStatus
		elseif refs.statusPopup then
			refs.statusPopup.Visible = showStatus
		end
		if refs.statusPopupLabel then
			refs.statusPopupLabel.Text = if showStatus then (statusText :: string) else ""
		end
	end
	if refs.relationshipLine then
		refs.relationshipLine.Text = getRelationshipDisplay(payload, overhead)
	end

	local streakDays = if overhead then overhead.streakDays else 0
	if refs.streakCountLabel then
		refs.streakCountLabel.Text = tostring(streakDays)
	end

	setCoupleModeVisual(self._coupleModeStyles, refs.profileTab, payload.relationshipMode)
	ensureCoupleSectionVisible(refs.profileTab)

	self._showCoupleEnabled = payload.showCoupleName == true
	if refs.showCoupleToggle then
		local showRow = payload.isCoupled == true and payload.relationshipMode == "Taken"
		setShowCoupleRowVisible(refs.showCoupleToggle, showRow)
		if showRow then
			setToggleVisual(refs.showCoupleToggle, self._showCoupleEnabled)
		end
	end

	if refs.displayNameInput and refs.displayNameInput.valueBox then
		refs.displayNameInput.valueBox.PlaceholderText = ""
		refs.displayNameInput.valueBox.Text = formatDisplayNameRowDisplay(payload)
	end
	if refs.specialTitleInput then
		refs.specialTitleInput.row.Visible = true
		setProfileFieldRowDisplay(refs.specialTitleInput.valueBox, "specialTitle", payload.specialTitle)
		if refs.specialTitleInput.valueBox then
			refs.specialTitleInput.valueBox.TextEditable = false
		end
		refs.specialTitleInput.row.Active = true
	end
	if refs.bioInput then
		setProfileFieldRowDisplay(refs.bioInput.valueBox, "bio", payload.bio)
	end
	if refs.statusInput then
		refs.statusInput.row.Visible = true
		setProfileFieldRowDisplay(refs.statusInput.valueBox, "statusText", payload.statusText)
	end

	if overhead and type(overhead.visibleBadges) == "table" then
		self:_setBadges(overhead.visibleBadges)
	end
	if overhead and refs.badgeGroup then
		setLikeCount(refs.badgeGroup, overhead.likesCount or 0)
		setCommunityBadge(refs.badgeGroup, overhead.communityLogo)
	end
end

function ProfileTabBinder:patchProfileField(field: string, value: any)
	if not self._currentPayload then
		return
	end
	(self._currentPayload :: any)[field] = value
	self:patchProfile(self._currentPayload, self._currentOverhead)
end

return ProfileTabBinder
