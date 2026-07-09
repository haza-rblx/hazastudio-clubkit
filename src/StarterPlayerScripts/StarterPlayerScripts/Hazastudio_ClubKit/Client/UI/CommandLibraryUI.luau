--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ObjectPool = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.ObjectPool)
type ILogger = Types.ILogger
type CommandLibraryEntry = Types.CommandLibraryEntry
type CardRefs = {
	root: TextButton,
	icon: ImageButton?,
	content: Frame?,
	chip: Frame?,
	commandLabel: TextLabel?,
	descriptionLabel: TextLabel?,
}
type CardStyle = {
	backgroundColor3: Color3,
	backgroundTransparency: number,
	chipBackgroundColor3: Color3?,
	chipBackgroundTransparency: number?,
	commandTextColor3: Color3?,
	descriptionTextColor3: Color3?,
}
type RowMeta = {
	refs: CardRefs,
	entryId: string?,
	baseVariant: string,
	baseIconImage: string?,
	isHovered: boolean,
	isClicked: boolean,
}

local LIST_FIXED_HEIGHT = 300
local PANEL_OPEN_START_SCALE = 0.96
local PANEL_OPEN_TIME = 0.28
local PANEL_CLOSE_TIME = 0.18
local PANEL_OPEN_TWEEN = TweenInfo.new(PANEL_OPEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PANEL_CLOSE_TWEEN = TweenInfo.new(PANEL_CLOSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local CARET_BLINK_INTERVAL = 0.52
local CARET_SIDE_PADDING = 14
local CARET_WIDTH = 2

local function createDisabledCommandLibraryUI(): any
	local inputText = ""
	local fallbackScreenGui = Instance.new("ScreenGui")
	fallbackScreenGui.ResetOnSpawn = false
	local fallbackMainWrapper = Instance.new("Frame")
	local ui = {}

	function ui:bindInputChanged(_callback: (string) -> ()) end
	function ui:bindInputFocused(_callback: () -> ()) end
	function ui:bindExecute(_callback: (string) -> ()) end
	function ui:bindCardFilled(_callback: (CommandLibraryEntry) -> ()) end
	function ui:setCloseCallback(_callback: () -> ()) end
	function ui:show() end
	function ui:hide() end
	function ui:isVisible(): boolean
		return false
	end
	function ui:isPanelOpen(): boolean
		return false
	end
	function ui:getScreenGui(): ScreenGui
		return fallbackScreenGui
	end
	function ui:getMainWrapper(): GuiObject
		return fallbackMainWrapper
	end
	function ui:focusInput() end
	function ui:setInputText(text: string)
		inputText = text
	end
	function ui:getInputText(): string
		return inputText
	end
	function ui:setPhoneButtonVisible(_visible: boolean) end
	function ui:setGhostSuggestion(_text: string?) end
	function ui:renderCommands(_entries: { CommandLibraryEntry }, _query: string) end
	function ui:handleOutsideClose() end

	return ui
end

local function createCommandLibraryUI(deps: { logger: ILogger })
	local log = deps.logger
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Config.CommandLibrary.GUI_NAME, 10) :: ScreenGui?
	if not gui then
		warn(
			"[CommandLibraryUI] GUI '"
				.. Config.CommandLibrary.GUI_NAME
				.. "' not found in PlayerGui — panel disabled"
		)
		return createDisabledCommandLibraryUI()
	end
	local gui_ = gui :: ScreenGui
	local mainWrapper = gui_:WaitForChild("MainWrapper") :: CanvasGroup
	local inputWrapper = mainWrapper:WaitForChild("InputWrapper") :: CanvasGroup
	local inputTextBox = inputWrapper:WaitForChild("InputTextCommand") :: TextBox
	local runButton = inputWrapper:WaitForChild("RunCommandForPhoneButton") :: ImageButton
	local listWrapper = mainWrapper:WaitForChild("ListCommandWrapper") :: CanvasGroup
	local listCommand = listWrapper:WaitForChild("ListCommand") :: ScrollingFrame
	local normalTemplate = listCommand:WaitForChild("NormalState") :: TextButton
	local hoverTemplate = listCommand:WaitForChild("HoverState") :: TextButton
	local matchedTemplate = listCommand:WaitForChild("MatchedState") :: TextButton
	local clickedTemplate = listCommand:WaitForChild("ClickedState") :: TextButton
	local notFoundTemplate = listCommand:WaitForChild("NotFoundState") :: TextButton
	local inputChangedCallback: ((string) -> ())? = nil
	local inputFocusedCallback: (() -> ())? = nil
	local executeCallback: ((string) -> ())? = nil
	local cardClickCallback: ((CommandLibraryEntry) -> ())? = nil
	local onCloseCallback: (() -> ())? = nil
	local entriesById = {} :: { [string]: CommandLibraryEntry }
	local activeRows = {} :: { TextButton }
	local rowMetaByInstance = {} :: { [TextButton]: RowMeta }
	local ui = {}
	local mainScale = mainWrapper:FindFirstChild("CommandLibraryPopScale") :: UIScale?
	if not mainScale then
		mainScale = Instance.new("UIScale")
		mainScale.Name = "CommandLibraryPopScale"
		mainScale.Scale = 1
		mainScale.Parent = mainWrapper
	end
	local mainScaleRef = mainScale :: UIScale
	local activeScaleTween: Tween? = nil
	local animationToken = 0
	local listLayout = listCommand:FindFirstChildWhichIsA("UIListLayout")
	local listPadding = listWrapper:FindFirstChildWhichIsA("UIPadding")
	listCommand.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listCommand.CanvasSize = UDim2.fromOffset(0, 0)
	local blinkCaret = inputTextBox:FindFirstChild("BlinkCaret") :: Frame?
	if not blinkCaret then
		blinkCaret = Instance.new("Frame")
		blinkCaret.Name = "BlinkCaret"
		blinkCaret.BorderSizePixel = 0
		blinkCaret.BackgroundColor3 = inputTextBox.TextColor3
		blinkCaret.Visible = false
		blinkCaret.ZIndex = inputTextBox.ZIndex + 2
		blinkCaret.Parent = inputTextBox
	end
	local blinkCaretRef = blinkCaret :: Frame
	local caretBlinkToken = 0
	local inputFocused = false
	local panelOpen = false
	local suppressInputCallbacks = false

	local function cancelScaleTween()
		if activeScaleTween then
			activeScaleTween:Cancel()
			activeScaleTween = nil
		end
	end

	local function tweenMainScale(
		startScale: number,
		targetScale: number,
		tweenInfo: TweenInfo,
		onCompleted: (() -> ())?
	)
		animationToken += 1
		local token = animationToken
		cancelScaleTween()
		mainScaleRef.Scale = startScale

		local tween = TweenService:Create(mainScaleRef, tweenInfo, { Scale = targetScale })
		activeScaleTween = tween
		tween.Completed:Once(function(playbackState: Enum.PlaybackState)
			if token ~= animationToken or playbackState ~= Enum.PlaybackState.Completed then
				return
			end

			activeScaleTween = nil
			if onCompleted then
				onCompleted()
			end
		end)
		tween:Play()
	end

	local function measureInputTextWidth(text: string): number
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = inputTextBox.FontFace
		params.Size = inputTextBox.TextSize
		params.Width = math.huge
		local ok, result = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		return if ok then result.X else 0
	end

	local function updateBlinkCaret()
		local text = inputTextBox.Text
		local cursorPosition = inputTextBox.CursorPosition
		-- Roblox clamps CursorPosition to #text (end of string), not #text+1.
		-- -1 means not focused; treat it as cursor at end.
		if cursorPosition < 1 then
			cursorPosition = #text
		end

		-- No -1 here: cursorPosition already equals the number of chars before cursor.
		local beforeCursor = string.sub(text, 1, cursorPosition)
		local beforeWidth = measureInputTextWidth(beforeCursor)
		local totalWidth = measureInputTextWidth(text)
		local availableWidth = inputTextBox.AbsoluteSize.X
		local x = CARET_SIDE_PADDING + beforeWidth

		if inputTextBox.TextXAlignment == Enum.TextXAlignment.Center then
			x = (availableWidth - totalWidth) * 0.5 + beforeWidth
		elseif inputTextBox.TextXAlignment == Enum.TextXAlignment.Right then
			x = availableWidth - CARET_SIDE_PADDING - totalWidth + beforeWidth
		end

		x = math.clamp(math.floor(x), 2, math.max(2, availableWidth - CARET_WIDTH - 2))
		blinkCaretRef.Size = UDim2.fromOffset(CARET_WIDTH, math.max(18, inputTextBox.TextSize + 6))
		blinkCaretRef.Position = UDim2.new(0, x, 0.5, 0)
		blinkCaretRef.AnchorPoint = Vector2.new(0, 0.5)
	end

	local function setBlinkCaretOn(isOn: boolean)
		blinkCaretRef.BackgroundColor3 = if isOn then inputTextBox.TextColor3 else inputTextBox.BackgroundColor3
		blinkCaretRef.BackgroundTransparency = if isOn then 0 else inputTextBox.BackgroundTransparency
	end

	local function setInputInteractivity(enabled: boolean)
		inputTextBox.TextEditable = enabled
		inputTextBox.Active = enabled
		inputTextBox.Selectable = enabled
	end

	local function stopBlinkCaret()
		caretBlinkToken += 1
		inputFocused = false
		blinkCaretRef.Visible = false
	end

	local function startBlinkCaret()
		caretBlinkToken += 1
		inputFocused = true
		blinkCaretRef.Visible = false
	end

	local function releaseKeyboardCapture()
		stopBlinkCaret()
		pcall(function()
			inputTextBox:ReleaseFocus()
		end)
		setInputInteractivity(false)
		task.defer(function()
			if inputTextBox.Parent then
				pcall(function()
					inputTextBox:ReleaseFocus()
				end)
			end
		end)
	end

	local function getVerticalPaddingHeight(): number
		if not listPadding then
			return 0
		end

		return listPadding.PaddingTop.Offset + listPadding.PaddingBottom.Offset
	end

	local function setListHeight(height: number, scrollingEnabled: boolean)
		listWrapper.AutomaticSize = Enum.AutomaticSize.None
		listWrapper.Size = UDim2.new(listWrapper.Size.X.Scale, listWrapper.Size.X.Offset, 0, height)
		listCommand.AutomaticSize = Enum.AutomaticSize.None
		listCommand.Size = UDim2.fromScale(1, 1)
		listCommand.ScrollingEnabled = scrollingEnabled
	end

	local function setListFixedHeight()
		setListHeight(LIST_FIXED_HEIGHT, true)
	end

	local function applyListMeasuredHeight(hasQuery: boolean)
		if not hasQuery or not listLayout then
			setListFixedHeight()
			return
		end

		task.defer(function()
			if not mainWrapper.Parent then
				return
			end

			local measuredHeight = math.ceil(listLayout.AbsoluteContentSize.Y + getVerticalPaddingHeight())
			local targetHeight = math.clamp(measuredHeight, 0, LIST_FIXED_HEIGHT)
			setListHeight(targetHeight, measuredHeight > LIST_FIXED_HEIGHT)
		end)
	end

	local function findDirectChildOfClass(parent: Instance, className: string): Instance?
		for _, child in ipairs(parent:GetChildren()) do
			if child.ClassName == className then
				return child
			end
		end
		return nil
	end
	local function resolveCardRefs(card: TextButton): CardRefs
		local refs: CardRefs = {
			root = card,
			icon = nil,
			content = nil,
			chip = nil,
			commandLabel = nil,
			descriptionLabel = nil,
		}
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("ImageButton") then
				refs.icon = child
			elseif child:IsA("Frame") and child.Name ~= "Icon" then
				-- Skip Frame "Icon" karena bukan content. Tanpa filter ini,
				-- refs.content ke-overwrite jadi Icon Frame dan descriptionLabel/
				-- commandLabel jadi nil → text di card stuck di default template.
				refs.content = child
			end
		end
		if refs.content then
			for _, child in ipairs(refs.content:GetChildren()) do
				if child:IsA("Frame") then
					refs.chip = child
				elseif child:IsA("TextLabel") then
					refs.descriptionLabel = child
				end
			end
		end
		if refs.chip then
			local commandLabel = findDirectChildOfClass(refs.chip, "TextLabel")
			if commandLabel and commandLabel:IsA("TextLabel") then
				refs.commandLabel = commandLabel
			end
		end
		return refs
	end
	local function snapshotStyle(card: TextButton): CardStyle
		local refs = resolveCardRefs(card)
		return {
			backgroundColor3 = card.BackgroundColor3,
			backgroundTransparency = card.BackgroundTransparency,
			chipBackgroundColor3 = refs.chip and refs.chip.BackgroundColor3 or nil,
			chipBackgroundTransparency = refs.chip and refs.chip.BackgroundTransparency or nil,
			commandTextColor3 = refs.commandLabel and refs.commandLabel.TextColor3 or nil,
			descriptionTextColor3 = refs.descriptionLabel and refs.descriptionLabel.TextColor3 or nil,
		}
	end
	local styleByVariant = {
		normal = snapshotStyle(normalTemplate),
		hover = snapshotStyle(hoverTemplate),
		matched = snapshotStyle(matchedTemplate),
		clicked = snapshotStyle(clickedTemplate),
	}
	local function getEffectiveVariant(meta: RowMeta): string
		if meta.isClicked then
			return "clicked"
		end
		if meta.isHovered then
			return "hover"
		end
		return meta.baseVariant
	end
	local function applyVariant(card: TextButton)
		local meta = rowMetaByInstance[card]
		if not meta then
			return
		end
		local variant = getEffectiveVariant(meta)
		local style = styleByVariant[variant]
		if not style then
			return
		end
		card.BackgroundColor3 = style.backgroundColor3
		card.BackgroundTransparency = style.backgroundTransparency
		if meta.refs.chip and style.chipBackgroundColor3 and style.chipBackgroundTransparency then
			meta.refs.chip.BackgroundColor3 = style.chipBackgroundColor3
			meta.refs.chip.BackgroundTransparency = style.chipBackgroundTransparency
		end
		if meta.refs.commandLabel and style.commandTextColor3 then
			meta.refs.commandLabel.TextColor3 = style.commandTextColor3
		end
		if meta.refs.descriptionLabel and style.descriptionTextColor3 then
			meta.refs.descriptionLabel.TextColor3 = style.descriptionTextColor3
		end
	end
	local function resetRow(card: TextButton)
		local meta = rowMetaByInstance[card]
		if meta then
			meta.entryId = nil
			meta.baseVariant = "normal"
			meta.isHovered = false
			meta.isClicked = false
			if meta.refs.commandLabel then
				meta.refs.commandLabel.Text = ""
			end
			if meta.refs.descriptionLabel then
				meta.refs.descriptionLabel.Text = ""
			end
			if meta.refs.icon then
				meta.refs.icon.Image = meta.baseIconImage or ""
				meta.refs.icon.Visible = meta.refs.icon.Image ~= ""
				meta.refs.icon.Active = meta.refs.icon.Visible
			end
		end
		card.Visible = false
		card.Parent = nil
		card.LayoutOrder = 0
		applyVariant(card)
	end
	local rowPool = ObjectPool.new(function()
		local row = normalTemplate:Clone()
		row.Name = "CommandCard"
		row.Visible = false
		local refs = resolveCardRefs(row)
		local meta: RowMeta = {
			refs = refs,
			entryId = nil,
			baseVariant = "normal",
			baseIconImage = refs.icon and refs.icon.Image or nil,
			isHovered = false,
			isClicked = false,
		}
		rowMetaByInstance[row] = meta
		local function fireFill()
			if not cardClickCallback or not meta.entryId then
				return
			end
			local entry = entriesById[meta.entryId]
			if entry then
				cardClickCallback(entry)
			end
		end
		row.MouseEnter:Connect(function()
			meta.isHovered = true
			applyVariant(row)
		end)
		row.MouseLeave:Connect(function()
			meta.isHovered = false
			applyVariant(row)
		end)
		row.Activated:Connect(function()
			meta.isClicked = true
			applyVariant(row)
			fireFill()
			task.delay(0.12, function()
				if rowMetaByInstance[row] ~= meta then
					return
				end
				meta.isClicked = false
				applyVariant(row)
			end)
		end)
		if refs.icon then
			refs.icon.Activated:Connect(fireFill)
		end
		return row
	end, resetRow, 32)
	local function releaseRows()
		for _, row in ipairs(activeRows) do
			rowPool:release(row)
		end
		table.clear(activeRows)
	end
	local function configureRow(row: TextButton, entry: CommandLibraryEntry, layoutOrder: number, baseVariant: string)
		local meta = rowMetaByInstance[row]
		if not meta then
			return
		end
		meta.entryId = entry.id
		meta.baseVariant = baseVariant
		meta.isHovered = false
		meta.isClicked = false
		if meta.refs.commandLabel then
			meta.refs.commandLabel.Text = entry.display
		end
		if meta.refs.descriptionLabel then
			meta.refs.descriptionLabel.Text = entry.description
		end
		if meta.refs.icon then
			meta.refs.icon.Image = meta.baseIconImage or ""
			meta.refs.icon.Visible = meta.refs.icon.Image ~= ""
			meta.refs.icon.Active = meta.refs.icon.Visible
		end
		row.LayoutOrder = layoutOrder
		row.Visible = true
		row.Parent = listCommand
		applyVariant(row)
	end
	local function hideTemplateRows()
		normalTemplate.Visible = false
		hoverTemplate.Visible = false
		matchedTemplate.Visible = false
		clickedTemplate.Visible = false
		notFoundTemplate.Visible = false
	end
	hideTemplateRows()
	mainWrapper.Visible = false
	setListFixedHeight()
	inputTextBox.ClearTextOnFocus = false
	inputTextBox.PlaceholderText = Config.CommandLibrary.INPUT_PLACEHOLDER
	inputTextBox:GetPropertyChangedSignal("Text"):Connect(updateBlinkCaret)
	inputTextBox:GetPropertyChangedSignal("CursorPosition"):Connect(updateBlinkCaret)
	inputTextBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateBlinkCaret)
	inputTextBox.Focused:Connect(startBlinkCaret)
	inputTextBox.FocusLost:Connect(stopBlinkCaret)
	function ui:bindInputChanged(callback: (string) -> ())
		inputChangedCallback = callback
		inputTextBox:GetPropertyChangedSignal("Text"):Connect(function()
			if suppressInputCallbacks or not panelOpen then
				return
			end
			if inputChangedCallback then
				inputChangedCallback(inputTextBox.Text)
			end
		end)
	end
	function ui:bindInputFocused(callback: () -> ())
		inputFocusedCallback = callback
		inputTextBox.Focused:Connect(function()
			if not panelOpen then
				releaseKeyboardCapture()
				return
			end
			if inputFocusedCallback then
				inputFocusedCallback()
			end
		end)
	end
	function ui:bindExecute(callback: (string) -> ())
		executeCallback = callback
		inputTextBox.FocusLost:Connect(function(enterPressed: boolean)
			if enterPressed and executeCallback then
				executeCallback(inputTextBox.Text)
			end
		end)
		runButton.Activated:Connect(function()
			if executeCallback then
				executeCallback(inputTextBox.Text)
			end
		end)
	end
	function ui:bindCardFilled(callback: (CommandLibraryEntry) -> ())
		cardClickCallback = callback
	end
	function ui:setCloseCallback(callback: () -> ())
		-- CommandLibrary close is handled by controller and topbar.
		-- Keep method for interface consistency with other UI modules.
	end
	function ui:show()
		panelOpen = true
		setInputInteractivity(true)
		mainWrapper.GroupTransparency = 0
		inputWrapper.GroupTransparency = 0
		listWrapper.GroupTransparency = 0
		mainWrapper.Visible = true
		tweenMainScale(PANEL_OPEN_START_SCALE, 1, PANEL_OPEN_TWEEN, nil)
	end
	function ui:hide()
		local wasOpen = panelOpen
		panelOpen = false
		releaseKeyboardCapture()
		if not wasOpen then
			return
		end
		suppressInputCallbacks = true
		inputTextBox.Text = ""
		suppressInputCallbacks = false
		tweenMainScale(1, 0, PANEL_CLOSE_TWEEN, function()
			mainWrapper.Visible = false
			mainScaleRef.Scale = 1
			releaseRows()
			releaseKeyboardCapture()
		end)
	end
	function ui:isVisible(): boolean
		return panelOpen
	end
	function ui:isPanelOpen(): boolean
		return panelOpen
	end
	function ui:getScreenGui(): ScreenGui
		return gui_ :: ScreenGui
	end
	function ui:getMainWrapper(): GuiObject
		return mainWrapper
	end
	function ui:focusInput()
		if not panelOpen then
			return
		end
		setInputInteractivity(true)
		inputTextBox:CaptureFocus()
		-- Defer so the assignment survives Roblox resetting CursorPosition on focus.
		task.defer(function()
			if inputTextBox.Parent ~= nil then
				inputTextBox.CursorPosition = #inputTextBox.Text + 1
			end
		end)
	end
	function ui:setInputText(text: string)
		if not panelOpen then
			suppressInputCallbacks = true
			inputTextBox.Text = text
			suppressInputCallbacks = false
			return
		end
		inputTextBox.Text = text
		-- Defer so the assignment survives Roblox resetting CursorPosition on Text change.
		task.defer(function()
			if inputTextBox.Parent ~= nil then
				inputTextBox.CursorPosition = #inputTextBox.Text + 1
			end
		end)
	end
	function ui:getInputText(): string
		return inputTextBox.Text
	end
	function ui:setPhoneButtonVisible(visible: boolean)
		runButton.Visible = visible
		runButton.Active = visible
		if visible then
			inputTextBox.Size = UDim2.fromScale(0.79, 1)
		else
			inputTextBox.Size = UDim2.fromScale(1, 1)
		end
	end
	function ui:setGhostSuggestion(_text: string?)
		-- Autocomplete ghost text intentionally disabled.
	end
	function ui:renderCommands(entries: { CommandLibraryEntry }, query: string)
		releaseRows()
		hideTemplateRows()
		table.clear(entriesById)
		local hasQuery = query ~= "" and query ~= "/"
		if #entries == 0 then
			notFoundTemplate.Visible = true
			notFoundTemplate.Parent = listCommand
			applyListMeasuredHeight(hasQuery)
			return
		end
		notFoundTemplate.Visible = false
		for index, entry in ipairs(entries) do
			entriesById[entry.id] = entry
			local row = rowPool:acquire()
			if not row then
				log:warn("CommandLibrary row pool exhausted", { index = index, id = entry.id })
				break
			end
			local baseVariant = hasQuery and "matched" or "normal"
			configureRow(row, entry, index, baseVariant)
			table.insert(activeRows, row)
		end
		applyListMeasuredHeight(hasQuery)
	end
	function ui:handleOutsideClose()
		if onCloseCallback then
			onCloseCallback()
		end
	end
	return ui
end
return createCommandLibraryUI
