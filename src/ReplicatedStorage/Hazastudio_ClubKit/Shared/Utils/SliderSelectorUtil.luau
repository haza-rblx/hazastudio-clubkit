--!strict
--[[
	Shared helpers for 2-SliderSelector + BackgroundPill tab headers.
	Used by Music, Donation, Gift, Couple, etc.
]]

local TweenService = game:GetService("TweenService")

export type TabButtonSpec = {
	legacyNames: { string }?,
	optionIndex: number,
	defaultLabel: string?,
}

local SliderSelectorUtil = {}

function SliderSelectorUtil.getOptionsContainer(selectorOuter: GuiObject): GuiObject
	local inner = selectorOuter:FindFirstChild("2-SliderSelector")
	if inner and inner:IsA("GuiObject") then
		return inner :: GuiObject
	end
	return selectorOuter
end

function SliderSelectorUtil.getBackgroundPill(selectorOuter: GuiObject): GuiObject?
	local pill = selectorOuter:FindFirstChild("BackgroundPill")
	if pill and pill:IsA("GuiObject") then
		return pill :: GuiObject
	end
	return nil
end

function SliderSelectorUtil.collectTabButtons(container: Instance): { TextButton }
	local buttons: { TextButton } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextButton") then
			table.insert(buttons, child :: TextButton)
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

function SliderSelectorUtil.resolveTabButton(
	container: Instance,
	spec: TabButtonSpec,
	allButtons: { TextButton }
): TextButton?
	if spec.legacyNames then
		for _, name in ipairs(spec.legacyNames) do
			local found = container:FindFirstChild(name)
			if found and found:IsA("TextButton") then
				return found :: TextButton
			end
		end
	end

	local option = container:FindFirstChild("Option" .. tostring(spec.optionIndex))
	if option and option:IsA("TextButton") then
		return option :: TextButton
	end

	return allButtons[spec.optionIndex]
end

function SliderSelectorUtil.applyTabLabel(button: TextButton, defaultLabel: string)
	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	local target: Instance = if label then label else button
	if not (target:IsA("TextLabel") or target:IsA("TextButton")) then
		return
	end
	local textObj = target :: TextLabel
	local text = textObj.Text
	if text == "" or string.find(string.lower(text), "option", 1, true) then
		textObj.Text = defaultLabel
	end
end

function SliderSelectorUtil.setTabButtonSelected(button: TextButton, selected: boolean)
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			local gradient = descendant :: UIGradient
			local lowerName = string.lower(gradient.Name)
			if string.find(lowerName, "enabled", 1, true) or lowerName == "uigradient-gold" then
				gradient.Enabled = selected
			elseif string.find(lowerName, "disabled", 1, true) or lowerName == "uigradient-normal" then
				gradient.Enabled = not selected
			end
		end
	end

	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIGradient") then
			local gradient = child :: UIGradient
			if gradient.Name == "UIGradient-Gold" then
				gradient.Enabled = selected
			elseif gradient.Name == "UIGradient-Normal" or gradient.Name == "GradientDisabled" then
				gradient.Enabled = not selected
			end
		end
	end

	local nestedLabel = button:FindFirstChildWhichIsA("TextLabel", true)
	if nestedLabel then
		nestedLabel.TextTransparency = 0
	end
	button.TextTransparency = 0
end

function SliderSelectorUtil.setTabButtonDimmed(button: TextButton, dimmed: boolean)
	button.Interactable = not dimmed
	local transparency = if dimmed then 0.5 else 0
	button.TextTransparency = transparency
	local nestedLabel = button:FindFirstChildWhichIsA("TextLabel", true)
	if nestedLabel then
		nestedLabel.TextTransparency = transparency
	end
end

function SliderSelectorUtil.filterVisibleTabButtons(allButtons: { TextButton }): { TextButton }
	local visibleButtons: { TextButton } = {}
	for _, button in ipairs(allButtons) do
		if button.Visible then
			table.insert(visibleButtons, button)
		end
	end
	return visibleButtons
end

function SliderSelectorUtil.animateSlidingPill(
	backgroundPill: GuiObject,
	selectedButton: TextButton,
	allButtons: { TextButton }
)
	local visibleButtons = SliderSelectorUtil.filterVisibleTabButtons(allButtons)
	if #visibleButtons == 0 then
		visibleButtons = allButtons
	end

	local selectedIndex = 0
	local totalButtons = #visibleButtons
	for i, button in ipairs(visibleButtons) do
		if button == selectedButton then
			selectedIndex = i
			break
		end
	end

	if selectedIndex == 0 or totalButtons == 0 then
		return
	end

	local pillWidthScale = 1 / totalButtons
	local currentSize = backgroundPill.Size
	local targetSize = UDim2.new(pillWidthScale, 0, currentSize.Y.Scale, currentSize.Y.Offset)

	local normalizedPos = if totalButtons > 1 then (selectedIndex - 1) / (totalButtons - 1) else 0.5
	local targetAnchorPoint = Vector2.new(normalizedPos, 0.5)
	local targetPosition = UDim2.new(normalizedPos, 0, 0.5, 0)

	backgroundPill.AnchorPoint = targetAnchorPoint
	local tween = TweenService:Create(
		backgroundPill,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPosition, Size = targetSize }
	)
	tween:Play()
end

return SliderSelectorUtil
