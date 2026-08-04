--!nocheck
--[[
  Lightweight Tween helpers for Club Kit Studio plugin panels.
  Fun, not loud — short springs, fades, progress, confetti-lite.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.DovetailTheme)

local PanelMotion = {}

local C = Theme.colors

local function ti(duration: number?, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(
		duration or 0.28,
		style or Enum.EasingStyle.Quart,
		dir or Enum.EasingDirection.Out
	)
end

function PanelMotion.tween(inst: Instance, props: { [string]: any }, info: TweenInfo?): Tween
	local tween = TweenService:Create(inst, info or ti(), props)
	tween:Play()
	return tween
end

function PanelMotion.ensureUIScale(gui: GuiObject): UIScale
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = gui
	end
	return scale
end

function PanelMotion.press(gui: GuiObject)
	local scale = PanelMotion.ensureUIScale(gui)
	scale.Scale = 0.94
	PanelMotion.tween(scale, { Scale = 1 }, ti(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

function PanelMotion.bindPress(gui: GuiButton)
	gui.MouseButton1Down:Connect(function()
		local scale = PanelMotion.ensureUIScale(gui)
		PanelMotion.tween(scale, { Scale = 0.96 }, ti(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end)
	gui.MouseButton1Up:Connect(function()
		PanelMotion.press(gui)
	end)
	gui.MouseLeave:Connect(function()
		local scale = gui:FindFirstChildOfClass("UIScale")
		if scale and scale.Scale ~= 1 then
			PanelMotion.tween(scale, { Scale = 1 }, ti(0.12))
		end
	end)
end

function PanelMotion.fadeIn(gui: GuiObject, duration: number?)
	if gui:IsA("GuiObject") then
		local startT = gui.BackgroundTransparency
		if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
			gui.TextTransparency = 1
			PanelMotion.tween(gui, { TextTransparency = 0 }, ti(duration or 0.35))
		end
		if startT < 1 then
			local target = startT
			gui.BackgroundTransparency = math.min(1, startT + 0.35)
			PanelMotion.tween(gui, { BackgroundTransparency = target }, ti(duration or 0.35))
		end
	end
end

function PanelMotion.popIn(gui: GuiObject, delaySec: number?)
	local scale = PanelMotion.ensureUIScale(gui)
	scale.Scale = 0.88
	gui.Visible = true
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		gui.TextTransparency = 0.65
	end
	task.delay(delaySec or 0, function()
		if not gui.Parent then
			return
		end
		PanelMotion.tween(scale, { Scale = 1 }, ti(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		if gui:IsA("TextLabel") or gui:IsA("TextButton") then
			PanelMotion.tween(gui, { TextTransparency = 0 }, ti(0.28))
		end
	end)
end

function PanelMotion.staggerIn(items: { GuiObject }, step: number?)
	local gap = step or 0.055
	for i, gui in ipairs(items) do
		PanelMotion.popIn(gui, (i - 1) * gap)
	end
end

function PanelMotion.pulseStatus(label: TextLabel, tone: string?)
	local color = C.faint
	if tone == "ok" or tone == "success" then
		color = C.success
	elseif tone == "warn" or tone == "warning" then
		color = C.warning
	elseif tone == "error" or tone == "fail" then
		color = C.error
	elseif tone == "accent" then
		color = C.blueBright
	end
	label.TextColor3 = color
	local scale = PanelMotion.ensureUIScale(label)
	scale.Scale = 1.04
	PanelMotion.tween(scale, { Scale = 1 }, ti(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	if tone == "ok" or tone == "success" or tone == "accent" or tone == nil then
		task.delay(0.9, function()
			if label.Parent then
				PanelMotion.tween(label, { TextColor3 = C.faint }, ti(0.45))
			end
		end)
	end
end

function PanelMotion.bumpLabel(label: TextLabel, newText: string)
	if label.Text == newText then
		return
	end
	local scale = PanelMotion.ensureUIScale(label)
	PanelMotion.tween(scale, { Scale = 0.82 }, ti(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	task.delay(0.1, function()
		if not label.Parent then
			return
		end
		label.Text = newText
		scale.Scale = 1.12
		PanelMotion.tween(scale, { Scale = 1 }, ti(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)
end

function PanelMotion.heroEntrance(hero: GuiObject, title: TextLabel?)
	local scale = PanelMotion.ensureUIScale(hero)
	scale.Scale = 0.92
	if title then
		title.TextTransparency = 1
	end
	PanelMotion.tween(scale, { Scale = 1 }, ti(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	if title then
		PanelMotion.tween(title, { TextTransparency = 0 }, ti(0.4))
	end
end

function PanelMotion.selectTabChip(tab: TextButton, selected: boolean)
	if selected then
		tab.BackgroundTransparency = 1
		PanelMotion.tween(tab, {
			BackgroundTransparency = 0,
			BackgroundColor3 = C.card,
			TextColor3 = C.text,
		}, ti(0.22))
		local scale = PanelMotion.ensureUIScale(tab)
		scale.Scale = 0.94
		PanelMotion.tween(scale, { Scale = 1 }, ti(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	else
		PanelMotion.tween(tab, {
			BackgroundTransparency = 1,
			TextColor3 = C.faint,
		}, ti(0.18))
	end
end

function PanelMotion.swapPanels(outgoing: GuiObject, incoming: GuiObject)
	incoming.Visible = true
	local inScale = PanelMotion.ensureUIScale(incoming)
	inScale.Scale = 0.97
	incoming.BackgroundTransparency = 1
	PanelMotion.tween(inScale, { Scale = 1 }, ti(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
	outgoing.Visible = false
end

function PanelMotion.channelRing(ring: GuiObject, on: boolean)
	local scale = PanelMotion.ensureUIScale(ring)
	if on then
		PanelMotion.tween(ring, {
			BackgroundColor3 = C.blue,
			TextColor3 = C.text,
		}, ti(0.22))
		scale.Scale = 0.88
		PanelMotion.tween(scale, { Scale = 1 }, ti(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	else
		PanelMotion.tween(ring, {
			BackgroundColor3 = C.elevated,
			TextColor3 = C.muted,
		}, ti(0.18))
	end
end

export type ProgressApi = {
	frame: Frame,
	set: (index: number, total: number) -> (),
	busy: () -> (),
	hide: () -> (),
	show: () -> (),
}

function PanelMotion.createProgress(parent: Instance, layoutOrder: number?): ProgressApi
	local wrap = Instance.new("Frame")
	wrap.Name = "ProgressWrap"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.Visible = false
	wrap.LayoutOrder = layoutOrder or 0
	wrap.ClipsDescendants = true
	wrap.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = C.elevated
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Parent = wrap
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = C.blue
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BackgroundColor3 = C.blueBright
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.AnchorPoint = Vector2.new(1, 0.5)
	glow.Position = UDim2.new(1, 0, 0.5, 0)
	glow.Size = UDim2.fromOffset(10, 10)
	glow.Visible = false
	glow.Parent = fill
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	local indeterminateToken = 0

	local api: ProgressApi = {
		frame = wrap,
		set = function(index: number, total: number)
			wrap.Visible = true
			indeterminateToken += 1
			glow.Visible = true
			local t = math.clamp(if total > 0 then index / total else 0, 0, 1)
			PanelMotion.tween(fill, { Size = UDim2.new(t, 0, 1, 0) }, ti(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end,
		busy = function()
			wrap.Visible = true
			glow.Visible = true
			indeterminateToken += 1
			local token = indeterminateToken
			fill.Size = UDim2.new(0.18, 0, 1, 0)
			task.spawn(function()
				local dir = 1
				while wrap.Parent and wrap.Visible and token == indeterminateToken do
					local goal = if dir > 0 then 0.82 else 0.18
					local tw = PanelMotion.tween(
						fill,
						{ Size = UDim2.new(goal, 0, 1, 0) },
						ti(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					)
					tw.Completed:Wait()
					dir = -dir
				end
			end)
		end,
		hide = function()
			indeterminateToken += 1
			glow.Visible = false
			PanelMotion.tween(fill, { Size = UDim2.new(0, 0, 1, 0) }, ti(0.2))
			task.delay(0.22, function()
				if wrap.Parent then
					wrap.Visible = false
				end
			end)
		end,
		show = function()
			wrap.Visible = true
		end,
	}
	return api
end

function PanelMotion.confetti(parent: GuiObject, duration: number?)
	local layer = Instance.new("Frame")
	layer.Name = "ConfettiLite"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 80
	layer.ClipsDescendants = true
	layer.Parent = parent

	local palette = {
		C.blue,
		C.blueBright,
		C.text,
		C.success,
		Color3.fromHex("#ffffff"),
		C.muted,
	}
	local life = duration or 1.15
	for i = 1, 28 do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = palette[((i - 1) % #palette) + 1]
		bit.Size = UDim2.fromOffset(4 + (i % 4), 4 + ((i * 3) % 5))
		bit.Position = UDim2.new(0.08 + math.random() * 0.84, 0, -0.05, 0)
		bit.Rotation = math.random(-40, 40)
		bit.ZIndex = 81
		bit.Parent = layer
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bit
		local fallY = 0.55 + math.random() * 0.45
		local drift = (math.random() - 0.5) * 0.25
		local delaySec = (i - 1) * 0.012
		task.delay(delaySec, function()
			if not bit.Parent then
				return
			end
			PanelMotion.tween(
				bit,
				{
					Position = UDim2.new(bit.Position.X.Scale + drift, 0, fallY, 0),
					Rotation = bit.Rotation + math.random(-120, 120),
					BackgroundTransparency = 1,
				},
				TweenInfo.new(life * (0.75 + math.random() * 0.35), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			)
		end)
	end
	task.delay(life + 0.45, function()
		if layer.Parent then
			layer:Destroy()
		end
	end)
end

function PanelMotion.showModal(bg: Frame, modal: GuiObject)
	bg.Visible = true
	bg.BackgroundTransparency = 1
	local scale = PanelMotion.ensureUIScale(modal)
	scale.Scale = 0.9
	PanelMotion.tween(bg, { BackgroundTransparency = 0.45 }, ti(0.22))
	PanelMotion.tween(scale, { Scale = 1 }, ti(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

function PanelMotion.hideModal(bg: Frame, modal: GuiObject)
	local scale = PanelMotion.ensureUIScale(modal)
	PanelMotion.tween(bg, { BackgroundTransparency = 1 }, ti(0.18))
	local tw = PanelMotion.tween(scale, { Scale = 0.94 }, ti(0.16))
	tw.Completed:Connect(function()
		bg.Visible = false
		scale.Scale = 1
	end)
end

return PanelMotion
