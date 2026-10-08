--!strict
-- Onboarding (CONTEXT.md "Onboarding"): constants, colours, small GUI helpers and the session
-- context shared by OnboardingUI (shell), OnboardingControls, OnboardingStage and OnboardingSteps.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AccentSurfaceTint = require(script.Parent.Parent.Parent.Services.AccentSurfaceTint)

-- What a pick does for real. Wired by OnboardingController to the Settings / Profile paths.
export type Apply = {
	theme: (id: string) -> (),
	-- "Single" | "Taken" | "For Fun" (the profile key for "For Fun" is "Fun")
	status: (label: string) -> (),
	-- "Low" | "Balance" | "High" (the stored preset for "Balance" is "Balanced")
	quality: (name: string) -> (),
	-- What the player has today, in the same labels.
	currentStatus: string,
	currentQuality: string,
	-- "Don't show again" tick on the last step; stored only when the player finishes.
	dismiss: (dismissed: boolean) -> (),
}

export type Picks = { theme: string?, status: string?, quality: string?, dontShow: boolean? }

-- GUI the modal clones from; every field may be nil and every user of it checks.
export type Sources = {
	loadingScreen: any,
	settingsTab: any,
	profileTab: any,
	topBarMenu: any,
	questPopup: any,
	reminderCard: any,
	summarySrc: any,
	menuPillSrc: any,
}

export type Ctx = {
	gui: any,
	shell: any,
	stage: any,
	stageBg: any,
	panel: any,
	wipe: any,
	shellScale: any,
	conns: { RBXScriptConnection },
	picks: Picks,
	alive: boolean,
	runToken: number,
	src: Sources,
	apply: Apply,
	placeName: string,
}

local Kit = {}

Kit.INTER = "rbxassetid://12187365364"
Kit.SHELL_W = 640
Kit.SHELL_H = 420
Kit.STAGE_W = Kit.SHELL_W / 2
Kit.STAGE_H = Kit.SHELL_H
Kit.TOP_H = 48

Kit.MUTED = Color3.fromHex("7c7c7c")
Kit.BODY = Color3.fromHex("bebebe")
Kit.ACCENT_LABEL = Color3.fromHex("ea4b07")
Kit.ROW_BG = Color3.fromHex("1e1e1e")
Kit.ROW_ON = Color3.fromHex("262626")
Kit.SUB = Color3.fromHex("b1b1b1")
Kit.WHITE = Color3.new(1, 1, 1)

Kit.NO_TINT = AccentSurfaceTint.NO_TINT_ATTRIBUTE
Kit.TOKEN = AccentSurfaceTint.TOKEN_ATTRIBUTE

function Kit.tween(inst: any, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

-- A step's loops and waits end when the session closes or the step is left.
function Kit.live(ctx: Ctx, token: number): boolean
	return ctx.alive and ctx.runToken == token
end

function Kit.animate(ctx: Ctx, token: number, fn: (t: number) -> ())
	local t0 = os.clock()
	local c: RBXScriptConnection
	c = RunService.RenderStepped:Connect(function()
		if not Kit.live(ctx, token) then
			c:Disconnect()
			return
		end
		fn(os.clock() - t0)
	end)
	table.insert(ctx.conns, c)
end

function Kit.round(inst: Instance, r: UDim): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = inst
	return c
end

function Kit.label(
	parent: Instance,
	text: string,
	size: number,
	weight: Enum.FontWeight,
	color: Color3,
	order: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	l.FontFace = Font.new(Kit.INTER, weight, Enum.FontStyle.Normal)
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

function Kit.textLabel(parent: Instance, text: string, size: number, weight: Enum.FontWeight, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Font.new(Kit.INTER, weight, Enum.FontStyle.Normal)
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

-- A clone of a design template without its scripts, so it is a picture, not a second live control.
function Kit.cleanClone(src: Instance): any
	local c = src:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("UIDragDetector") then
			d:Destroy()
		end
	end
	if c:GetAttribute("UIMotionBound") ~= nil then
		c:SetAttribute("UIMotionBound", nil)
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:GetAttribute("UIMotionBound") ~= nil then
			d:SetAttribute("UIMotionBound", nil)
		end
	end
	return c
end

-- root.a.b.c, or nil as soon as a name is missing (buyer places may lack parts of the design).
function Kit.find(root: Instance?, ...: string): any
	local node: Instance? = root
	for _, name in ipairs({ ... }) do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

return Kit
