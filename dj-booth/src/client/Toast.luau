--!strict
-- Short messages at the top of the screen: refusals, "… is live", now playing. Shown to everyone
-- (listeners too), so it lives in its own ScreenGui, not in the panel.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Toast = {}

local gui: ScreenGui? = nil
local token = 0

local function ensure(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "CosmicDJ_Toast"
	g.ResetOnSpawn = false
	g.DisplayOrder = 20
	g.IgnoreGuiInset = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	return g
end

function Toast.show(text: string)
	local g = ensure()
	token += 1
	local mine = token
	local old = g:FindFirstChild("Toast")
	if old then
		old:Destroy()
	end
	local pill = Instance.new("TextLabel")
	pill.Name = "Toast"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 12)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, 32)
	pill.BackgroundColor3 = Theme.C.raised
	pill.BorderSizePixel = 0
	pill.FontFace = Theme.B
	pill.TextSize = 13
	pill.TextColor3 = Theme.W
	pill.Text = text
	pill.BackgroundTransparency = 1
	pill.TextTransparency = 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = pill
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 14)
	p.PaddingRight = UDim.new(0, 14)
	p.Parent = pill
	local s = Instance.new("UIStroke")
	s.Color = Theme.C.line
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = pill
	pill.Parent = g
	TweenService:Create(pill, Theme.FAST, { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
	task.delay(3, function()
		if token == mine and pill.Parent then
			local tw = TweenService:Create(pill, Theme.SLIDE, { BackgroundTransparency = 1, TextTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			pill:Destroy()
		end
	end)
end

return Toast
