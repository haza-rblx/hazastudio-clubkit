--!strict
-- Reusable Sign tool input GUI (cloned to PlayerGui on equip).

local SignGuiTemplate = {}

function SignGuiTemplate.create(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SignGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(320, 180)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.Size = UDim2.new(1, -20, 0, 80)
	textBox.Position = UDim2.fromOffset(10, 10)
	textBox.ClearTextOnFocus = false
	textBox.Text = ""
	textBox.PlaceholderText = "Type sign text..."
	textBox.TextColor3 = Color3.new(1, 1, 1)
	textBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	textBox.Parent = frame

	local submit = Instance.new("TextButton")
	submit.Name = "TextButton"
	submit.Size = UDim2.fromOffset(120, 36)
	submit.Position = UDim2.fromOffset(10, 110)
	submit.Text = "Submit"
	submit.BackgroundColor3 = Color3.fromRGB(0, 170, 127)
	submit.TextColor3 = Color3.new(1, 1, 1)
	submit.Parent = frame

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.Size = UDim2.fromOffset(120, 36)
	close.Position = UDim2.fromOffset(190, 110)
	close.Text = "Close"
	close.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Parent = frame

	return gui
end

return SignGuiTemplate
