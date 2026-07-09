--!strict
-- Client logic for membership Rope tools.

local Players = game:GetService("Players")

local RopeClient = {}

function RopeClient.bind(tool: Tool)
	local remote = tool:WaitForChild("RemoteEvent") :: RemoteEvent
	tool.Activated:Connect(function()
		local mouse = Players.LocalPlayer:GetMouse()
		remote:FireServer(mouse.Target, mouse.Hit)
	end)
end

return RopeClient
