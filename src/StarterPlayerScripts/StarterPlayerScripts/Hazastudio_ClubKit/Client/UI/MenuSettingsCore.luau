--!strict
-- Settings row builders extracted from SettingsMenuUI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local GraphicsQuality = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.GraphicsQuality)

type SettingsPayload = Types.SettingsPayload

-- Explicit union type untuk SECTION_DEFS — mencegah type mismatch di array literal heterogeneous
type OptionItem = { label: string, value: string, iconImage: string? }
type SliderDef = {
	kind: "slider",
	field: string,
	label: string,
	iconImage: string?,
	min: number,
	max: number,
	step: number,
	format: (any) -> string,
	localOnly: boolean?,
	requiresOverheadFeature: string?,
}
type SegmentedDef = {
	kind: "segmented",
	field: string,
	label: string,
	iconImage: string?,
	options: { OptionItem },
	localOnly: boolean?,
	requiresOverheadFeature: string?,
}
type ToggleDef = {
	kind: "toggle",
	field: string,
	label: string,
	iconImage: string?,
	localOnly: boolean?,
	valueMap: { on: any, off: any }?,
	requiresOverheadFeature: string?,
}
type InputDef = {
	kind: "input",
	field: string,
	label: string,
	iconImage: string?,
	subtitle: string?,
	placeholder: string?,
	value: string?,
	disabled: boolean?,
}
type InfoDef = { kind: "info", label: string }
type SettingDef = SliderDef | SegmentedDef | ToggleDef | InputDef | InfoDef
type SettingsSectionDef = { key: string, title: string, subtitle: string, items: { SettingDef } }
type ChangeCallback = (field: string, value: any) -> ()

export type FieldBinding = {
	kind: string,
	field: string,
	item: any,
	row: GuiObject,
	setValue: (any) -> (),
}

local SECTION_LIST_GAP = 16
local SECTION_TITLE_CONTENT_GAP = 14
local SECTION_VERTICAL_PADDING = 14
local SECTION_IDENTITY_TITLE_TEXT_SIZE = 18
local SECTION_IDENTITY_SUBTITLE_TEXT_SIZE = 14
local SECTION_IDENTITY_LIST_PADDING = 6
local SECTION_CONTENT_ROW_GAP = 1
local SECTION_CONTENT_PADDING_TOP = 4
local SETTINGS_ROW_LABEL_TEXT_SIZE = 14
local SECTION_IDENTITY_TITLE_NAMES = { "SectionTitle" }
local SECTION_IDENTITY_SUBTITLE_NAMES = { "SectionSubtitle" }
local SETTINGS_TAB_PAGE_TITLE = "Preferences"
local SETTINGS_TAB_PAGE_SUBTITLE = "Gameplay, audio, and display preferences."
local PROFILE_TAB_PAGE_TITLE = "Profile"
local PROFILE_TAB_PAGE_SUBTITLE = "Your card, status, and couple preferences."
local SCROLL_TOP_PADDING = 8
local SLIDER_ROW_HEIGHT = 88
local SLIDER_ROW_PADDING_X = 14
local SLIDER_ROW_PADDING_Y = 12
local SLIDER_INNER_GAP = 10
local ADJUST_WRAPPER_CORNER_RADIUS = UDim.new(1, 0)
local TOGGLE_ROW_HEIGHT = 38
local _SEGMENTED_ROW_HEIGHT = 104
local PROFILE_INPUT_ROW_HEIGHT = 116
local PROFILE_INPUT_ROW_PADDING_X = 12
local PROFILE_INPUT_ROW_PADDING_Y = 10
local PROFILE_INPUT_AREA_PADDING_X = 14
local INFO_ROW_HEIGHT = 72
local SIDEBAR_HIDDEN_MARGIN = 24
-- Entrance: smooth deceleration slide, no bounce.
local SIDEBAR_TWEEN_IN = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local SIDEBAR_TWEEN_OUT = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BACKDROP_TWEEN_IN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BACKDROP_TWEEN_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SETTINGS_ICON = {
	Generic = "rbxassetid://87272651050606",
	Torso = "rbxassetid://104572654745007",
	Single = "rbxassetid://79366863686652",
	NameTag = "rbxassetid://99143048206723",
	Head = "rbxassetid://82655670841185",
	FullBody = "rbxassetid://87479186690180",
	Fun = "rbxassetid://126281074508689",
	Taken = "rbxassetid://132600999999748",
	BubbleChat = "rbxassetid://94227935854947",
	Off = "rbxassetid://124392921024385",
	On = "rbxassetid://137095705806436",
	GraphicsLow = "rbxassetid://76421319383025",
	GraphicsMed = "rbxassetid://94928591392266",
	GraphicsHigh = "rbxassetid://105332257572128",
}
local SETTINGS_ICON_BY_FIELD: { [string]: string } = {
	cameraFocus = SETTINGS_ICON.Torso,
	overheadDistance = SETTINGS_ICON.NameTag,
	chatBubbleVisibility = SETTINGS_ICON.BubbleChat,
	hideAllParticles = SETTINGS_ICON.Fun,
	overheadVisible = SETTINGS_ICON.NameTag,
	relationshipMode = SETTINGS_ICON.Single,
	showCoupleName = SETTINGS_ICON.Taken,
}
local SETTINGS_ICON_BY_FIELD_PREFIX: { [string]: string } = {
	overheadLayerVisible = SETTINGS_ICON.NameTag,
	overheadBadgeVisible = SETTINGS_ICON.NameTag,
}
local SETTINGS_ICON_BY_VALUE: { [string]: string } = {
	Torso = SETTINGS_ICON.Torso,
	Head = SETTINGS_ICON.Head,
	FullBody = SETTINGS_ICON.FullBody,
	Single = SETTINGS_ICON.Single,
	Taken = SETTINGS_ICON.Taken,
	Fun = SETTINGS_ICON.Fun,
	Off = SETTINGS_ICON.Off,
	Near = SETTINGS_ICON.NameTag,
	Medium = SETTINGS_ICON.NameTag,
	Far = SETTINGS_ICON.NameTag,
	All = SETTINGS_ICON.BubbleChat,
	Nearby = SETTINGS_ICON.BubbleChat,
}

local TAB_DEFS = {
	{ key = "profile", label = "Profile", sectionName = "ProfileSection" },
	{ key = "playerlist", label = "Players", sectionName = "PlayerlistSection" },
	{ key = "settings", label = "Settings", sectionName = "SettingsSection" },
	{ key = "about", label = "About", sectionName = "AboutSection" },
}

local MEMBERSHIP_TIER_STYLE = {
	Guest = {
		order = 0,
		cardColor = Color3.fromRGB(18, 18, 18),
		nameColor = Color3.fromRGB(210, 210, 210),
		badgeImage = "",
	},
	Member = {
		order = 1,
		cardColor = Color3.fromRGB(4, 20, 8),
		nameColor = Color3.fromRGB(126, 217, 87),
		badgeImage = "",
	},
	Tier1 = {
		order = 2,
		cardColor = Color3.fromRGB(32, 24, 4),
		nameColor = Color3.fromRGB(226, 171, 48),
		badgeImage = Config.Membership.Tiers.Tier1.badgeImage,
	},
	Tier2 = {
		order = 3,
		cardColor = Color3.fromRGB(24, 10, 38),
		nameColor = Color3.fromRGB(192, 132, 252),
		badgeImage = Config.Membership.Tiers.Tier2.badgeImage,
	},
	Tier3 = {
		order = 4,
		cardColor = Color3.fromRGB(22, 0, 0),
		nameColor = Color3.fromRGB(186, 0, 0),
		badgeImage = Config.Membership.Tiers.Tier3.badgeImage,
	},
	-- Spender sits between Tier3 (Exclusive) and Tier2 (VVIP). Overrides the
	-- membership tier when the player is in the top Saweria/Robux leaderboard.
	Spender = {
		order = 3.5,
		cardColor = Color3.fromRGB(4, 28, 24),
		nameColor = Color3.fromRGB(94, 234, 212),
		badgeImage = "",
	},
}

local SECTION_DEFS: { SettingsSectionDef } = {
	{
		key = "graphics",
		title = "Graphics",
		subtitle = "Low applies performance settings automatically. Visual Comfort below can override.",
		items = {
			{
				kind = "segmented",
				field = "graphicsPreset",
				label = "Overall Quality",
				options = {
					{ label = "Low", value = "Low", iconImage = SETTINGS_ICON.GraphicsLow },
					{ label = "Balance", value = "Balanced", iconImage = SETTINGS_ICON.GraphicsMed },
					{ label = "High", value = "High", iconImage = SETTINGS_ICON.GraphicsHigh },
				},
			},
		},
	},
	{
		key = "visual",
		title = "Visual Comfort",
		subtitle = "Fine-tune effects. Changes here override your quality preset.",
		items = {
			{ kind = "toggle", field = "eyeComfortMode", label = "Warm Screen Tone" },
			{
				kind = "slider",
				field = "colorSaturation",
				label = "Saturation",
				min = 0,
				max = 100,
				step = 5,
				format = function(v)
					local rounded = math.floor(v + 0.5)
					if rounded == 50 then
						return "Default"
					end
					local delta = rounded - 50
					if delta > 0 then
						return "+" .. tostring(delta) .. "%"
					end
					return tostring(delta) .. "%"
				end,
			},
			{
				kind = "slider",
				field = "colorContrast",
				label = "Contrast",
				min = 0,
				max = 100,
				step = 5,
				format = function(v)
					local rounded = math.floor(v + 0.5)
					if rounded == 50 then
						return "Default"
					end
					local delta = rounded - 50
					if delta > 0 then
						return "+" .. tostring(delta) .. "%"
					end
					return tostring(delta) .. "%"
				end,
			},
			{
				kind = "slider",
				field = "colorBrightness",
				label = "Brightness",
				min = 0,
				max = 100,
				step = 5,
				format = function(v)
					local rounded = math.floor(v + 0.5)
					if rounded == 50 then
						return "Default"
					end
					local delta = rounded - 50
					if delta > 0 then
						return "+" .. tostring(delta) .. "%"
					end
					return tostring(delta) .. "%"
				end,
			},
			{
				kind = "toggle",
				field = "shadowQuality",
				label = "Shadows",
				valueMap = { on = "Balanced", off = "Off" },
			},
			{ kind = "toggle", field = "depthOfField", label = "Background Blur", valueMap = { on = 3, off = 0 } },
			{ kind = "toggle", field = "hideAllParticles", label = "Hide All Particles" },
			{
				kind = "toggle",
				field = "chatBubbleVisibility",
				label = "Hide Chat Bubbles",
				valueMap = { on = "Off", off = "All" },
			},
			{ kind = "toggle", field = "textures", label = "Textures", valueMap = { on = 2, off = 0 } },
		},
	},
	{
		key = "audio",
		title = "Audio",
		subtitle = "Adjust music playback volume.",
		items = {
			{
				kind = "slider",
				field = "musicVolume",
				label = "Music Volume",
				min = 0,
				max = 100,
				step = 5,
				format = function(v)
					return tostring(math.floor(v + 0.5)) .. "%"
				end,
			},
		},
	},
	{
		key = "camera",
		title = "Camera",
		subtitle = "Adjust how wide the camera feels.",
		items = {
			{
				kind = "slider",
				field = "fov",
				label = "View Width",
				min = 60,
				max = 100,
				step = 1,
				format = function(v)
					return tostring(math.floor(v + 0.5))
				end,
			},
			-- "Follow" (cameraFocus) row dihapus 2026-05-23: feature di-revert ke
			-- Roblox default camera (no offset).
			-- "Dock Zoom" slider dihapus 2026-05-23: di-lock ke 35% di semua device.
			-- Lihat applyHotbarZoom di SettingsController.luau.
		},
	},
	{
		key = "overhead_master",
		title = "Name Tags",
		subtitle = "Show or hide custom player name tags above heads.",
		items = {
			-- "Show Name Tags At" (overheadDistance) dihapus 2026-05-23.
			{ kind = "toggle", field = "overheadVisible", label = "Show Name Tags", localOnly = true },
			{ kind = "toggle", field = "hideAllGui", label = "Hide All GUI", localOnly = true },
		},
	},
	{
		key = "overhead_layers",
		title = "Name Tag Details",
		subtitle = "Choose what appears in player name tags.",
		items = {
			{ kind = "toggle", field = "overheadLayerVisible.SpecialTitle", label = "Custom Title", localOnly = true },
			{ kind = "toggle", field = "overheadLayerVisible.BadgeGroup", label = "Badges", localOnly = true },
			{ kind = "toggle", field = "overheadLayerVisible.Level", label = "Level", localOnly = true },
			{
				kind = "toggle",
				field = "overheadLayerVisible.SpecialRank",
				label = "Special Rank",
				localOnly = true,
				requiresOverheadFeature = "SpecialRank",
			},
			{
				kind = "toggle",
				field = "overheadLayerVisible.TopSpender",
				label = "Top Spender",
				localOnly = true,
				requiresOverheadFeature = "TopSpender",
			},
			{
				kind = "toggle",
				field = "overheadLayerVisible.TopDonate",
				label = "Top Donor",
				localOnly = true,
				requiresOverheadFeature = "TopDonate",
			},
			{ kind = "toggle", field = "overheadLayerVisible.Rank", label = "Role", localOnly = true },
			{ kind = "toggle", field = "overheadLayerVisible.DisplayName", label = "Player Name", localOnly = true },
			{ kind = "toggle", field = "overheadLayerVisible.CoupleName", label = "Couple Status", localOnly = true },
		},
	},
	{
		key = "badge_visibility",
		title = "Badge Types",
		subtitle = "Choose which badges can appear in name tags.",
		items = {
			{
				kind = "toggle",
				field = "overheadBadgeVisible.OwnerCoOwner",
				label = "Owner / Co-Owner",
				localOnly = true,
			},
			{ kind = "toggle", field = "overheadBadgeVisible.Developer", label = "Developer", localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.Admin", label = "Admin", localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.Member", label = "Membership", localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.VIP", label = Config.Membership.Tiers.Tier1.label, localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.VVIP", label = Config.Membership.Tiers.Tier2.label, localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.Elite", label = Config.Membership.Tiers.Tier3.label, localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.Streak", label = "Streak", localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.LikeCounter", label = "Likes", localOnly = true },
			{ kind = "toggle", field = "overheadBadgeVisible.Community", label = "Community", localOnly = true },
		},
	},
	{
		key = "announcements",
		title = "Announcements",
		subtitle = "Choose which messages you want to see.",
		items = {
			{
				kind = "toggle",
				field = "hideAdminAnnounce",
				label = "Admin Messages",
				valueMap = { on = false, off = true },
			},
			{
				kind = "toggle",
				field = "hideCoupleAnnounce",
				label = "Couple Messages",
				valueMap = { on = false, off = true },
			},
			{
				kind = "toggle",
				field = "hideSystemAnnounce",
				label = "System Messages",
				valueMap = { on = false, off = true },
			},
		},
	},
	{
		key = "donation_experience",
		title = "Donation Experience",
		subtitle = "Control donation visuals and announcements on your screen.",
		items = {
			{
				kind = "toggle",
				field = "hideDonationWorldEffect",
				label = "World Effects",
				valueMap = { on = false, off = true },
			},
			{
				kind = "toggle",
				field = "hideDonationAura",
				label = "Donor Aura",
				valueMap = { on = false, off = true },
			},
			{
				kind = "toggle",
				field = "hideDonationAnnounce",
				label = "Announcements",
				valueMap = { on = false, off = true },
			},
			{
				kind = "toggle",
				field = "hideDonatorHighlight",
				label = "Donor Highlight",
				valueMap = { on = false, off = true },
			},
		},
	},
}

local PRETTY_VALUE = {
	Torso = "Torso",
	Head = "Head",
	FullBody = "Full",
	Off = "Off",
	Low = "Low",
	Medium = "Medium",
	High = "High",
	Small = "Small",
	Normal = "Normal",
	Large = "Large",
	Near = "Near",
	Far = "Far",
	Nearby = "Nearby",
	LowPreset = "Low",
	Balanced = "Balance",
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

local function hasText(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function getVisibleBadgeSettingKeys(overheadPayload: any?): { [string]: boolean }?
	if type(overheadPayload) ~= "table" or type(overheadPayload.visibleBadges) ~= "table" then
		return nil
	end

	local keys = {}
	for _, badgeName in ipairs(overheadPayload.visibleBadges) do
		local key = BADGE_SETTING_KEY_BY_FRAME[tostring(badgeName)]
		if key then
			keys[key] = true
		end
	end
	return keys
end

local function hasOverheadFeature(feature: string?, overheadPayload: any?): boolean
	if not feature or feature == "" or type(overheadPayload) ~= "table" then
		return true
	end
	if feature == "SpecialTitle" then
		return hasText(overheadPayload.specialTitle)
	end
	if feature == "BadgeGroup" then
		return type(overheadPayload.visibleBadges) == "table" and #overheadPayload.visibleBadges > 0
	end
	if feature == "SpecialRank" then
		return hasText(overheadPayload.specialRank)
	end
	if feature == "TopSpender" then
		return type(overheadPayload.topSpenderRank) == "number" or hasText(overheadPayload.topSpenderText)
	end
	if feature == "TopDonate" then
		return type(overheadPayload.topDonateRank) == "number" or hasText(overheadPayload.topDonateText)
	end
	return true
end

local function shouldShowSettingsItem(item: any, overheadPayload: any?): boolean
	if type(overheadPayload) ~= "table" then
		return true
	end

	if type(item.field) == "string" then
		local layerKey = string.match(item.field, "^overheadLayerVisible%.(.+)$")
		if layerKey and not hasOverheadFeature(item.requiresOverheadFeature or layerKey, overheadPayload) then
			return false
		end

		local badgeKey = string.match(item.field, "^overheadBadgeVisible%.(.+)$")
		if badgeKey then
			local visibleBadgeKeys = getVisibleBadgeSettingKeys(overheadPayload)
			return visibleBadgeKeys == nil or visibleBadgeKeys[badgeKey] == true
		end
	end

	return hasOverheadFeature(item.requiresOverheadFeature, overheadPayload)
end

local function profileStructureKey(payload: any): string
	local profilePayload = payload or {}
	return tostring(profilePayload.isCoupled == true)
		.. ":"
		.. tostring(profilePayload.relationshipMode == "Taken")
end

local function getSettingsSectionDefs(_overheadPayload: any?): { SettingsSectionDef }
	-- Always return all items — conditional visibility is handled by updateConditionalRowVisibility.
	-- Filtering here would cause missing registry bindings, triggering expensive full rebuilds.
	return SECTION_DEFS
end
local function _asTextLabel(inst: Instance?): TextLabel?
	if inst and inst:IsA("TextLabel") then
		return inst
	end
	return nil
end

local function asTextButton(inst: Instance?): TextButton?
	if inst and inst:IsA("TextButton") then
		return inst
	end
	return nil
end

local function asTextBox(inst: Instance?): TextBox?
	if inst and inst:IsA("TextBox") then
		return inst
	end
	return nil
end

local function asFrame(inst: Instance?): Frame?
	if inst and inst:IsA("Frame") then
		return inst
	end
	return nil
end

local function asGuiObject(inst: Instance?): GuiObject?
	if inst and inst:IsA("GuiObject") then
		return inst
	end
	return nil
end

local function _asCanvasGroup(inst: Instance?): CanvasGroup?
	if inst and inst:IsA("CanvasGroup") then
		return inst
	end
	return nil
end

local function asScrollingFrame(inst: Instance?): ScrollingFrame?
	if inst and inst:IsA("ScrollingFrame") then
		return inst
	end
	return nil
end

local function collectButtons(parent: Instance): { TextButton }
	local buttons = {}
	for _, child in ipairs(parent:GetDescendants()) do
		if child:IsA("TextButton") then
			table.insert(buttons, child)
		end
	end
	table.sort(buttons, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return buttons
end

local function findFirstChildByNames(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name)
		if child then
			return child
		end
	end
	return nil
end

local function findFirstDescendantByNames(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name, true)
		if child then
			return child
		end
	end
	return nil
end

local function applySettingsRowLabelStyle(label: TextLabel?)
	if not label then
		return
	end
	label.TextSize = SETTINGS_ROW_LABEL_TEXT_SIZE
end

local function setTextLabelText(parent: Instance, text: string)
	local label = parent:FindFirstChildWhichIsA("TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
		applySettingsRowLabelStyle(label)
	end
end

local function configureBodyLabel(label: Instance?)
	if not label or not label:IsA("TextLabel") then
		return
	end

	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.TextYAlignment = Enum.TextYAlignment.Top
end

local function findIdentityLabels(identity: Instance, names: { string }): { TextLabel }
	local labels: { TextLabel } = {}
	local seen: { [TextLabel]: boolean } = {}
	for _, name in ipairs(names) do
		local label = identity:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") and not seen[label] then
			seen[label] = true
			table.insert(labels, label)
		end
	end
	return labels
end

local function setIdentityTitleText(identity: Instance, names: { string }, text: string)
	for _, label in ipairs(findIdentityLabels(identity, names)) do
		label.Text = text
	end
end

local function setIdentitySubtitleText(identity: Instance, names: { string }, text: string)
	local subtitle = if type(text) == "string" then text else ""
	local hasSubtitle = subtitle ~= ""
	for _, label in ipairs(findIdentityLabels(identity, names)) do
		label.Text = subtitle
		label.Visible = hasSubtitle
	end
end

local function applyIdentityChrome(identity: Instance, titleNames: { string }, subtitleNames: { string })
	local listLayout = identity:FindFirstChildWhichIsA("UIListLayout")
	if listLayout then
		listLayout.Padding = UDim.new(0, SECTION_IDENTITY_LIST_PADDING)
	end

	for _, label in ipairs(findIdentityLabels(identity, titleNames)) do
		label.TextSize = SECTION_IDENTITY_TITLE_TEXT_SIZE
	end

	for _, label in ipairs(findIdentityLabels(identity, subtitleNames)) do
		label.TextSize = SECTION_IDENTITY_SUBTITLE_TEXT_SIZE
		configureBodyLabel(label)
	end
end

local function applySectionIdentityStyle(identity: Instance)
	applyIdentityChrome(identity, SECTION_IDENTITY_TITLE_NAMES, SECTION_IDENTITY_SUBTITLE_NAMES)
end

local function applyTabPageIdentity(tab: ScrollingFrame, title: string, subtitle: string?)
	local identity = tab:FindFirstChild("TabIdentity")
	if not identity then
		return
	end
	local titleLabel = identity:FindFirstChild("TabTitle")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = title
	end
	local subtitleLabel = identity:FindFirstChild("TabSubtitle")
	if subtitleLabel and subtitleLabel:IsA("TextLabel") then
		subtitleLabel.Text = if type(subtitle) == "string" then subtitle else ""
	end
end

local function allowOverflow(gui: Instance?)
	if not gui or not gui:IsA("GuiObject") or gui:IsA("CanvasGroup") then
		return
	end

	gui.ClipsDescendants = false
end

local function setTextButtonText(root: Instance, text: string)
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
			child.Text = text
			return
		end
	end
	if root:IsA("TextButton") or root:IsA("TextLabel") or root:IsA("TextBox") then
		(root :: any).Text = text
	end
end

local function setTextAndIconColor(parent: Instance, color: Color3)
	for _, child in ipairs(parent:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
			(child :: any).TextColor3 = color
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			(child :: any).ImageColor3 = color
		end
	end
end

local function hasNamedAncestor(instance: Instance, stopAt: Instance, names: { [string]: boolean }): boolean
	local current = instance.Parent
	while current and current ~= stopAt do
		if names[current.Name] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function findSettingIconTarget(root: Instance): any
	local preferredNames = {
		"Icon2",
		"SettingIcon",
		"OptionIcon",
		"IconImage",
		"ImageIcon",
		"Icon",
	}
	for _, name in ipairs(preferredNames) do
		local target = root:FindFirstChild(name, true)
		if target and (target:IsA("ImageLabel") or target:IsA("ImageButton")) then
			return target
		end
	end

	local excludedAncestors = {
		ActionButton = true,
		AdjustWrapper = true,
		Toggle = true,
	}
	local excludedSelf = {
		ActionButton = true,
		DraggableIcon = true,
	}
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			(descendant:IsA("ImageLabel") or descendant:IsA("ImageButton"))
			and not excludedSelf[descendant.Name]
			and not hasNamedAncestor(descendant, root, excludedAncestors)
		then
			return descendant
		end
	end
	return nil
end

local function setSettingIcon(root: Instance, image: string?)
	local icon = findSettingIconTarget(root)
	if not icon then
		return
	end
	icon.Image = image or SETTINGS_ICON.Generic
	icon.Visible = true
	icon.ImageTransparency = 0

	local existingScale = icon:FindFirstChild("RuntimeSettingsIconScale")
	local scale: UIScale
	if existingScale and existingScale:IsA("UIScale") then
		scale = existingScale
	else
		local createdScale = Instance.new("UIScale")
		createdScale.Name = "RuntimeSettingsIconScale"
		createdScale.Parent = icon
		scale = createdScale
	end
	scale.Scale = 1
end

local function resolveSettingIcon(item: any): string
	if type(item.iconImage) == "string" and item.iconImage ~= "" then
		return item.iconImage
	end

	local field = tostring(item.field or "")
	local direct = SETTINGS_ICON_BY_FIELD[field]
	if direct then
		return direct
	end

	local prefix = string.match(field, "^([^%.]+)%.")
	if prefix and SETTINGS_ICON_BY_FIELD_PREFIX[prefix] then
		return SETTINGS_ICON_BY_FIELD_PREFIX[prefix]
	end

	return SETTINGS_ICON.Generic
end

local function resolveOptionIcon(option: any): string
	if type(option) == "table" then
		if type(option.iconImage) == "string" and option.iconImage ~= "" then
			return option.iconImage
		end
		local valueIcon = SETTINGS_ICON_BY_VALUE[tostring(option.value or "")]
		if valueIcon then
			return valueIcon
		end
		local labelIcon = SETTINGS_ICON_BY_VALUE[tostring(option.label or "")]
		if labelIcon then
			return labelIcon
		end
	end

	return SETTINGS_ICON_BY_VALUE[tostring(option)] or SETTINGS_ICON.Generic
end

local function disableAutoButtonColor(root: Instance)
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("GuiButton") then
			child.AutoButtonColor = false
		end
	end

	if root:IsA("GuiButton") then
		root.AutoButtonColor = false
	end
end

local function clearSectionContent(sectionContent: Instance, preserve: { [string]: boolean })
	for _, child in ipairs(sectionContent:GetChildren()) do
		if not preserve[child.Name] then
			child:Destroy()
		end
	end
end

local function configureVerticalLayout(container: Instance): UIListLayout?
	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if not layout then
		return nil
	end
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	return layout
end

local function getPaddingOffsetY(container: Instance): number
	local padding = container:FindFirstChildWhichIsA("UIPadding")
	if not padding then
		return 0
	end
	return padding.PaddingTop.Offset + padding.PaddingBottom.Offset
end

local function setVerticalPadding(container: Instance, topOffset: number, bottomOffset: number)
	local padding = container:FindFirstChildWhichIsA("UIPadding")
	if not padding then
		return
	end

	padding.PaddingTop = UDim.new(padding.PaddingTop.Scale, topOffset)
	padding.PaddingBottom = UDim.new(padding.PaddingBottom.Scale, bottomOffset)
end

local function ensurePadding(container: Instance, name: string): UIPadding
	local existing = container:FindFirstChild(name)
	if existing and existing:IsA("UIPadding") then
		return existing
	end

	local padding = Instance.new("UIPadding")
	padding.Name = name
	padding.Parent = container
	return padding
end

local function applyProfileInputPadding(row: TextButton)
	local rowPadding = ensurePadding(row, "RuntimeProfileInputPadding")
	rowPadding.PaddingLeft = UDim.new(0, PROFILE_INPUT_ROW_PADDING_X)
	rowPadding.PaddingRight = UDim.new(0, PROFILE_INPUT_ROW_PADDING_X)
	rowPadding.PaddingTop = UDim.new(0, PROFILE_INPUT_ROW_PADDING_Y)
	rowPadding.PaddingBottom = UDim.new(0, PROFILE_INPUT_ROW_PADDING_Y)
end

local function applyProfileInputAreaPadding(inputArea: Instance?)
	if not inputArea or not inputArea:IsA("GuiObject") then
		return
	end

	local padding = ensurePadding(inputArea, "RuntimeProfileInputAreaPadding")
	padding.PaddingLeft = UDim.new(0, PROFILE_INPUT_AREA_PADDING_X)
	padding.PaddingRight = UDim.new(0, PROFILE_INPUT_AREA_PADDING_X)
end

local function hasAutomaticYSize(gui: GuiObject): boolean
	return gui.AutomaticSize == Enum.AutomaticSize.Y or gui.AutomaticSize == Enum.AutomaticSize.XY
end

local function measureLayoutChildHeight(child: GuiObject): number
	if hasAutomaticYSize(child) and child.AbsoluteSize.Y > 0 then
		return child.AbsoluteSize.Y
	end

	if math.abs(child.Size.Y.Offset) > 0.001 then
		return child.Size.Y.Offset
	end

	if child.AbsoluteSize.Y > 0 then
		return child.AbsoluteSize.Y
	end

	return 0
end

local function measureVerticalLayoutHeight(container: GuiObject, layout: UIListLayout): number
	local total = 0
	local count = 0

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and child ~= layout then
			total += measureLayoutChildHeight(child)
			count += 1
		end
	end

	total += layout.Padding.Offset * math.max(count - 1, 0)
	return total
end

local function bindHeightToLayout(container: GuiObject, extraHeight: number?)
	local layout = configureVerticalLayout(container)
	if not layout then
		return
	end

	local function updateHeight()
		local currentSize = container.Size
		local height = math.ceil(measureVerticalLayoutHeight(container, layout) + (extraHeight or 0))
		container.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset, 0, math.max(height, 0))
	end

	local layoutConnection: RBXScriptConnection? = nil
	layoutConnection = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not container.Parent then
			if layoutConnection then
				layoutConnection:Disconnect()
				layoutConnection = nil
			end
			return
		end
		updateHeight()
	end)
	container.Destroying:Connect(function()
		if layoutConnection then
			layoutConnection:Disconnect()
			layoutConnection = nil
		end
	end)

	updateHeight()
	task.defer(updateHeight)
end

local function isPointInsideGui(gui: GuiObject?, point: Vector2): boolean
	if not gui or not gui.Visible then
		return false
	end

	local absolutePosition = gui.AbsolutePosition
	local absoluteSize = gui.AbsoluteSize
	return point.X >= absolutePosition.X
		and point.Y >= absolutePosition.Y
		and point.X <= absolutePosition.X + absoluteSize.X
		and point.Y <= absolutePosition.Y + absoluteSize.Y
end

local function cancelTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

local function getSidebarHiddenPosition(wrapper: GuiObject, shownPosition: UDim2): UDim2
	local width = wrapper.AbsoluteSize.X
	if width <= 1 then
		width = math.max(wrapper.Size.X.Offset, 240)
	end

	return UDim2.new(
		shownPosition.X.Scale,
		shownPosition.X.Offset + width + SIDEBAR_HIDDEN_MARGIN,
		shownPosition.Y.Scale,
		shownPosition.Y.Offset
	)
end

local function _fieldToDisplay(field: string, value: any): string
	if type(value) == "boolean" then
		return if value then "On" else "Off"
	end
	if type(value) == "number" then
		return tostring(math.floor(value + 0.5))
	end
	if type(value) == "string" then
		return PRETTY_VALUE[value] or value
	end
	return tostring(value)
end

local function setToggleVisual(row: TextButton, enabled: boolean)
	local toggle = row:FindFirstChild("Toggle")
	if not toggle or not toggle:IsA("Frame") then
		return
	end
	local shell = toggle:FindFirstChildWhichIsA("Frame")
	if shell then
		shell.BackgroundColor3 = enabled and Color3.fromRGB(223, 223, 223) or Color3.fromRGB(62, 62, 62)
		local inner = shell:FindFirstChildWhichIsA("Frame")
		if inner then
			inner.BackgroundColor3 = enabled and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
			inner.Position = enabled and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
			inner.AnchorPoint = Vector2.new(if enabled then 1 else 0, 0)
		end
	end
end

local function resolveGuiPixelHeight(gui: GuiObject, parentHeight: number): number
	local offset = gui.Size.Y.Offset
	if math.abs(offset) > 0.001 then
		return offset
	end

	local scale = gui.Size.Y.Scale
	if scale > 0 and parentHeight > 0 then
		return math.floor(parentHeight * scale + 0.5)
	end

	if gui.AbsoluteSize.Y > 0 then
		return gui.AbsoluteSize.Y
	end

	return 0
end

local function resolveSliderTemplateRowHeight(row: GuiObject): number
	if math.abs(row.Size.Y.Offset) > 0.001 then
		return row.Size.Y.Offset
	end
	if row.AbsoluteSize.Y > 0 then
		return row.AbsoluteSize.Y
	end
	return SLIDER_ROW_HEIGHT
end

local function applySliderRowSpacing(row: GuiObject)
	local padding = ensurePadding(row, "RuntimeSliderRowPadding")
	padding.PaddingLeft = UDim.new(0, SLIDER_ROW_PADDING_X)
	padding.PaddingRight = UDim.new(0, SLIDER_ROW_PADDING_X)
	padding.PaddingTop = UDim.new(0, SLIDER_ROW_PADDING_Y)
	padding.PaddingBottom = UDim.new(0, SLIDER_ROW_PADDING_Y)

	local layout = row:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, SLIDER_INNER_GAP)
	end
end

local function applyAdjustWrapperLayout(wrapper: Instance?, templateRowHeight: number)
	if not wrapper or not wrapper:IsA("GuiObject") then
		return
	end

	local gui = wrapper :: GuiObject
	local height = resolveGuiPixelHeight(gui, templateRowHeight)
	if height > 0 then
		-- Pin to Studio pixel height; row height is overridden at runtime (SLIDER_ROW_HEIGHT).
		gui.Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, height)
	end

	local corner = gui:FindFirstChildWhichIsA("UICorner")
	if corner then
		corner.CornerRadius = ADJUST_WRAPPER_CORNER_RADIUS
	end
end

local function setSliderPercentVisual(row: GuiObject, percent: number, displayText: string)
	local fillRoot = row:FindFirstChild("AdjustWrapper")
	if not fillRoot or not fillRoot:IsA("GuiObject") then
		return
	end
	local clampedPercent = math.clamp(percent, 0, 1)
	local widthFrame = fillRoot:FindFirstChild("AdjustableFrameWidth")
	if widthFrame and widthFrame:IsA("Frame") then
		widthFrame.Size = UDim2.new(clampedPercent, 0, 1, 0)
		local draggable = widthFrame:FindFirstChild("DraggableIcon")
		if draggable and draggable:IsA("ImageLabel") then
			draggable.AnchorPoint = Vector2.new(0.5, 0.5)
			draggable.Position = UDim2.new(1, 0, 0.5, 0)
		end
	end
	local valueLabel = row:FindFirstChild("SliderLabel")
	if valueLabel and valueLabel:IsA("Frame") then
		local current = valueLabel:FindFirstChild("SliderCurrentValue")
		if current and current:IsA("TextLabel") then
			current.Text = displayText
		end
	end
end

local function formatSliderValue(item: any, value: number): string
	return if item.format then item.format(value) else tostring(math.floor(value + 0.5))
end

local function setSliderVisual(row: GuiObject, item: any, value: number, minValue: number, maxValue: number)
	local percent = if maxValue > minValue then math.clamp((value - minValue) / (maxValue - minValue), 0, 1) else 0
	setSliderPercentVisual(row, percent, formatSliderValue(item, value))
end

local function snapSliderValue(raw: number, minValue: number, maxValue: number, step: number): number
	local snapped = math.floor((raw / step) + 0.5) * step
	return math.clamp(snapped, minValue, maxValue)
end

local function createSliderRow(
	template: GuiObject,
	parent: Instance,
	item: any,
	value: number,
	layoutOrder: number,
	onChange: (number) -> (),
	fieldRegistry: { [string]: FieldBinding }?,
	onDragActiveChanged: ((boolean) -> ())?
)
	local row = template:Clone()
	if not row:IsA("GuiObject") then
		return template
	end
	row.Name = item.field
	row.LayoutOrder = layoutOrder
	row.Visible = true
	row.Active = true
	local templateRowHeight = resolveSliderTemplateRowHeight(row)
	row.AutomaticSize = Enum.AutomaticSize.None
	row.Size = UDim2.new(1, 0, 0, SLIDER_ROW_HEIGHT)
	allowOverflow(row)
	row.Parent = parent
	applySliderRowSpacing(row)
	setSettingIcon(row, resolveSettingIcon(item))
	applyAdjustWrapperLayout(row:FindFirstChild("AdjustWrapper"), templateRowHeight)

	local currentValue = snapSliderValue(value, item.min, item.max, item.step or 1)
	local labelFrame = row:FindFirstChild("SliderLabel")
	if labelFrame and labelFrame:IsA("Frame") then
		local title = labelFrame:FindFirstChild("SectionTitle")
		if title and title:IsA("TextLabel") then
			title.Text = item.label
			applySettingsRowLabelStyle(title)
		end
		local valueLabel = labelFrame:FindFirstChild("SliderCurrentValue")
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = formatSliderValue(item, currentValue)
		end
	end

	setSliderVisual(row, item, currentValue, item.min, item.max)

	local dragging = false
	local connections = {} :: { RBXScriptConnection }
	local scrollingFrame = row:FindFirstAncestorWhichIsA("ScrollingFrame")
	local previousScrollingEnabled: boolean? = nil
	local function track(connection: RBXScriptConnection)
		table.insert(connections, connection)
	end

	local function applyFromX(x: number)
		local fillRoot = row:FindFirstChild("AdjustWrapper")
		if not fillRoot or not fillRoot:IsA("GuiObject") then
			return
		end
		local absPos = fillRoot.AbsolutePosition.X
		local absSize = fillRoot.AbsoluteSize.X
		local percent = math.clamp((x - absPos) / math.max(absSize, 1), 0, 1)
		local raw = item.min + (item.max - item.min) * percent
		local step = item.step or 1
		local nextValue = snapSliderValue(raw, item.min, item.max, step)
		setSliderPercentVisual(row, percent, formatSliderValue(item, nextValue))
		if nextValue == currentValue then
			return
		end
		currentValue = nextValue
		onChange(nextValue)
	end

	local function beginDrag(x: number)
		if not dragging and scrollingFrame then
			previousScrollingEnabled = scrollingFrame.ScrollingEnabled
			scrollingFrame.ScrollingEnabled = false
		end
		if not dragging and onDragActiveChanged then
			onDragActiveChanged(true)
		end
		dragging = true
		applyFromX(x)
	end

	local function endDrag()
		if scrollingFrame and previousScrollingEnabled ~= nil then
			scrollingFrame.ScrollingEnabled = previousScrollingEnabled
		end
		previousScrollingEnabled = nil
		dragging = false
		if onDragActiveChanged then
			onDragActiveChanged(false)
		end
		setSliderVisual(row, item, currentValue, item.min, item.max)
	end

	local button = row:FindFirstChild("AdjustWrapper")
	if button and button:IsA("GuiObject") then
		button.Active = true
		track(button.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginDrag(input.Position.X)
			end
		end))

		local draggable = button:FindFirstChild("AdjustableFrameWidth")
		if draggable and draggable:IsA("Frame") then
			draggable.Active = true
			track(draggable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					beginDrag(input.Position.X)
				end
			end))

			local dragButton = draggable:FindFirstChild("DraggableIcon")
			if dragButton and dragButton:IsA("ImageLabel") then
				dragButton.Active = true
				track(dragButton.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						beginDrag(input.Position.X)
					end
				end))
			end
		end
	end

	track(UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if dragging then
				endDrag()
			end
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			applyFromX(input.Position.X)
		end
	end))

	track(row.Destroying:Connect(function()
		if dragging and onDragActiveChanged then
			onDragActiveChanged(false)
		end
		if scrollingFrame and previousScrollingEnabled ~= nil then
			scrollingFrame.ScrollingEnabled = previousScrollingEnabled
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end))

	if fieldRegistry and type(item.field) == "string" then
		fieldRegistry[item.field] = {
			kind = "slider",
			field = item.field,
			item = item,
			row = row,
			setValue = function(nextValue: number)
				currentValue = snapSliderValue(nextValue, item.min, item.max, item.step or 1)
				setSliderVisual(row, item, currentValue, item.min, item.max)
			end,
		}
	end

	return row
end

local function createToggleRow(
	template: TextButton,
	parent: Instance,
	item: any,
	value: boolean,
	layoutOrder: number,
	onChange: (boolean) -> (),
	fieldRegistry: { [string]: FieldBinding }?
)
	local row = template:Clone()
	row.Name = item.field
	row.LayoutOrder = layoutOrder
	row.Visible = true
	row.AutomaticSize = Enum.AutomaticSize.None
	row.Size = UDim2.new(1, 0, 0, TOGGLE_ROW_HEIGHT)
	allowOverflow(row)
	row.Parent = parent
	disableAutoButtonColor(row)

	local currentValue = value == true
	setTextLabelText(row, item.label)
	setSettingIcon(row, resolveSettingIcon(item))
	setToggleVisual(row, currentValue)

	row.Activated:Connect(function()
		currentValue = not currentValue
		setToggleVisual(row, currentValue)
		onChange(currentValue)
	end)

	if fieldRegistry and type(item.field) == "string" then
		fieldRegistry[item.field] = {
			kind = "toggle",
			field = item.field,
			item = item,
			row = row,
			setValue = function(nextValue: boolean)
				currentValue = nextValue == true
				setToggleVisual(row, currentValue)
			end,
		}
	end

	return row
end

local function isMappedToggleEnabled(item: any, resolved: any): boolean
	if item.valueMap then
		return resolved == item.valueMap.on
	end
	return resolved == true
end

local function resolveSegmentedButtonFrame(row: GuiObject): Instance?
	local groupRoot = row:FindFirstChild("CanvasGroup")
		or row:FindFirstChildWhichIsA("CanvasGroup")
		or row:FindFirstChildWhichIsA("Frame")
	if not groupRoot or not groupRoot:IsA("GuiObject") then
		return nil
	end
	return groupRoot:FindFirstChildWhichIsA("Frame")
end

local function setSegmentedButtonVisual(button: TextButton, label: string, selected: boolean, iconImage: string?)
	button.Text = ""
	button.BackgroundTransparency = if selected then 0 else 0.95
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	local color = if selected then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(255, 255, 255)
	setSettingIcon(button, iconImage)
	setTextAndIconColor(button, color)
	setTextLabelText(button, label)
end

local function createSegmentedRow(
	template: GuiObject,
	parent: Instance,
	item: any,
	value: string,
	layoutOrder: number,
	onChange: (string) -> (),
	fieldRegistry: { [string]: FieldBinding }?
)
	local row = template:Clone()
	if not row:IsA("GuiObject") then
		return template
	end
	row.Name = item.field
	row.LayoutOrder = layoutOrder
	row.Visible = true
	allowOverflow(row)
	row.Parent = parent
	disableAutoButtonColor(row)

	local titleFrame = row:FindFirstChild("SectionTitle", true)
	if titleFrame and titleFrame:IsA("TextLabel") then
		titleFrame.Text = item.label
		applySettingsRowLabelStyle(titleFrame)
	end

	local buttonHolder = resolveSegmentedButtonFrame(row)
	if not buttonHolder then
		return row
	end

	local buttons = collectButtons(buttonHolder)
	local optionCount = math.min(#item.options, 3)
	local baseButton = buttons[#buttons]
	local currentValue = value
	local optionLabels = {} :: { [TextButton]: string }
	local optionValues = {} :: { [TextButton]: string }
	local optionIcons = {} :: { [TextButton]: string }
	setSettingIcon(row, resolveSettingIcon(item))
	for i = #buttons + 1, optionCount do
		if baseButton then
			local cloned = baseButton:Clone()
			cloned.Parent = buttonHolder
			table.insert(buttons, cloned)
		end
	end

	local function updateButtons()
		for button, optionLabel in pairs(optionLabels) do
			setSegmentedButtonVisual(button, optionLabel, optionValues[button] == currentValue, optionIcons[button])
		end
	end

	for i, button in ipairs(buttons) do
		local option = if i <= optionCount then item.options[i] else nil
		if option then
			local optionLabel = if type(option) == "table"
				then tostring(option.label or option.value or "")
				else tostring(option)
			local optionValue = if type(option) == "table"
				then tostring(option.value or option.label or "")
				else tostring(option)
			button.Name = "Option_" .. optionValue
			button.Visible = true
			optionLabels[button] = optionLabel
			optionValues[button] = optionValue
			optionIcons[button] = resolveOptionIcon(option)
			setSegmentedButtonVisual(button, optionLabel, optionValue == currentValue, optionIcons[button])
			button.Activated:Connect(function()
				if optionValue == currentValue then
					return
				end
				currentValue = optionValue
				updateButtons()
				onChange(optionValue)
			end)
		else
			button.Visible = false
		end
	end

	if fieldRegistry and type(item.field) == "string" then
		fieldRegistry[item.field] = {
			kind = "segmented",
			field = item.field,
			item = item,
			row = row,
			setValue = function(nextValue: string)
				currentValue = tostring(nextValue)
				updateButtons()
			end,
		}
	end

	return row
end

local function getOptionValue(option: any): string
	if type(option) == "table" then
		return tostring(option.value or option.label or "")
	end
	return tostring(option)
end

local function createSection(
	template: GuiObject,
	parent: Instance,
	def: any,
	payload: SettingsPayload,
	onChange: ChangeCallback,
	fieldRegistry: { [string]: FieldBinding }?,
	sliderDragHandlers: { [string]: (boolean) -> () }?
)
	local section = template:Clone()
	if not section:IsA("GuiObject") then
		return template
	end
	section.Name = def.key .. "_Section"
	section.Visible = true
	section.AutomaticSize = Enum.AutomaticSize.None
	section.Size = UDim2.new(section.Size.X.Scale, section.Size.X.Offset, 0, 0)
	allowOverflow(section)
	section.Parent = parent
	setVerticalPadding(section, SECTION_VERTICAL_PADDING, SECTION_VERTICAL_PADDING)
	local sectionLayout = configureVerticalLayout(section)
	if sectionLayout then
		sectionLayout.Padding = UDim.new(0, SECTION_TITLE_CONTENT_GAP)
	end

	local identity = findFirstDescendantByNames(section, { "SectionIdentity" })
	if identity then
		setIdentityTitleText(identity, SECTION_IDENTITY_TITLE_NAMES, def.title)
		setIdentitySubtitleText(identity, SECTION_IDENTITY_SUBTITLE_NAMES, def.subtitle)
		applySectionIdentityStyle(identity)
	end

	local contentWrapper = findFirstDescendantByNames(section, { "SectionContentWrapper", "SectionContentWraooer" })
	local contentWrapperGui = asGuiObject(contentWrapper)
	if not contentWrapperGui then
		return section
	end

	contentWrapperGui.AutomaticSize = Enum.AutomaticSize.None
	contentWrapperGui.Size = UDim2.new(contentWrapperGui.Size.X.Scale, contentWrapperGui.Size.X.Offset, 0, 0)
	allowOverflow(contentWrapperGui)
	local contentPadding = ensurePadding(contentWrapperGui, "RuntimeSectionContentPadding")
	contentPadding.PaddingTop = UDim.new(0, SECTION_CONTENT_PADDING_TOP)

	local rawTemplateSlider = contentWrapperGui:FindFirstChild("Slider")
	local rawTemplateToggleEnabled = contentWrapperGui:FindFirstChild("BasicToggleEnabled")
	local rawTemplateToggleDisabled = contentWrapperGui:FindFirstChild("BasicToggleDisabled")
	local rawTemplateToggle = contentWrapperGui:FindFirstChild("BasicToggle")
	local rawTemplateSegmented = contentWrapperGui:FindFirstChild("MultiOption")
	local templateSlider = if rawTemplateSlider and rawTemplateSlider:IsA("Frame")
		then rawTemplateSlider:Clone()
		else nil
	local templateToggleEnabled = if rawTemplateToggleEnabled and rawTemplateToggleEnabled:IsA("TextButton")
		then rawTemplateToggleEnabled:Clone()
		else nil
	local templateToggleDisabled = if rawTemplateToggleDisabled and rawTemplateToggleDisabled:IsA("TextButton")
		then rawTemplateToggleDisabled:Clone()
		else nil
	local templateToggle = if rawTemplateToggle and rawTemplateToggle:IsA("TextButton")
		then rawTemplateToggle:Clone()
		else nil
	local templateSegmented = if rawTemplateSegmented and rawTemplateSegmented:IsA("Frame")
		then rawTemplateSegmented:Clone()
		else nil

	if rawTemplateSlider then
		rawTemplateSlider:Destroy()
	end
	if rawTemplateToggleEnabled then
		rawTemplateToggleEnabled:Destroy()
	end
	if rawTemplateToggleDisabled then
		rawTemplateToggleDisabled:Destroy()
	end
	if rawTemplateToggle then
		rawTemplateToggle:Destroy()
	end
	if rawTemplateSegmented then
		rawTemplateSegmented:Destroy()
	end

	local preserve = {
		UICorner = true,
		UIListLayout = true,
		UIStroke = true,
	}
	clearSectionContent(contentWrapperGui, preserve)
	local contentLayout = configureVerticalLayout(contentWrapperGui)
	if contentLayout then
		contentLayout.Padding = UDim.new(0, SECTION_CONTENT_ROW_GAP)
	end

	local nextLayoutOrder = 1
	for _, item in ipairs(def.items) do
		local parentTarget = contentWrapperGui
		local field = item.field
		local parts = {}
		for token in string.gmatch(field, "[^%.]+") do
			table.insert(parts, token)
		end
		local resolved: any = payload
		for _, part in ipairs(parts) do
			if type(resolved) ~= "table" then
				resolved = nil
				break
			end
			resolved = resolved[part]
		end
		if field == "hotbarZoom" and resolved == nil then
			resolved = 200
		end

		if item.kind == "slider" and templateSlider then
			createSliderRow(
				templateSlider,
				parentTarget,
				item,
				tonumber(resolved) or item.min,
				nextLayoutOrder,
				function(nextValue)
					onChange(item.field, nextValue)
				end,
				fieldRegistry,
				if sliderDragHandlers then sliderDragHandlers[item.field] else nil
			)
			nextLayoutOrder += 1
		elseif item.kind == "toggle" then
			local isEnabled = isMappedToggleEnabled(item, resolved)
			local selectedTemplate = if isEnabled then templateToggleEnabled else templateToggleDisabled
			if not selectedTemplate then
				selectedTemplate = templateToggle
			end
			if selectedTemplate then
				createToggleRow(
					selectedTemplate,
					parentTarget,
					item,
					isEnabled,
					nextLayoutOrder,
					function(nextValue)
						if item.valueMap then
							onChange(item.field, if nextValue then item.valueMap.on else item.valueMap.off)
						else
							onChange(item.field, nextValue)
						end
					end,
					fieldRegistry
				)
				nextLayoutOrder += 1
			end
		elseif item.kind == "segmented" and templateSegmented then
			local defaultOption = item.options[1]
			createSegmentedRow(
				templateSegmented,
				parentTarget,
				item,
				tostring(resolved or getOptionValue(defaultOption)),
				nextLayoutOrder,
				function(nextValue)
					onChange(item.field, nextValue)
				end,
				fieldRegistry
			)
			nextLayoutOrder += 1
		end
	end

	bindHeightToLayout(contentWrapperGui, 0)
	bindHeightToLayout(section, getPaddingOffsetY(section))

	return section
end
local function resolveFieldValue(root: any, field: string): any
	local resolved = root
	for token in string.gmatch(field, "[^%.]+") do
		if type(resolved) ~= "table" then
			return nil
		end
		resolved = resolved[token]
	end
	return resolved
end

local function assignFieldValue(root: any, field: string, value: any)
	local tokens = {}
	for token in string.gmatch(field, "[^%.]+") do
		table.insert(tokens, token)
	end
	if #tokens == 0 then
		return
	end
	local cursor = root
	for index = 1, #tokens - 1 do
		local token = tokens[index]
		if type(cursor[token]) ~= "table" then
			cursor[token] = {}
		end
		cursor = cursor[token]
	end
	cursor[tokens[#tokens]] = value
end

local MenuSettingsCore = {}

MenuSettingsCore.SECTION_LIST_GAP = SECTION_LIST_GAP
MenuSettingsCore.createSection = createSection
MenuSettingsCore.getSettingsSectionDefs = getSettingsSectionDefs
MenuSettingsCore.shouldShowSettingsItem = shouldShowSettingsItem
MenuSettingsCore.resolveFieldValue = resolveFieldValue
MenuSettingsCore.assignFieldValue = assignFieldValue
MenuSettingsCore.isMappedToggleEnabled = isMappedToggleEnabled
MenuSettingsCore.getOptionValue = getOptionValue
MenuSettingsCore.configureVerticalLayout = configureVerticalLayout
MenuSettingsCore.setVerticalPadding = setVerticalPadding
MenuSettingsCore.setTextLabelText = setTextLabelText
MenuSettingsCore.findFirstDescendantByNames = findFirstDescendantByNames
MenuSettingsCore.applyTabPageIdentity = function(tab: ScrollingFrame, title: string, subtitle: string?)
	applyTabPageIdentity(tab, title, subtitle or "")
end
MenuSettingsCore.applySettingsTabPageIdentity = function(settingsTab: ScrollingFrame, title: string?, subtitle: string?)
	applyTabPageIdentity(
		settingsTab,
		if type(title) == "string" and title ~= "" then title else SETTINGS_TAB_PAGE_TITLE,
		if subtitle ~= nil then subtitle else SETTINGS_TAB_PAGE_SUBTITLE
	)
end
MenuSettingsCore.applyProfileTabPageIdentity = function(profileTab: ScrollingFrame, title: string?, subtitle: string?)
	applyTabPageIdentity(
		profileTab,
		if type(title) == "string" and title ~= "" then title else PROFILE_TAB_PAGE_TITLE,
		if subtitle ~= nil then subtitle else PROFILE_TAB_PAGE_SUBTITLE
	)
end

return MenuSettingsCore
