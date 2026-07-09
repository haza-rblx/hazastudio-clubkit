--!strict
-- Resolve 07-MenuGUI tree (v2 layout) into typed refs.

local Config = require(game:GetService("ReplicatedStorage").Hazastudio_ClubKit.Shared.Constants.Config)

export type EditableInputRefs = {
	row: TextButton,
	valueBox: TextBox?,
	actionButton: ImageButton?,
}

export type TabButtonRefs = {
	profileButton: TextButton?,
	settingsButton: TextButton?,
	profileIdle: TextButton?,
	profileActive: TextButton?,
	settingsIdle: TextButton?,
	settingsActive: TextButton?,
}

export type MenuGuiRefs = {
	root: ScreenGui,
	outerWrapper: GuiObject,
	contentWrapper: GuiObject,
	gradientOverlay: Frame?,
	profileTab: ScrollingFrame,
	settingsTab: ScrollingFrame,
	tabWrapper: GuiObject?,
	tabSwitcher: ScrollingFrame?,
	tabButtons: TabButtonRefs,
	universalModal: GuiObject?,
	modalTitle: TextLabel?,
	modalInput: TextBox?,
	modalCancelButton: TextButton?,
	modalUpdateButton: TextButton?,
	avatarViewport: ViewportFrame?,
	displayNameLabel: TextLabel?,
	usernameLabel: TextLabel?,
	badgeGroup: Frame?,
	statusPopup: GuiButton?,
	statusPopupFrame: GuiObject?,
	statusPopupLabel: TextLabel?,
	bioContent: TextLabel?,
	relationshipLine: TextLabel?,
	streakCountLabel: TextLabel?,
	coupleSingle: TextButton?,
	coupleTaken: TextButton?,
	coupleFun: TextButton?,
	showCoupleToggle: TextButton?,
	displayNameInput: EditableInputRefs?,
	specialTitleInput: EditableInputRefs?,
	bioInput: EditableInputRefs?,
	statusInput: EditableInputRefs?,
	settingsSectionTemplate: GuiObject?,
	settingsResetButton: TextButton?,
	profileTabIdentity: GuiObject?,
	profileTabTitle: TextLabel?,
	profileTabSubtitle: TextLabel?,
	settingsTabIdentity: GuiObject?,
	settingsTabTitle: TextLabel?,
	settingsTabSubtitle: TextLabel?,
}

local MenuGuiRefsModule = {}

local function asGuiObject(inst: Instance?): GuiObject?
	if inst and inst:IsA("GuiObject") then
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

local function asTextLabel(inst: Instance?): TextLabel?
	if inst and inst:IsA("TextLabel") then
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

local function asViewport(inst: Instance?): ViewportFrame?
	if inst and inst:IsA("ViewportFrame") then
		return inst
	end
	return nil
end

local function asImageButton(inst: Instance?): ImageButton?
	if inst and inst:IsA("ImageButton") then
		return inst
	end
	return nil
end

local function findDescendant(parent: Instance, className: string, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function findEditableInputByTitle(root: Instance, titleText: string): EditableInputRefs?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextButton") and descendant.Name == "EditableInputField" then
			local title = descendant:FindFirstChild("Title")
			if title and title:IsA("TextLabel") and title.Text == titleText then
				local inputArea = descendant:FindFirstChild("InputArea", true)
				local valueBox = if inputArea then asTextBox(inputArea:FindFirstChild("EditableValue")) else nil
				local actionButton = if inputArea then asImageButton(inputArea:FindFirstChild("ActionButton")) else nil
				return {
					row = descendant,
					valueBox = valueBox,
					actionButton = actionButton,
				}
			end
		end
	end
	return nil
end

local function findEditableInputByTitles(root: Instance, titleTexts: { string }): EditableInputRefs?
	for _, titleText in ipairs(titleTexts) do
		local found = findEditableInputByTitle(root, titleText)
		if found then
			return found
		end
	end
	return nil
end

local function findTabButton(tabSwitcher: Instance, names: { string }): TextButton?
	for _, name in ipairs(names) do
		local found = tabSwitcher:FindFirstChild(name, true)
		if found and found:IsA("TextButton") then
			return found
		end
	end
	return nil
end

local function resolveTabButtons(tabSwitcher: ScrollingFrame?): TabButtonRefs
	if not tabSwitcher then
		return {}
	end

	local profileIdle = findTabButton(tabSwitcher, { "ProfileTabIdle", "ProfileIdle" })
	local profileActive = findTabButton(tabSwitcher, { "ProfileTabActive", "ProfileActive" })
	local settingsIdle = findTabButton(tabSwitcher, { "SettingsTabIdle", "SettingsIdle" })
	local settingsActive = findTabButton(tabSwitcher, { "SettingsTabActive", "SettingsActive" })

	return {
		profileButton = profileIdle or profileActive,
		settingsButton = settingsActive or settingsIdle,
		profileIdle = profileIdle,
		profileActive = profileActive,
		settingsIdle = settingsIdle,
		settingsActive = settingsActive,
	}
end

function MenuGuiRefsModule.resolve(gui: ScreenGui): MenuGuiRefs?
	local outerWrapper = asGuiObject(gui:FindFirstChild("MenuGUIWrapper"))
	if not outerWrapper then
		return nil
	end

	local contentWrapper = asGuiObject(outerWrapper:FindFirstChild("MenuGUIWrapper"))
	if not contentWrapper then
		contentWrapper = outerWrapper
	end

	local profileTab = contentWrapper and asScrollingFrame(contentWrapper:FindFirstChild("ProfileTab"))
	local settingsTab = contentWrapper and asScrollingFrame(contentWrapper:FindFirstChild("SettingsTab"))
	if not profileTab or not settingsTab then
		return nil
	end

	local tabWrapper = asGuiObject(outerWrapper:FindFirstChild("TabWrapper"))
	local tabSwitcher = if tabWrapper then asScrollingFrame(tabWrapper:FindFirstChild("TabSwitcher")) else nil

	local universalModal = asGuiObject(gui:FindFirstChild("UniversalModal"))
	local playerInfo = findDescendant(profileTab, "Frame", "PlayerInformation")
	local mainPlayerInfo = if playerInfo then asFrame(findDescendant(playerInfo :: Instance, "Frame", "MainPlayerInfo")) else nil
	local streakSection = findDescendant(profileTab, "Frame", "StreakSection")
	local streakSubtitle = if streakSection
		then asFrame(findDescendant(streakSection :: Instance, "Frame", "Subtitle"))
		else nil

	local statusPopup = if playerInfo then findDescendant(playerInfo :: Instance, "Frame", "StatusPopUp") else nil
	local statusLabel = if statusPopup
		then asTextLabel(statusPopup:FindFirstChild("TextLabel", true))
		else nil

	local bioSection = findDescendant(profileTab, "Frame", "BioSection")
	local profileTabIdentity = asGuiObject(profileTab:FindFirstChild("TabIdentity"))
	local profileTabTitle = if profileTabIdentity
		then asTextLabel(profileTabIdentity:FindFirstChild("TabTitle"))
		else nil
	local profileTabSubtitle = if profileTabIdentity
		then asTextLabel(profileTabIdentity:FindFirstChild("TabSubtitle"))
		else nil
	local settingsSectionTemplate = settingsTab:FindFirstChild("Section")
	if settingsSectionTemplate and settingsSectionTemplate:IsA("GuiObject") then
		(settingsSectionTemplate :: GuiObject).Visible = false
	end
	local settingsTabIdentity = asGuiObject(settingsTab:FindFirstChild("TabIdentity"))
	local settingsTabTitle = if settingsTabIdentity
		then asTextLabel(settingsTabIdentity:FindFirstChild("TabTitle"))
		else nil
	local settingsTabSubtitle = if settingsTabIdentity
		then asTextLabel(settingsTabIdentity:FindFirstChild("TabSubtitle"))
		else nil

	return {
		root = gui,
		outerWrapper = outerWrapper,
		contentWrapper = contentWrapper,
		gradientOverlay = asFrame(outerWrapper:FindFirstChild("GradientOverlay")),
		profileTab = profileTab,
		settingsTab = settingsTab,
		tabWrapper = tabWrapper,
		tabSwitcher = tabSwitcher,
		tabButtons = resolveTabButtons(tabSwitcher),
		universalModal = universalModal,
		modalTitle = if universalModal then asTextLabel(universalModal:FindFirstChild("Title")) else nil,
		modalInput = if universalModal then asTextBox(universalModal:FindFirstChild("InputValue")) else nil,
		modalCancelButton = if universalModal then asTextButton(universalModal:FindFirstChild("CancelButton")) else nil,
		modalUpdateButton = if universalModal then asTextButton(universalModal:FindFirstChild("UpdateButton")) else nil,
		avatarViewport = if playerInfo
			then asViewport(findDescendant(playerInfo :: Instance, "ViewportFrame", "3DTargetPlayerAvatar"))
			else nil,
		displayNameLabel = if mainPlayerInfo
			then asTextLabel(mainPlayerInfo:FindFirstChild("1-TargetPlayerDisplayName"))
			else nil,
		usernameLabel = if mainPlayerInfo
			then asTextLabel(mainPlayerInfo:FindFirstChild("2-TargetPlayerUsername"))
			else nil,
		badgeGroup = if mainPlayerInfo then asFrame(mainPlayerInfo:FindFirstChild("3-BadgeGroup")) else nil,
		statusPopup = if statusPopup and (statusPopup:IsA("TextButton") or statusPopup:IsA("ImageButton"))
			then (statusPopup :: GuiButton)
			else nil,
		statusPopupFrame = if statusPopup and statusPopup:IsA("GuiObject") then statusPopup :: GuiObject else nil,
		statusPopupLabel = statusLabel,
		bioContent = if bioSection then asTextLabel(bioSection:FindFirstChild("BioContent")) else nil,
		relationshipLine = asTextLabel(
			findDescendant(profileTab, "TextLabel", "RelationshipStatusContent")
		),
		streakCountLabel = if streakSubtitle
			then asTextLabel(streakSubtitle:FindFirstChild("TextLabel", true))
			else nil,
		coupleSingle = asTextButton(findDescendant(profileTab, "TextButton", "SingleIdle"))
			or asTextButton(findDescendant(profileTab, "TextButton", "SingleSelected")),
		coupleTaken = asTextButton(findDescendant(profileTab, "TextButton", "TakenIdle"))
			or asTextButton(findDescendant(profileTab, "TextButton", "TakenSelected")),
		coupleFun = asTextButton(findDescendant(profileTab, "TextButton", "ForFunIdle"))
			or asTextButton(findDescendant(profileTab, "TextButton", "ForFunSelected")),
		showCoupleToggle = asTextButton(findDescendant(profileTab, "TextButton", "ShowCoupleNameToggle"))
			or asTextButton(findDescendant(profileTab, "TextButton", "ShowCoupleName"))
			or asTextButton(findDescendant(profileTab, "TextButton", "ShowMyCoupleNameToggle")),
		displayNameInput = findEditableInputByTitle(profileTab, "Display Name"),
		specialTitleInput = findEditableInputByTitle(profileTab, "Title")
			or findEditableInputByTitle(profileTab, "Custom Title"),
		bioInput = findEditableInputByTitle(profileTab, "Bio"),
		statusInput = findEditableInputByTitles(profileTab, { "Status", "Player Status", "Custom Status" }),
		profileTabIdentity = profileTabIdentity,
		profileTabTitle = profileTabTitle,
		profileTabSubtitle = profileTabSubtitle,
		settingsSectionTemplate = if settingsSectionTemplate and settingsSectionTemplate:IsA("GuiObject")
			then settingsSectionTemplate
			else nil,
		settingsResetButton = asTextButton(settingsTab:FindFirstChild("ResetAllSettingsButton", true)),
		settingsTabIdentity = settingsTabIdentity,
		settingsTabTitle = settingsTabTitle,
		settingsTabSubtitle = settingsTabSubtitle,
	}
end

function MenuGuiRefsModule.waitForPlayerGui(timeout: number?): ScreenGui?
	local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Config.Settings.GUI_NAME, timeout or 10)
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

return MenuGuiRefsModule
