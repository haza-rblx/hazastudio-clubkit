--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local DonationSystemGuiRefs = {}

export type Refs = {
	root: ScreenGui,
	rootScale: UIScale?,
	mainWrapper: Frame,
	inputModal: Frame,
	messageBox: TextBox,
	addEmojiButton: TextButton?,
	emojiPicker: GuiObject?,
	emojiList: ScrollingFrame?,
	emojiTemplate: TextButton?,
	emojiCloseButton: TextButton?,
	cancelButton: TextButton,
	continueButton: TextButton,
	continueText: TextLabel?,
	closeButton: TextButton?,
	selector: Frame,
	backgroundPill: GuiObject?,
	robuxTabButton: TextButton,
	saweriaTabButton: TextButton,
	contentWrapper: Frame,
	donorProfile: Frame,
	robuxTab: GuiObject,
	saweriaTab: Frame,
	robuxScroll: ScrollingFrame,
	productTemplate: TextButton?,
	notFoundCard: GuiObject?,
	saweriaLink: TextBox?,
	copyLinkButton: TextButton?,
	displayNameLabel: TextLabel?,
	usernameLabel: TextLabel?,
	robuxRankLabel: GuiObject?,
	robuxValueLabel: GuiObject?,
	saweriaRankLabel: GuiObject?,
	saweriaValueLabel: GuiObject?,
	avatarViewport: ViewportFrame?,
}

local function expect(parent: Instance, name: string, timeout: number?): Instance
	local child = parent:WaitForChild(name, timeout or 15)
	assert(child, ("DonationSystemGuiRefs: missing '%s' under %s"):format(name, parent:GetFullName()))
	return child
end

local function asFrame(instance: Instance): Frame
	assert(instance:IsA("Frame"), ("Expected Frame, got %s at %s"):format(instance.ClassName, instance:GetFullName()))
	return instance :: Frame
end

local function asTextButton(instance: Instance): TextButton
	assert(
		instance:IsA("TextButton"),
		("Expected TextButton, got %s at %s"):format(instance.ClassName, instance:GetFullName())
	)
	return instance :: TextButton
end

local function asTextBox(instance: Instance): TextBox
	assert(
		instance:IsA("TextBox"),
		("Expected TextBox, got %s at %s"):format(instance.ClassName, instance:GetFullName())
	)
	return instance :: TextBox
end

local function asScrollingFrame(instance: Instance): ScrollingFrame
	assert(
		instance:IsA("ScrollingFrame"),
		("Expected ScrollingFrame, got %s at %s"):format(instance.ClassName, instance:GetFullName())
	)
	return instance :: ScrollingFrame
end

local function asCanvasGroup(instance: Instance): CanvasGroup
	assert(
		instance:IsA("CanvasGroup"),
		("Expected CanvasGroup, got %s at %s"):format(instance.ClassName, instance:GetFullName())
	)
	return instance :: CanvasGroup
end

local function isTextDisplay(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton")
end

local function findTextDisplay(root: Instance, name: string): GuiObject?
	local found = root:FindFirstChild(name, true)
	if found and isTextDisplay(found) then
		return found :: GuiObject
	end
	return nil
end

local function normalizeUiText(text: string): string
	return (string.gsub(text, "^%s+", ""):gsub("%s+$", "")) :: string
end

local function isEffectivelyVisible(gui: GuiObject): boolean
	local current: Instance? = gui
	while current do
		if current:IsA("GuiObject") and current.Visible == false then
			return false
		end
		current = current.Parent
	end
	return true
end

local function hasRenderableSize(gui: GuiObject): boolean
	return gui.AbsoluteSize.X > 1 and gui.AbsoluteSize.Y > 1
end

local function sortByLayoutOrder(a: GuiObject, b: GuiObject): boolean
	if a.LayoutOrder ~= b.LayoutOrder then
		return a.LayoutOrder < b.LayoutOrder
	end
	return a.AbsolutePosition.X < b.AbsolutePosition.X
end

local function findTextDisplayByNames(root: Instance, names: { string }): GuiObject?
	for _, name in ipairs(names) do
		local found = findTextDisplay(root, name)
		if found then
			return found
		end
	end
	return nil
end

local function findVisibleTextDisplayByNames(root: Instance, names: { string }): GuiObject?
	for _, name in ipairs(names) do
		local found = findTextDisplay(root, name)
		if found and isEffectivelyVisible(found) then
			return found
		end
	end
	return nil
end

local function findChipTextDisplay(root: Instance, wrapperName: string, labelName: string): GuiObject?
	local wrapper = root:FindFirstChild(wrapperName, true)
	if not wrapper or not wrapper:IsA("GuiObject") then
		return nil
	end
	local label = findTextDisplay(wrapper, labelName)
	if label and isEffectivelyVisible(label) then
		return label
	end
	local fallback = wrapper:FindFirstChildWhichIsA("TextLabel", true)
		or wrapper:FindFirstChildWhichIsA("TextButton", true)
	if fallback and isTextDisplay(fallback) and isEffectivelyVisible(fallback :: GuiObject) then
		return fallback :: GuiObject
	end
	return nil
end

-- Donation GUI layout: MainContentWrapper.PlayerStats.{RobuxDonation,SaweriaDonations}
local function findPlayerStatsStatLabels(
	donorProfileRoot: Instance
): (GuiObject?, GuiObject?, GuiObject?, GuiObject?)
	local playerStats = donorProfileRoot:FindFirstChild("PlayerStats")
	if not playerStats then
		return nil, nil, nil, nil
	end

	local robuxBlock = playerStats:FindFirstChild("RobuxDonation")
	local saweriaBlock = playerStats:FindFirstChild("SaweriaDonations")

	local robuxRankLabel = if robuxBlock then findTextDisplay(robuxBlock, "RobuxRank") else nil
	local robuxValueLabel = if robuxBlock then findTextDisplay(robuxBlock, "RobuxValueDynamic") else nil
	local saweriaRankLabel = if saweriaBlock then findTextDisplay(saweriaBlock, "SaweriaRank") else nil
	local saweriaValueLabel = if saweriaBlock then findTextDisplay(saweriaBlock, "SaweriaValueDynamic") else nil

	return robuxRankLabel, robuxValueLabel, saweriaRankLabel, saweriaValueLabel
end

-- Visible stat cards ship with placeholder "#-" and "0" before data bind.
local function discoverStatLabelsByPlaceholder(
	root: Instance,
	requireRenderableSize: boolean?
): (GuiObject?, GuiObject?, GuiObject?, GuiObject?)
	local rankLabels: { GuiObject } = {}
	local valueLabels: { GuiObject } = {}
	for _, inst in ipairs(root:GetDescendants()) do
		if not isTextDisplay(inst) then
			continue
		end
		local gui = inst :: GuiObject
		if not isEffectivelyVisible(gui) then
			continue
		end
		if requireRenderableSize == true and not hasRenderableSize(gui) then
			continue
		end
		local text = normalizeUiText(gui.Text)
		if text == "#-" or text == "# -" then
			table.insert(rankLabels, gui)
		elseif text == "0" then
			table.insert(valueLabels, gui)
		end
	end
	table.sort(rankLabels, sortByLayoutOrder)
	table.sort(valueLabels, sortByLayoutOrder)
	return rankLabels[1], valueLabels[1], rankLabels[2], valueLabels[2]
end

-- Stat cards use visible titles ("Top Donate", "Top Spender") with rank/value
-- labels that may not match legacy names RobuxRank / RobuxValueDynamic.
local function findStatLabelsBySectionTitle(
	root: Instance,
	sectionTitle: string,
	requireRenderable: boolean?
): (GuiObject?, GuiObject?)
	local titleLower = string.lower(sectionTitle)
	for _, inst in ipairs(root:GetDescendants()) do
		if not isTextDisplay(inst) then
			continue
		end
		local titleGui = inst :: GuiObject
		if not isEffectivelyVisible(titleGui) then
			continue
		end
		local textLower = string.lower(normalizeUiText(titleGui.Text))
		if textLower ~= titleLower and not textLower:find(titleLower, 1, true) then
			continue
		end

		local searchRoot = inst.Parent
		if searchRoot and searchRoot.Parent and searchRoot.Parent:IsA("GuiObject") then
			searchRoot = searchRoot.Parent
		end
		if not searchRoot then
			continue
		end

		local rankLabel: GuiObject? = nil
		local valueLabel: GuiObject? = nil
		for _, descendant in ipairs(searchRoot:GetDescendants()) do
			if not isTextDisplay(descendant) or descendant == inst then
				continue
			end
			local gui = descendant :: GuiObject
			if not isEffectivelyVisible(gui) then
				continue
			end
			if requireRenderable == true and not hasRenderableSize(gui) then
				continue
			end
			local nameLower = gui.Name:lower()
			if nameLower:find("rank", 1, true) then
				rankLabel = gui
			elseif
				nameLower:find("value", 1, true)
				or nameLower:find("dynamic", 1, true)
				or nameLower:find("total", 1, true)
			then
				valueLabel = gui
			elseif gui.Text:match("^#") then
				rankLabel = rankLabel or gui
			elseif tonumber(gui.Text) ~= nil then
				valueLabel = valueLabel or gui
			end
		end

		if rankLabel or valueLabel then
			return rankLabel, valueLabel
		end
	end
	return nil, nil
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local found = findTextDisplay(root, name)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function findTextButton(root: Instance, name: string): TextButton?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextButton") then
		return found
	end
	return nil
end

local function findTextButtonByNames(root: Instance, names: { string }): TextButton?
	for _, name in ipairs(names) do
		local found = findTextButton(root, name)
		if found then
			return found
		end
	end
	return nil
end

local function findTextBox(root: Instance, name: string): TextBox?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextBox") then
		return found
	end
	return nil
end

local function findViewportFrame(root: Instance, name: string): ViewportFrame?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("ViewportFrame") then
		return found
	end
	return nil
end

function DonationSystemGuiRefs.resolveDonorStatLabels(
	donorProfileRoot: Instance,
	requireRenderable: boolean?
): (GuiObject?, GuiObject?, GuiObject?, GuiObject?)
	local robuxRankLabel, robuxValueLabel, saweriaRankLabel, saweriaValueLabel =
		findPlayerStatsStatLabels(donorProfileRoot)

	robuxRankLabel = robuxRankLabel or findVisibleTextDisplayByNames(donorProfileRoot, {
		"RobuxRank",
		"TopDonateRank",
		"1-RobuxRank",
		"RobuxRanking",
	})
		or findChipTextDisplay(donorProfileRoot, "RobuxRankWrapper", "RobuxRanking")
	robuxValueLabel = robuxValueLabel or findVisibleTextDisplayByNames(donorProfileRoot, {
		"RobuxValueDynamic",
		"RobuxValue",
		"TopDonateValue",
		"RobuxTotal",
	})

	if not robuxRankLabel or not robuxValueLabel then
		local byTitleRank, byTitleValue = findStatLabelsBySectionTitle(donorProfileRoot, "Top Donate", requireRenderable)
		robuxRankLabel = robuxRankLabel or byTitleRank
		robuxValueLabel = robuxValueLabel or byTitleValue
	end

	saweriaRankLabel = saweriaRankLabel or findVisibleTextDisplayByNames(donorProfileRoot, {
		"SaweriaRank",
		"TopSpenderRank",
		"1-SaweriaRank",
		"RupiahRank",
	})
		or findChipTextDisplay(donorProfileRoot, "RupiahRankWrapper", "RupiahRank")
	saweriaValueLabel = saweriaValueLabel or findVisibleTextDisplayByNames(donorProfileRoot, {
		"SaweriaValueDynamic",
		"SaweriaValue",
		"TopSpenderValue",
		"CashTotal",
	})

	if not saweriaRankLabel or not saweriaValueLabel then
		local byTitleRank, byTitleValue = findStatLabelsBySectionTitle(donorProfileRoot, "Top Spender", requireRenderable)
		saweriaRankLabel = saweriaRankLabel or byTitleRank
		saweriaValueLabel = saweriaValueLabel or byTitleValue
		if not saweriaRankLabel or not saweriaValueLabel then
			local providerName = DonationProviderDomain.getName()
			byTitleRank, byTitleValue = findStatLabelsBySectionTitle(donorProfileRoot, providerName, requireRenderable)
			saweriaRankLabel = saweriaRankLabel or byTitleRank
			saweriaValueLabel = saweriaValueLabel or byTitleValue
		end
		local bagiRank, bagiValue = findStatLabelsBySectionTitle(donorProfileRoot, "BagiBagi", requireRenderable)
		saweriaRankLabel = saweriaRankLabel or bagiRank
		saweriaValueLabel = saweriaValueLabel or bagiValue
	end

	if not robuxRankLabel or not robuxValueLabel or not saweriaRankLabel or not saweriaValueLabel then
		local placeholderRobuxRank, placeholderRobuxValue, placeholderSpenderRank, placeholderSpenderValue =
			discoverStatLabelsByPlaceholder(donorProfileRoot, requireRenderable)
		robuxRankLabel = robuxRankLabel or placeholderRobuxRank
		robuxValueLabel = robuxValueLabel or placeholderRobuxValue
		saweriaRankLabel = saweriaRankLabel or placeholderSpenderRank
		saweriaValueLabel = saweriaValueLabel or placeholderSpenderValue
	end

	return robuxRankLabel, robuxValueLabel, saweriaRankLabel, saweriaValueLabel
end

function DonationSystemGuiRefs.resolve(playerGui: PlayerGui, guiName: string): Refs
	local root = expect(playerGui, guiName) :: ScreenGui
	local mainWrapper = asFrame(expect(root, "MainWrapper"))
	local inputModal = asFrame(expect(root, "InputCustomMessageModal"))
	local messageBox = asTextBox(expect(inputModal, "TextBox"))
	local addEmojiButton = findTextButton(messageBox, "AddEmojiButton")
	local emojiPickerCandidate = root:FindFirstChild("EmojiPicker")
	if not emojiPickerCandidate then
		local adminGui: Instance? = nil
		local adminCandidates = Config.Admin.GUI_NAME_CANDIDATES or { Config.Admin.GUI_NAME }
		for _, guiName in ipairs(adminCandidates) do
			adminGui = playerGui:FindFirstChild(guiName)
			if adminGui then
				break
			end
		end
		local adminEmojiPicker = adminGui and adminGui:FindFirstChild("EmojiPicker")
		if adminEmojiPicker and adminEmojiPicker:IsA("GuiObject") then
			local clonedEmojiPicker = adminEmojiPicker:Clone()
			clonedEmojiPicker.Name = "EmojiPicker"
			clonedEmojiPicker.Parent = root
			emojiPickerCandidate = clonedEmojiPicker
		end
	end
	local emojiPicker = if emojiPickerCandidate and emojiPickerCandidate:IsA("GuiObject")
		then emojiPickerCandidate :: GuiObject
		else nil
	local emojiListCandidate = emojiPicker and emojiPicker:FindFirstChild("EmojiList")
	local emojiList = if emojiListCandidate and emojiListCandidate:IsA("ScrollingFrame")
		then emojiListCandidate :: ScrollingFrame
		else nil
	local emojiTemplateCandidate = emojiList and emojiList:FindFirstChild("EmojiButtonTemplate")
	local emojiTemplate = if emojiTemplateCandidate and emojiTemplateCandidate:IsA("TextButton")
		then emojiTemplateCandidate :: TextButton
		else nil
	local cancelButton = asTextButton(expect(inputModal, "CancelButton"))
	local continueButton = asTextButton(expect(inputModal, "ContinueDonateButton"))
	local headerWrapper = asFrame(expect(mainWrapper, "01-HeaderWrapper"))
	local selector = asFrame(expect(headerWrapper, "2-SliderSelector"))
	local backgroundPill = selector:FindFirstChild("BackgroundPill")
	if backgroundPill and not backgroundPill:IsA("GuiObject") then
		backgroundPill = nil
	end
	
	-- Find nested SliderSelector container if exists
	local selectorInner = selector:FindFirstChild("2-SliderSelector")
	local optionsContainer = if selectorInner and selectorInner:IsA("Frame") then selectorInner else selector
	
	-- Find tab buttons by checking text content or fallback names
	local robuxTabButton: TextButton? = nil
	local saweriaTabButton: TextButton? = nil
	
	for _, child in ipairs(optionsContainer:GetChildren()) do
		if child:IsA("TextButton") then
			local btn = child :: TextButton
			local text = btn.Text:lower()
			if text:find("robux") or btn.Name == "Option1" or btn.Name == "RobuxTabButton" then
				robuxTabButton = btn
			elseif text:find("bagi") or text:find("saweria") or btn.Name == "Option2" or btn.Name == "SaweriaTabButton" then
				saweriaTabButton = btn
			end
		end
	end
	
	assert(robuxTabButton, ("DonationSystemGuiRefs: missing robux tab button under %s"):format(optionsContainer:GetFullName()))
	assert(saweriaTabButton, ("DonationSystemGuiRefs: missing saweria tab button under %s"):format(optionsContainer:GetFullName()))
	
	local contentWrapper = asFrame(expect(mainWrapper, "02-MainContentWrapper"))
	local donorProfile = asFrame(expect(contentWrapper, "1-DonorProfile"))
	local donorProfileRoot = donorProfile:FindFirstChild("MainContentWrapper") or donorProfile
	local robuxTabCandidate = contentWrapper:FindFirstChild("2-RobuxTab")
	local robuxTab = if robuxTabCandidate and robuxTabCandidate:IsA("CanvasGroup")
		then robuxTabCandidate :: CanvasGroup
		elseif robuxTabCandidate and robuxTabCandidate:IsA("Frame")
		then robuxTabCandidate :: Frame
		else asCanvasGroup(expect(contentWrapper, "2-RobuxTab"))
	local saweriaTab = asFrame(expect(contentWrapper, "3-SaweriaTab"))
	local robuxScroll = asScrollingFrame(expect(robuxTab, "ScrollableMainWrapper"))
	local productTemplate = robuxScroll:FindFirstChild("ProductCardTemplate")
	local notFoundCard = robuxScroll:FindFirstChild("NotFoundCard")
	local inputArea = saweriaTab:FindFirstChild("InputArea")

	local robuxRankLabel, robuxValueLabel, saweriaRankLabel, saweriaValueLabel =
		DonationSystemGuiRefs.resolveDonorStatLabels(donorProfileRoot, false)

	return {
		root = root,
		rootScale = root:FindFirstChildWhichIsA("UIScale"),
		mainWrapper = mainWrapper,
		inputModal = inputModal,
		messageBox = messageBox,
		addEmojiButton = addEmojiButton,
		emojiPicker = emojiPicker,
		emojiList = emojiList,
		emojiTemplate = emojiTemplate,
		emojiCloseButton = if emojiPicker then findTextButton(emojiPicker, "CloseModalButton") else nil,
		cancelButton = cancelButton,
		continueButton = continueButton,
		continueText = findTextLabel(continueButton, "ContinueDonateText"),
		closeButton = findTextButton(mainWrapper, "3-CloseModalButton"),
		selector = selector,
		backgroundPill = backgroundPill,
		robuxTabButton = robuxTabButton,
		saweriaTabButton = saweriaTabButton,
		contentWrapper = contentWrapper,
		donorProfile = donorProfile,
		robuxTab = robuxTab,
		saweriaTab = saweriaTab,
		robuxScroll = robuxScroll,
		productTemplate = if productTemplate and productTemplate:IsA("TextButton")
			then productTemplate :: TextButton
			else nil,
		notFoundCard = if notFoundCard and notFoundCard:IsA("GuiObject") then notFoundCard :: GuiObject else nil,
		saweriaLink = if inputArea then findTextBox(inputArea, "SaweriaLink") else nil,
		copyLinkButton = if inputArea then findTextButton(inputArea, "CopyLinkButton") else nil,
		displayNameLabel = findTextDisplayByNames(donorProfileRoot, {
			"1-PlayerDisplayName",
			"PlayerDisplayName",
		}),
		usernameLabel = findTextDisplayByNames(donorProfileRoot, {
			"2-PlayerUsername",
			"PlayerUsername",
		}),
		robuxRankLabel = robuxRankLabel,
		robuxValueLabel = robuxValueLabel,
		saweriaRankLabel = saweriaRankLabel,
		saweriaValueLabel = saweriaValueLabel,
		avatarViewport = findViewportFrame(donorProfileRoot, "3DTargetPlayerAvatar"),
	}
end

function DonationSystemGuiRefs.refreshStatLabelRefs(refs: Refs)
	local donorProfileRoot = refs.donorProfile:FindFirstChild("MainContentWrapper") or refs.donorProfile
	local robuxRankLabel, robuxValueLabel, saweriaRankLabel, saweriaValueLabel =
		DonationSystemGuiRefs.resolveDonorStatLabels(donorProfileRoot, true)
	if robuxRankLabel then
		refs.robuxRankLabel = robuxRankLabel
	end
	if robuxValueLabel then
		refs.robuxValueLabel = robuxValueLabel
	end
	if saweriaRankLabel then
		refs.saweriaRankLabel = saweriaRankLabel
	end
	if saweriaValueLabel then
		refs.saweriaValueLabel = saweriaValueLabel
	end
end

return DonationSystemGuiRefs
