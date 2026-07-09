--!strict
-- Client logic for membership Sign tools.

local Players = game:GetService("Players")

local SignGuiTemplate = require(script.Parent.SignGuiTemplate)

local SignClient = {}

local function getGuiTemplate(tool: Tool, localScript: LocalScript): ScreenGui
	local existing = localScript:FindFirstChild("SignGui")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	existing = tool:FindFirstChild("SignGui")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local created = SignGuiTemplate.create()
	created.Parent = localScript
	return created
end

function SignClient.bind(localScript: LocalScript)
	local tool = localScript.Parent
	if not tool or not tool:IsA("Tool") then
		return
	end

	local remote = tool:WaitForChild("RemoteFunction") :: RemoteFunction
	local guiTemplate = getGuiTemplate(tool, localScript)

	tool.Equipped:Connect(function()
		local player = Players.LocalPlayer
		local oldGui = player.PlayerGui:FindFirstChild("SignGui")
		if oldGui then
			oldGui:Destroy()
		end

		local clonedGui = guiTemplate:Clone()
		clonedGui.Parent = player.PlayerGui

		local frame = clonedGui:FindFirstChild("Frame")
		if not frame or not frame:IsA("Frame") then
			return
		end
		local textBox = frame:FindFirstChild("TextBox")
		local textButton = frame:FindFirstChild("TextButton")
		local closeButton = frame:FindFirstChild("CloseButton")
		if not textBox or not textBox:IsA("TextBox") then
			return
		end
		if not textButton or not textButton:IsA("TextButton") then
			return
		end
		if not closeButton or not closeButton:IsA("TextButton") then
			return
		end

		textButton.MouseButton1Click:Connect(function()
			local letters = textBox.Text
			local ok, err = remote:InvokeServer(letters)
			if ok then
				textButton.Text = "Successfully changed!"
				task.wait(1)
				textButton.Text = "Submit"
			else
				textButton.Text = "Failed!"
				task.wait(1)
				textButton.Text = "Submit"
				if err then
					warn(err)
				end
			end
		end)

		closeButton.MouseButton1Click:Connect(function()
			clonedGui:Destroy()
		end)
	end)

	tool.Unequipped:Connect(function()
		local player = Players.LocalPlayer
		local found = player.PlayerGui:FindFirstChild("SignGui")
		if found then
			found:Destroy()
		end
	end)
end

return SignClient
