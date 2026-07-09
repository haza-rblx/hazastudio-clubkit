--!strict

local PaidBroadcastGuiRefs = {}

export type Refs = {
	root: ScreenGui,
	modal: Frame,
	staticTitle: TextLabel,
	messageBox: TextBox,
	continueButton: GuiButton,
	continueText: TextLabel?,
	cancelButton: GuiButton,
}

local function expect(parent: Instance, name: string, timeout: number?): Instance
	local child = parent:WaitForChild(name, timeout or 15)
	assert(child, ("PaidBroadcastGuiRefs: missing '%s' under %s"):format(name, parent:GetFullName()))
	return child
end

local function asFrame(instance: Instance): Frame
	assert(instance:IsA("Frame"), ("Expected Frame, got %s"):format(instance.ClassName))
	return instance :: Frame
end

local function asTextLabel(instance: Instance): TextLabel
	assert(instance:IsA("TextLabel"), ("Expected TextLabel, got %s"):format(instance.ClassName))
	return instance :: TextLabel
end

local function asTextBox(instance: Instance): TextBox
	assert(instance:IsA("TextBox"), ("Expected TextBox, got %s"):format(instance.ClassName))
	return instance :: TextBox
end

local function asGuiButton(instance: Instance): GuiButton
	assert(
		instance:IsA("GuiButton"),
		("Expected GuiButton, got %s at %s"):format(instance.ClassName, instance:GetFullName())
	)
	return instance :: GuiButton
end

function PaidBroadcastGuiRefs.resolve(playerGui: PlayerGui, guiName: string): Refs
	local root = expect(playerGui, guiName, 15)
	assert(root:IsA("ScreenGui"), "PaidBroadcastGuiRefs: root must be ScreenGui")
	local modal = asFrame(expect(root, "InputBroadcastMessageModal", 15))
	local titleFrame = expect(modal, "Title", 15)
	local staticTitle = asTextLabel(expect(titleFrame, "StaticTitle", 15))
	local messageBox = asTextBox(expect(modal, "TextBox", 15))
	local continueButton = asGuiButton(expect(modal, "ContinueSendPaidMessage", 15))
	local cancelButton = asGuiButton(expect(modal, "CancelButton", 15))
	local continueText = continueButton:FindFirstChild("ContinueDonateText")
	local continueLabel = if continueText and continueText:IsA("TextLabel") then continueText :: TextLabel else nil

	return {
		root = root :: ScreenGui,
		modal = modal,
		staticTitle = staticTitle,
		messageBox = messageBox,
		continueButton = continueButton,
		continueText = continueLabel,
		cancelButton = cancelButton,
	}
end

return PaidBroadcastGuiRefs
