-- Place-only: remake SignGui (HyperOS AMOLED) + DualGlowStick color picker.
-- Not Club Kit engine. Run in Edit via MCP execute_luau / Command Bar.

local ServerStorage = game:GetService("ServerStorage")
local results = {}

local C = {
	page = Color3.fromHex("#000000"),
	card = Color3.fromHex("#111111"),
	elevated = Color3.fromHex("#1a1a1a"),
	text = Color3.fromHex("#ffffff"),
	muted = Color3.fromHex("#a0a0a0"),
	faint = Color3.fromHex("#6e6e6e"),
	blue = Color3.fromHex("#0a84ff"),
	red = Color3.fromHex("#ff453a"),
}

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 16)
	c.Parent = inst
	return c
end

local function pad(inst, t, r, b, l)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r or t)
	p.PaddingBottom = UDim.new(0, b or t)
	p.PaddingLeft = UDim.new(0, l or t)
	p.Parent = inst
	return p
end

local function buildSignGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SignGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = C.page
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = gui

	-- Keep name "Frame" for existing LocalScript paths
	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 16)
	frame.Size = UDim2.fromOffset(360, 240)
	frame.BackgroundColor3 = C.card
	frame.BorderSizePixel = 0
	frame.ZIndex = 2
	frame.Parent = gui
	corner(frame, 20)
	pad(frame, 20, 20, 20, 20)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -44, 0, 24)
	title.Position = UDim2.fromOffset(0, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = C.text
	title.Text = "Edit sign"
	title.ZIndex = 3
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -44, 0, 18)
	subtitle.Position = UDim2.fromOffset(0, 26)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = C.faint
	subtitle.Text = "Text appears on your handheld board"
	subtitle.ZIndex = 3
	subtitle.Parent = frame

	-- Names required by LocalScript: TextBox, TextButton, CloseButton
	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AutoButtonColor = true
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, -4)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = C.elevated
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = C.muted
	close.Text = "✕"
	close.ZIndex = 4
	close.Parent = frame
	corner(close, 12)

	local box = Instance.new("TextBox")
	box.Name = "TextBox"
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextWrapped = true
	box.Text = ""
	box.PlaceholderText = "Type your message…"
	box.PlaceholderColor3 = C.faint
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 15
	box.TextColor3 = C.text
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.BackgroundColor3 = C.elevated
	box.BorderSizePixel = 0
	box.Position = UDim2.fromOffset(0, 56)
	box.Size = UDim2.new(1, 0, 0, 96)
	box.ZIndex = 3
	box.Parent = frame
	corner(box, 14)
	pad(box, 12, 12, 12, 12)

	local submit = Instance.new("TextButton")
	submit.Name = "TextButton"
	submit.AutoButtonColor = true
	submit.Size = UDim2.new(1, 0, 0, 44)
	submit.Position = UDim2.new(0, 0, 1, -44)
	submit.BackgroundColor3 = C.blue
	submit.BorderSizePixel = 0
	submit.Font = Enum.Font.GothamBold
	submit.TextSize = 15
	submit.TextColor3 = C.text
	submit.Text = "Save text"
	submit.ZIndex = 3
	submit.Parent = frame
	corner(submit, 22)

	return gui
end

local function buildGlowColorGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DualGlowColorGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 75
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 12)
	card.Size = UDim2.fromOffset(420, 168)
	card.BackgroundColor3 = C.card
	card.BorderSizePixel = 0
	card.Parent = gui
	corner(card, 18)
	pad(card, 12, 12, 10, 12)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = C.text
	title.Text = "Glow color"
	title.Parent = card

	local solidsFrame = Instance.new("Frame")
	solidsFrame.Name = "Swatches"
	solidsFrame.BackgroundTransparency = 1
	solidsFrame.Position = UDim2.fromOffset(0, 26)
	solidsFrame.Size = UDim2.new(1, 0, 0, 56)
	solidsFrame.Parent = card

	local solidsLayout = Instance.new("UIGridLayout")
	solidsLayout.CellSize = UDim2.fromOffset(28, 28)
	solidsLayout.CellPadding = UDim2.fromOffset(6, 6)
	solidsLayout.FillDirectionMaxCells = 8
	solidsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	solidsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	solidsLayout.Parent = solidsFrame

	local solids = {
		{ "White", Color3.fromRGB(231, 231, 236) },
		{ "Ice", Color3.fromRGB(180, 230, 255) },
		{ "Blue", Color3.fromHex("#0a84ff") },
		{ "Cyan", Color3.fromRGB(90, 220, 240) },
		{ "Mint", Color3.fromRGB(100, 245, 200) },
		{ "Green", Color3.fromRGB(50, 215, 75) },
		{ "Lime", Color3.fromRGB(180, 255, 60) },
		{ "Yellow", Color3.fromRGB(255, 214, 10) },
		{ "Orange", Color3.fromRGB(255, 159, 10) },
		{ "Red", Color3.fromRGB(255, 69, 58) },
		{ "Pink", Color3.fromRGB(255, 105, 180) },
		{ "HotPink", Color3.fromRGB(255, 55, 160) },
		{ "Magenta", Color3.fromRGB(255, 55, 255) },
		{ "Purple", Color3.fromRGB(175, 120, 255) },
		{ "Violet", Color3.fromRGB(120, 80, 255) },
		{ "Gold", Color3.fromRGB(255, 200, 80) },
	}

	for i, entry in ipairs(solids) do
		local btn = Instance.new("TextButton")
		btn.Name = "Swatch_" .. entry[1]
		btn.LayoutOrder = i
		btn.AutoButtonColor = true
		btn.Size = UDim2.fromOffset(28, 28)
		btn.BackgroundColor3 = entry[2]
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn:SetAttribute("GlowMode", "solid")
		btn:SetAttribute("GlowColor", entry[2]:ToHex())
		btn.Parent = solidsFrame
		corner(btn, 999)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.25
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.72
		stroke.Parent = btn
	end

	local multiLabel = Instance.new("TextLabel")
	multiLabel.Name = "MultiLabel"
	multiLabel.BackgroundTransparency = 1
	multiLabel.Position = UDim2.fromOffset(0, 90)
	multiLabel.Size = UDim2.new(1, 0, 0, 14)
	multiLabel.Font = Enum.Font.GothamMedium
	multiLabel.TextSize = 11
	multiLabel.TextXAlignment = Enum.TextXAlignment.Left
	multiLabel.TextColor3 = C.faint
	multiLabel.Text = "Fun / multi"
	multiLabel.Parent = card

	local multiFrame = Instance.new("Frame")
	multiFrame.Name = "MultiSwatches"
	multiFrame.BackgroundTransparency = 1
	multiFrame.Position = UDim2.fromOffset(0, 108)
	multiFrame.Size = UDim2.new(1, 0, 0, 36)
	multiFrame.Parent = card

	local multiLayout = Instance.new("UIListLayout")
	multiLayout.FillDirection = Enum.FillDirection.Horizontal
	multiLayout.Padding = UDim.new(0, 8)
	multiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	multiLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	multiLayout.Parent = multiFrame

	local multis = {
		{ "Rainbow", Color3.fromRGB(255, 100, 180), { "ff3b30", "ff9500", "ffcc00", "34c759", "00c7be", "0a84ff", "bf5af2" } },
		{ "Neon", Color3.fromRGB(0, 255, 200), { "00ffd0", "ff00e5", "ffe600" } },
		{ "Sunset", Color3.fromRGB(255, 120, 80), { "ff453a", "ff9f0a", "ff6b9d", "bf5af2" } },
		{ "Galaxy", Color3.fromRGB(140, 100, 255), { "5e5ce6", "bf5af2", "ff66cc", "64d2ff" } },
		{ "Fire", Color3.fromRGB(255, 100, 40), { "ff2d00", "ff6a00", "ffd000" } },
		{ "Cotton", Color3.fromRGB(255, 180, 230), { "ff9ad5", "a8f0ff", "ffffff", "d4b5ff" } },
		{ "Ocean", Color3.fromRGB(40, 180, 255), { "003366", "0a84ff", "64d2ff", "00ffcc" } },
		{ "Candy", Color3.fromRGB(255, 80, 160), { "ff2d55", "ff7ab8", "7afff0", "ffd60a" } },
	}

	for _, entry in ipairs(multis) do
		local btn = Instance.new("TextButton")
		btn.Name = "Multi_" .. entry[1]
		btn.AutoButtonColor = true
		btn.Size = UDim2.fromOffset(36, 28)
		btn.BackgroundColor3 = entry[2]
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 9
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = entry[1]
		btn:SetAttribute("GlowMode", "seq")
		btn:SetAttribute("GlowSeq", table.concat(entry[3], ","))
		btn:SetAttribute("GlowColor", entry[3][1])
		btn.Parent = multiFrame
		corner(btn, 10)
		if entry[1] == "Rainbow" then
			btn.Text = "✨"
			btn.TextSize = 14
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 160, 0)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 220, 0)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(60, 220, 90)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(60, 180, 255)),
				ColorSequenceKeypoint.new(0.85, Color3.fromRGB(120, 90, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 200)),
			})
			grad.Parent = btn
		end
	end

	return gui
end

local GlowLocalSource = [[
-- Place-only DualGlowStick color picker (not Club Kit).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local tool = script.Parent
local guiTemplate = script:WaitForChild("DualGlowColorGui")

local cycleConn: RBXScriptConnection? = nil

local function stopCycle()
	if cycleConn then
		cycleConn:Disconnect()
		cycleConn = nil
	end
end

local function parseHexList(raw: string): { Color3 }
	local out = {}
	for token in string.gmatch(raw, "[^,]+") do
		local hex = string.gsub(token, "%s+", "")
		local ok, color = pcall(function()
			return Color3.fromHex(hex)
		end)
		if ok and typeof(color) == "Color3" then
			table.insert(out, color)
		end
	end
	return out
end

local function makeSequence(colors: { Color3 }): ColorSequence
	if #colors == 0 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	end
	if #colors == 1 then
		local c = colors[1]
		local fade = c:Lerp(Color3.new(1, 1, 1), 0.55)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, c),
			ColorSequenceKeypoint.new(1, fade),
		})
	end
	local keys = {}
	for i, c in ipairs(colors) do
		local t = (i - 1) / (#colors - 1)
		table.insert(keys, ColorSequenceKeypoint.new(t, c))
	end
	return ColorSequence.new(keys)
end

local function tintFx(root: Instance, partColor: Color3, seq: ColorSequence)
	for _, d in root:GetDescendants() do
		if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then
			d.Color = partColor
		elseif d:IsA("ParticleEmitter") then
			d.Color = seq
		elseif d:IsA("Trail") or d:IsA("Beam") then
			d.Color = seq
		end
	end
end

local function applyPalette(colors: { Color3 }, cycling: boolean)
	stopCycle()
	if #colors == 0 then
		return
	end
	local seq = makeSequence(colors)
	local primary = colors[1]

	local function paint(partColor: Color3)
		for _, name in ipairs({ "Handle", "Handle2" }) do
			local part = tool:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Color = partColor
				tintFx(part, partColor, seq)
			end
		end
		for _, d in tool:GetChildren() do
			if d:IsA("Trail") or d:IsA("Beam") then
				d.Color = seq
			end
		end
	end

	paint(primary)

	if cycling and #colors > 1 then
		local t0 = os.clock()
		cycleConn = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - t0) * 1.35
			local idx = math.floor(t) % #colors + 1
			local nxt = idx % #colors + 1
			local a = t - math.floor(t)
			local blended = colors[idx]:Lerp(colors[nxt], a)
			for _, name in ipairs({ "Handle", "Handle2" }) do
				local part = tool:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					part.Color = blended
					for _, d in part:GetDescendants() do
						if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then
							d.Color = blended
						end
					end
				end
			end
		end)
	end

	local hexes = {}
	for _, c in ipairs(colors) do
		table.insert(hexes, c:ToHex())
	end
	tool:SetAttribute("GlowColorHex", hexes[1])
	tool:SetAttribute("GlowSeq", table.concat(hexes, ","))
	tool:SetAttribute("GlowCycle", cycling)
end

local function restoreSaved()
	local raw = tool:GetAttribute("GlowSeq")
	local cycling = tool:GetAttribute("GlowCycle") == true
	if typeof(raw) == "string" and #raw >= 6 then
		local colors = parseHexList(raw)
		if #colors > 0 then
			applyPalette(colors, cycling or #colors > 1)
			return
		end
	end
	local hex = tool:GetAttribute("GlowColorHex")
	if typeof(hex) == "string" and #hex >= 6 then
		local ok, color = pcall(function()
			return Color3.fromHex(hex)
		end)
		if ok and typeof(color) == "Color3" then
			applyPalette({ color }, false)
		end
	end
end

restoreSaved()

tool.Equipped:Connect(function()
	restoreSaved()
	local player = Players.LocalPlayer
	local old = player.PlayerGui:FindFirstChild("DualGlowColorGui")
	if old then
		old:Destroy()
	end
	local gui = guiTemplate:Clone()
	gui.Parent = player.PlayerGui

	local function wire(container: Instance?)
		if not container then
			return
		end
		for _, btn in container:GetChildren() do
			if btn:IsA("TextButton") then
				btn.MouseButton1Click:Connect(function()
					local mode = btn:GetAttribute("GlowMode")
					if mode == "seq" then
						local raw = btn:GetAttribute("GlowSeq")
						if typeof(raw) == "string" then
							local colors = parseHexList(raw)
							applyPalette(colors, true)
						end
					else
						local hex = btn:GetAttribute("GlowColor")
						if typeof(hex) == "string" then
							local ok, color = pcall(function()
								return Color3.fromHex(hex)
							end)
							if ok and typeof(color) == "Color3" then
								applyPalette({ color }, false)
							end
						end
					end
				end)
			end
		end
	end

	local card = gui:FindFirstChild("Card")
	if card then
		wire(card:FindFirstChild("Swatches"))
		wire(card:FindFirstChild("MultiSwatches"))
	end
end)

tool.Unequipped:Connect(function()
	stopCycle()
	local player = Players.LocalPlayer
	local found = player.PlayerGui:FindFirstChild("DualGlowColorGui")
	if found then
		found:Destroy()
	end
end)
]]

local toolsRoot = ServerStorage:FindFirstChild("Tools")
if not toolsRoot then
	return { error = "ServerStorage.Tools missing" }
end

local signCount = 0
local glowCount = 0

for _, roleFolder in ipairs(toolsRoot:GetChildren()) do
	if roleFolder:IsA("Folder") then
		local sign = roleFolder:FindFirstChild("Sign")
		if sign and sign:IsA("Tool") then
			local ls = sign:FindFirstChildWhichIsA("LocalScript")
			if ls then
				local old = ls:FindFirstChild("SignGui")
				if old then
					old:Destroy()
				end
				local gui = buildSignGui()
				gui.Parent = ls
				signCount += 1
			end
		end

		local dual = roleFolder:FindFirstChild("DualGlowStick")
		if dual and dual:IsA("Tool") then
			local colorLs = dual:FindFirstChild("ColorLocalScript")
			if not colorLs then
				colorLs = Instance.new("LocalScript")
				colorLs.Name = "ColorLocalScript"
				colorLs.Parent = dual
			end
			local oldGui = colorLs:FindFirstChild("DualGlowColorGui")
			if oldGui then
				oldGui:Destroy()
			end
			local gui = buildGlowColorGui()
			gui.Parent = colorLs
			colorLs.Source = GlowLocalSource
			glowCount += 1
		end
	end
end

table.insert(results, ("SignGui remade x%d"):format(signCount))
table.insert(results, ("DualGlow color x%d"):format(glowCount))
return results
