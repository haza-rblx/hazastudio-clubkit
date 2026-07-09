--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

local DancePanelGuiRefs = {}

export type Refs = {
	screenGui: ScreenGui,
	triggerButton: GuiButton,
	triggerButtonInner: GuiButton?,
	panelRoot: GuiObject,
	panelDragDetector: UIDragDetector?,
	draggableFrame: GuiObject,
	danceTabButton: GuiButton,
	poseTabButton: GuiButton,
	favoritesTabButton: GuiButton?,
	backgroundPill: GuiObject?,
	tabButtonOrder: { GuiButton },
	mainContentWrapper: CanvasGroup,
	searchBox: TextBox,
	mainContent: ScrollingFrame,
	speedWrapper: GuiObject,
	speedFill: Frame,
	speedHandle: GuiObject,
	speedHandleButton: GuiButton?,
	speedSliderVertical: boolean,
	currentSpeedLabel: TextLabel?,
	maxSpeedLabel: TextLabel?,
	paginationWrapper: GuiObject?,
	previousButton: GuiButton?,
	nextButton: GuiButton?,
	customSpeedWrapper: GuiObject?,
	customSpeedField: TextBox?,
	resetSpeedButton: GuiButton?,
	syncOverlay: GuiButton,
	syncLeaderLabel: TextLabel?,
	syncTapLabel: TextLabel?,
	syncAutoRouteLabel: TextLabel?,
	rowRefs: {
		normal: GuiButton,
		played: GuiButton,
		favorited: GuiButton,
		favoritedPlayed: GuiButton,
	},
}

local function expectChild(parent: Instance, name: string, className: string): Instance
	local child = parent:WaitForChild(name, 15)
	assert(child, string.format("Missing child %s under %s", name, parent:GetFullName()))
	assert(child:IsA(className), string.format("Expected %s to be %s, got %s", child:GetFullName(), className, child.ClassName))
	return child
end

local function asButton(instance: Instance): GuiButton
	assert(instance:IsA("GuiButton"), string.format("Expected button, got %s at %s", instance.ClassName, instance:GetFullName()))
	return instance
end

local function normalizeVersion(config: any?): string
	local syncConfig = if config then config.Sync else Config.Sync
	local configuredVersion = if syncConfig then syncConfig.DANCE_PANEL_UI_VERSION else nil
	if configuredVersion == "v2" then
		return "v2"
	end
	return "v1"
end

local function getPanelRootName(config: any?, version: string): string
	local syncConfig = if config then config.Sync else Config.Sync
	local roots = if syncConfig then syncConfig.DANCE_PANEL_UI_ROOTS else nil
	if type(roots) == "table" and type(roots[version]) == "string" then
		return roots[version]
	end
	return if version == "v2" then "DancePanelGUIWrapperv2" else "DancePanelGUIWrapper"
end

local function getPanelLabel(config: any?, version: string, layoutKind: string): string
	local syncConfig = if config then config.Sync else Config.Sync
	local labels = if syncConfig then syncConfig.DANCE_PANEL_UI_LABELS else nil
	if layoutKind == "mobile" and type(labels) == "table" and type(labels.v2Mobile) == "string" then
		return labels.v2Mobile
	end
	if type(labels) == "table" and type(labels[version]) == "string" then
		return labels[version]
	end
	return if version == "v2" then "Dance Panel V2" else "Dance Panel"
end

local function getActivePanelRootName(config: any?, version: string): (string, string)
	local syncConfig = if config then config.Sync else Config.Sync
	local useMobileLayout = syncConfig.DANCE_PANEL_USE_MOBILE_LAYOUT ~= false

	if version ~= "v2" or not useMobileLayout then
		return getPanelRootName(config, version), "desktop"
	end

	if PhoneLayout.isPhoneLayout() then
		local roots = syncConfig.DANCE_PANEL_UI_ROOTS
		local mobileName = if type(roots) == "table" and type(roots.v2Mobile) == "string"
			then roots.v2Mobile
			else "DancePanelGUIWrapperv2Mobile"
		return mobileName, "mobile"
	end

	return getPanelRootName(config, version), "desktop"
end

local function getContentRoot(panelRoot: GuiObject): GuiObject
	local mainWrapper = panelRoot:FindFirstChild("MainWrapper")
	if mainWrapper and mainWrapper:IsA("GuiObject") then
		return mainWrapper :: GuiObject
	end
	return panelRoot
end

local function resolveSpeedRefs(panelRoot: GuiObject, mainContentWrapper: GuiObject, layoutKind: string): {
	speedWrapper: GuiObject,
	speedFill: Frame,
	speedHandle: GuiObject,
	speedHandleButton: GuiButton?,
	currentSpeedLabel: TextLabel?,
	maxSpeedLabel: TextLabel?,
	speedSliderVertical: boolean,
}
	local speedWrapper: GuiObject? = nil
	local panelSpeed = panelRoot:FindFirstChild("AdjustSpeedWrapper")
	if panelSpeed and panelSpeed:IsA("GuiObject") then
		speedWrapper = panelSpeed
	end
	if not speedWrapper then
		local contentSpeed = mainContentWrapper:FindFirstChild("AdjustSpeedWrapper")
		if contentSpeed and contentSpeed:IsA("GuiObject") then
			speedWrapper = contentSpeed
		end
	end

	assert(
		speedWrapper,
		string.format("Missing AdjustSpeedWrapper under %s or %s", panelRoot:GetFullName(), mainContentWrapper:GetFullName())
	)

	local speedFill = speedWrapper:FindFirstChild("AdjustableFrameWidth")
	assert(speedFill and speedFill:IsA("Frame"), string.format("Missing AdjustableFrameWidth under %s", speedWrapper:GetFullName()))

	local speedHandle: GuiObject = speedFill
	local dragIcon = speedFill:FindFirstChild("DraggableIcon")
	if dragIcon and dragIcon:IsA("GuiObject") then
		speedHandle = dragIcon
	end

	local speedHandleButton = speedHandle:FindFirstChildWhichIsA("GuiButton")

	local currentSpeedLabel = speedWrapper:FindFirstChild("CurrentSpeedTextLabel")
	local maxSpeedLabel = speedWrapper:FindFirstChild("MaximumSpeedTextLabel")
	if currentSpeedLabel and not currentSpeedLabel:IsA("TextLabel") then
		currentSpeedLabel = nil
	end
	if maxSpeedLabel and not maxSpeedLabel:IsA("TextLabel") then
		maxSpeedLabel = nil
	end

	local abs = speedWrapper.AbsoluteSize
	local sizeSuggestsVertical = abs.X > 0 and abs.Y > 0 and abs.X < abs.Y
	local speedSliderVertical = layoutKind == "mobile" or sizeSuggestsVertical

	return {
		speedWrapper = speedWrapper,
		speedFill = speedFill :: Frame,
		speedHandle = speedHandle,
		speedHandleButton = speedHandleButton,
		currentSpeedLabel = currentSpeedLabel :: TextLabel?,
		maxSpeedLabel = maxSpeedLabel :: TextLabel?,
		speedSliderVertical = speedSliderVertical,
	}
end

local DANCE_TAB_SPECS = {
	{
		key = "Dance",
		legacyNames = { "DancePanelTabButton" },
		optionIndex = 1,
		defaultLabel = "Dance",
	},
	{
		key = "Favorites",
		legacyNames = { "FavoritesPanelTabButton" },
		optionIndex = 2,
		defaultLabel = "Fav",
	},
	{
		key = "Pose",
		legacyNames = { "PosePanelTabButton" },
		optionIndex = 3,
		defaultLabel = "Pose",
	},
}

local DANCE_TAB_LAYOUT_ORDER = {
	Dance = 1,
	Favorites = 2,
	Pose = 3,
}

local SLIDER_SELECTOR_NAMES = { "2-SliderSelector", "SliderSelector" }

local function applyDanceTabLabel(button: GuiButton, labelText: string)
	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = labelText
	elseif button:IsA("TextButton") then
		button.Text = labelText
	end
end

local function findSliderSelectorOuter(headerWrapper: Instance): GuiObject?
	for _, name in ipairs(SLIDER_SELECTOR_NAMES) do
		local direct = headerWrapper:FindFirstChild(name)
		if direct and direct:IsA("GuiObject") then
			return direct :: GuiObject
		end
	end
	return nil
end

local function resolveHeaderTabs(headerWrapper: GuiObject, layoutKind: string): (
	GuiButton,
	GuiButton,
	GuiButton?,
	GuiObject?,
	{ GuiButton }
)
	local sliderOuter = if layoutKind == "desktop" then findSliderSelectorOuter(headerWrapper) else nil
	if sliderOuter then
		local container = SliderSelectorUtil.getOptionsContainer(sliderOuter)
		local backgroundPill = SliderSelectorUtil.getBackgroundPill(sliderOuter)
		local allButtons = SliderSelectorUtil.collectTabButtons(container)

		local tabButtonOrder: { GuiButton } = {}
		local resolved: { [string]: GuiButton } = {}

		for _, spec in ipairs(DANCE_TAB_SPECS) do
			local button = SliderSelectorUtil.resolveTabButton(container, {
				legacyNames = spec.legacyNames,
				optionIndex = spec.optionIndex,
				defaultLabel = spec.defaultLabel,
			}, allButtons)
			if button then
				local layoutOrder = DANCE_TAB_LAYOUT_ORDER[spec.key]
				if layoutOrder then
					button.LayoutOrder = layoutOrder
				end
				resolved[spec.key] = button
				table.insert(tabButtonOrder, button)
				applyDanceTabLabel(button, spec.defaultLabel)
			end
		end

		assert(
			resolved.Dance and resolved.Pose,
			string.format(
				"DancePanelGuiRefs: missing Dance/Pose tabs under %s (expected Option1/3 or legacy names)",
				container:GetFullName()
			)
		)

		return resolved.Dance, resolved.Pose, resolved.Favorites, backgroundPill, tabButtonOrder
	end

	local selector = expectChild(headerWrapper, "2-Selector", "GuiObject") :: GuiObject
	local danceTabButton = asButton(expectChild(selector, "DancePanelTabButton", "GuiButton") :: GuiButton)
	local poseTabButton = asButton(expectChild(selector, "PosePanelTabButton", "GuiButton") :: GuiButton)
	local favoritesTabButtonCandidate = selector:FindFirstChild("FavoritesPanelTabButton")
	local favoritesTabButton = if favoritesTabButtonCandidate and favoritesTabButtonCandidate:IsA("GuiButton")
		then favoritesTabButtonCandidate :: GuiButton
		else nil

	local tabButtonOrder: { GuiButton } = { danceTabButton }
	if favoritesTabButton then
		table.insert(tabButtonOrder, favoritesTabButton)
	end
	table.insert(tabButtonOrder, poseTabButton)

	applyDanceTabLabel(danceTabButton, "Dance")
	applyDanceTabLabel(poseTabButton, "Pose")
	if favoritesTabButton then
		applyDanceTabLabel(favoritesTabButton, "Fav")
	end

	return danceTabButton, poseTabButton, favoritesTabButton, nil, tabButtonOrder
end

local function collectInactivePanelNames(config: any?): { string }
	local syncConfig = if config then config.Sync else Config.Sync
	local roots = if syncConfig then syncConfig.DANCE_PANEL_UI_ROOTS else nil
	local names: { string } = {}
	if type(roots) ~= "table" then
		return names
	end
	for _, name in pairs(roots) do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	return names
end

function DancePanelGuiRefs.resolve(playerGui: PlayerGui, config: any?): Refs
	local screenGui = expectChild(playerGui, "IconGroup", "ScreenGui") :: ScreenGui
	local triggerButton = asButton(expectChild(screenGui, "DancePanelButton", "ImageButton") :: ImageButton)
	local triggerButtonInner = triggerButton:FindFirstChild("DancePanelButton")
	if triggerButtonInner and not triggerButtonInner:IsA("GuiButton") then
		triggerButtonInner = nil
	end

	local version = normalizeVersion(config)
	local panelRootName, layoutKind = getActivePanelRootName(config, version)

	local panelRootCandidate = screenGui:FindFirstChild(panelRootName)
	if layoutKind == "mobile" and (panelRootCandidate == nil or not panelRootCandidate:IsA("GuiObject")) then
		error(
			"[DancePanel] Missing DancePanelGUIWrapperv2Mobile under IconGroup for phone layout. "
				.. "Add the mobile panel instance to the place or set DANCE_PANEL_USE_MOBILE_LAYOUT = false."
		)
	end

	local panelRoot = expectChild(screenGui, panelRootName, "GuiObject") :: GuiObject
	local panelLabel = getPanelLabel(config, version, layoutKind)
	panelRoot:SetAttribute("DancePanelVersion", version)
	panelRoot:SetAttribute("DancePanelLabel", panelLabel)
	panelRoot:SetAttribute("DancePanelLayout", layoutKind)
	triggerButton:SetAttribute("DancePanelLabel", panelLabel)

	if layoutKind == "mobile" then
		local syncConfig = if config then config.Sync else Config.Sync
		local bakedScale = panelRoot:FindFirstChild("UIScale")
		if bakedScale and bakedScale:IsA("UIScale") then
			local targetScale = tonumber(syncConfig.DANCE_PANEL_V2_SCALE_MOBILE) or 0.75
			bakedScale.Scale = targetScale
		end
	end

	for _, inactiveName in ipairs(collectInactivePanelNames(config)) do
		if inactiveName ~= panelRootName then
			local inactiveRoot = screenGui:FindFirstChild(inactiveName)
			if inactiveRoot and inactiveRoot:IsA("GuiObject") then
				inactiveRoot.Visible = false
			end
		end
	end

	local contentRoot = getContentRoot(panelRoot)
	local panelDragDetector = panelRoot:FindFirstChildWhichIsA("UIDragDetector")
	local draggableFrame = expectChild(contentRoot, "01-DraggableFrame", "Frame") :: Frame

	local headerWrapper = expectChild(contentRoot, "02-HeaderWrapper", "GuiObject") :: GuiObject
	local danceTabButton, poseTabButton, favoritesTabButton, backgroundPill, tabButtonOrder =
		resolveHeaderTabs(headerWrapper, layoutKind)

	local mainContentWrapper = expectChild(contentRoot, "03-MainContentWrapper", "CanvasGroup") :: CanvasGroup
	local searchBox = expectChild(mainContentWrapper, "SearchDanceorPose", "TextBox") :: TextBox
	local mainContent = expectChild(mainContentWrapper, "MainContent", "ScrollingFrame") :: ScrollingFrame

	local speedRefs = resolveSpeedRefs(panelRoot, mainContentWrapper, layoutKind)

	local syncOverlay = asButton(expectChild(mainContentWrapper, "SyncedIndicatorandTaptoUnsyncButton", "TextButton") :: TextButton)
	local syncLeaderLabel = syncOverlay:FindFirstChild("1-SyncedTextLabel")
	local syncTapLabel = syncOverlay:FindFirstChild("2-TaptoUnsyncTextLabel")
	local syncAutoRouteLabel = syncOverlay:FindFirstChild("3-AutoReRouteIndicator")
	if syncLeaderLabel and not syncLeaderLabel:IsA("TextLabel") then
		syncLeaderLabel = nil
	end
	if syncTapLabel and not syncTapLabel:IsA("TextLabel") then
		syncTapLabel = nil
	end
	if syncAutoRouteLabel and not syncAutoRouteLabel:IsA("TextLabel") then
		syncAutoRouteLabel = nil
	end

	local paginationWrapper = contentRoot:FindFirstChild("04-PaginationArrow")
	local previousButton = nil :: GuiButton?
	local nextButton = nil :: GuiButton?
	if paginationWrapper then
		assert(paginationWrapper:IsA("GuiObject"), string.format("Expected %s to be GuiObject", paginationWrapper:GetFullName()))
		previousButton = asButton(expectChild(paginationWrapper, "PreviousButton", "GuiButton") :: GuiButton)
		nextButton = asButton(expectChild(paginationWrapper, "NextButton", "GuiButton") :: GuiButton)
	end

	local customSpeedWrapper = contentRoot:FindFirstChild("04-CustomSpeed")
	local customSpeedField = nil :: TextBox?
	local resetSpeedButton = nil :: GuiButton?
	if customSpeedWrapper then
		assert(customSpeedWrapper:IsA("GuiObject"), string.format("Expected %s to be GuiObject", customSpeedWrapper:GetFullName()))

		local speedField = customSpeedWrapper:FindFirstChild("CustomSpeedField")
		if speedField and speedField:IsA("TextBox") then
			customSpeedField = speedField
		end

		local resetButton = customSpeedWrapper:FindFirstChild("ResetSpeedButton")
		if resetButton and resetButton:IsA("GuiButton") then
			resetSpeedButton = resetButton
		end
	end

	local rowRefs = {
		normal = asButton(expectChild(mainContent, "NormalState", "TextButton") :: TextButton),
		played = asButton(expectChild(mainContent, "PlayedState", "TextButton") :: TextButton),
		favorited = asButton(expectChild(mainContent, "FavoritedState", "TextButton") :: TextButton),
		favoritedPlayed = asButton(expectChild(mainContent, "FavoritedStateandPlayed", "TextButton") :: TextButton),
	}

	return {
		screenGui = screenGui,
		triggerButton = triggerButton,
		triggerButtonInner = triggerButtonInner :: GuiButton?,
		panelRoot = panelRoot,
		panelDragDetector = panelDragDetector,
		draggableFrame = draggableFrame,
		danceTabButton = danceTabButton,
		poseTabButton = poseTabButton,
		favoritesTabButton = favoritesTabButton,
		backgroundPill = backgroundPill,
		tabButtonOrder = tabButtonOrder,
		mainContentWrapper = mainContentWrapper,
		searchBox = searchBox,
		mainContent = mainContent,
		speedWrapper = speedRefs.speedWrapper,
		speedFill = speedRefs.speedFill,
		speedHandle = speedRefs.speedHandle,
		speedHandleButton = speedRefs.speedHandleButton,
		speedSliderVertical = speedRefs.speedSliderVertical,
		currentSpeedLabel = speedRefs.currentSpeedLabel,
		maxSpeedLabel = speedRefs.maxSpeedLabel,
		paginationWrapper = paginationWrapper :: GuiObject?,
		previousButton = previousButton,
		nextButton = nextButton,
		customSpeedWrapper = customSpeedWrapper :: GuiObject?,
		customSpeedField = customSpeedField,
		resetSpeedButton = resetSpeedButton,
		syncOverlay = syncOverlay,
		syncLeaderLabel = syncLeaderLabel :: TextLabel?,
		syncTapLabel = syncTapLabel :: TextLabel?,
		syncAutoRouteLabel = syncAutoRouteLabel :: TextLabel?,
		rowRefs = rowRefs,
	}
end

return DancePanelGuiRefs
