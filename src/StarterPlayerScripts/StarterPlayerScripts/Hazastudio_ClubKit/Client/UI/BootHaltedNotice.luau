--!strict
-- Full-screen notice shown when the SERVER halted the kit at boot (ADR 0006
-- boot gate) -- most commonly because HttpService is disabled. The server never
-- wired its remotes, so the client would otherwise sit on a stuck/blank loading
-- screen with no explanation. This says why, and how to fix it.

local Players = game:GetService("Players")

local BootHaltedNotice = {}

type Reason = { title: string, body: string }

local REASONS: { [string]: Reason } = {
	http_disabled = {
		title = "Club Kit paused",
		body = "HttpService is turned off for this experience, so the kit could not start."
			.. "\n\nEnable “Allow HTTP Requests” in Game Settings → Security, then rejoin.",
	},
}

local FALLBACK: Reason = {
	title = "Club Kit paused",
	body = "The kit could not start on the server. Please contact the venue owner.",
}

local shown = false

function BootHaltedNotice.show(reason: string?): ()
	if shown then
		return
	end
	shown = true

	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local info = REASONS[tostring(reason)] or FALLBACK

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClubKitBootHalted"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	shade.BackgroundTransparency = 0.06
	shade.BorderSizePixel = 0
	shade.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(440, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	card.BorderSizePixel = 0
	card.Parent = shade

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 1
	stroke.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 26)
	pad.PaddingBottom = UDim.new(0, 26)
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 26)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(240, 240, 245)
	title.Text = info.title
	title.TextWrapped = true
	title.LayoutOrder = 1
	title.Parent = card

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Font = Enum.Font.Gotham
	body.TextSize = 15
	body.LineHeight = 1.15
	body.TextColor3 = Color3.fromRGB(188, 188, 198)
	body.Text = info.body
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LayoutOrder = 2
	body.Parent = card

	gui.Parent = playerGui
end

return BootHaltedNotice
