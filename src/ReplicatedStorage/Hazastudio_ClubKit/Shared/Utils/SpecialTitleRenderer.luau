--!strict
-- Applies TitleColorPreset animations to 01-SpecialTitle > SpecialTitleText.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleFontUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes = TitleColorPreset.AnimationModes

export type ApplyOptions = {
	text: string,
	font: string?,
	size: string?,
	presetMode: string?,
}

local SpecialTitleRenderer = {}

local rowEffects: { [Frame]: any } = {}
local TITLE_TEXT_HOST_NAME = "TitleTextHost"

local function resolveLabel(row: Frame): TextLabel?
	local direct = row:FindFirstChild("SpecialTitleText")
	if direct and direct:IsA("TextLabel") then
		return direct
	end

	local host = row:FindFirstChild(TITLE_TEXT_HOST_NAME)
	if host then
		local hosted = host:FindFirstChild("SpecialTitleText")
		if hosted and hosted:IsA("TextLabel") then
			return hosted
		end
	end

	local fallback = row:FindFirstChildWhichIsA("TextLabel", true)
	if fallback and fallback:IsA("TextLabel") then
		return fallback
	end
	return nil
end

local function ensureTitleTextHost(row: Frame, label: TextLabel): Frame
	local existing = row:FindFirstChild(TITLE_TEXT_HOST_NAME)
	local host: Frame
	if existing and existing:IsA("Frame") then
		host = existing
	else
		host = Instance.new("Frame")
		host.Name = TITLE_TEXT_HOST_NAME
		host.BackgroundTransparency = 1
		host.BorderSizePixel = 0
		host.ZIndex = label.ZIndex
		host.Parent = row
	end

	host.ClipsDescendants = false
	host.AnchorPoint = Vector2.new(0.5, 0.5)
	host.Position = UDim2.fromScale(0.5, 0.5)
	host.Size = UDim2.fromScale(1, 1)

	if label.Parent ~= host then
		label.Parent = host
	end

	return host
end

local function moveRuntimeScaleToHost(row: Frame, host: Frame, textScale: number)
	local rowScale = row:FindFirstChild("RuntimeUIScale")
	if rowScale then
		rowScale:Destroy()
	end

	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("TextLabel") then
			local nestedScale = child:FindFirstChild("RuntimeUIScale")
			if nestedScale then
				nestedScale:Destroy()
			end
		end
	end

	local runtimeScale = host:FindFirstChild("RuntimeUIScale") :: UIScale?
	if not runtimeScale then
		local created = Instance.new("UIScale")
		created.Name = "RuntimeUIScale"
		created.Parent = host
		runtimeScale = created
	end
	runtimeScale.Scale = textScale
end

function SpecialTitleRenderer.clearRowBackground(row: Frame)
	row.BackgroundTransparency = 1
	row.ClipsDescendants = false

	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("UIGradient") then
			(child :: UIGradient).Enabled = false
		end
	end

	local label = resolveLabel(row)
	if label then
		label.BackgroundTransparency = 1
	end
end

function SpecialTitleRenderer.destroy(row: Frame)
	local effect = rowEffects[row]
	if effect then
		pcall(function()
			effect:Destroy()
		end)
		rowEffects[row] = nil
	end
end

local function normalizeSpecialTitleLayout(row: Frame)
	row.AnchorPoint = Vector2.new(0, 0)
	row.Position = UDim2.fromScale(0, 0)
	row.ClipsDescendants = false
	row.Size = UDim2.new(1, 0, row.Size.Y.Scale, row.Size.Y.Offset)

	local padding = row:FindFirstChildWhichIsA("UIPadding")
	if padding then
		padding.PaddingLeft = UDim.new(0, 0)
		padding.PaddingRight = UDim.new(0, 0)
		padding.PaddingTop = UDim.new(0, 0)
		padding.PaddingBottom = UDim.new(0, 0)
	end

	local label = resolveLabel(row)
	if not label then
		return
	end

	local host = ensureTitleTextHost(row, label)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center

	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			(descendant :: UIStroke).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end
	end

	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end

	local hostScale = host:FindFirstChild("RuntimeUIScale") :: UIScale?
	local labelScale = label:FindFirstChild("RuntimeUIScale")
	if labelScale and labelScale:IsA("UIScale") and hostScale then
		hostScale.Scale = labelScale.Scale
		labelScale:Destroy()
	elseif labelScale and labelScale:IsA("UIScale") then
		labelScale.Parent = host
	end
end

function SpecialTitleRenderer.normalizeLayout(row: Frame)
	normalizeSpecialTitleLayout(row)
end

function SpecialTitleRenderer.applyRowSize(row: Frame, sizeKey: string?)
	normalizeSpecialTitleLayout(row)

	local key = if type(sizeKey) == "string" and sizeKey ~= "" then sizeKey else "M"
	local heightScale = Config.Admin.TITLE_SIZE_HEIGHT_SCALE[key]
		or Config.Admin.TITLE_SIZE_HEIGHT_SCALE.M
	local textScale = Config.Admin.TITLE_SIZE_TEXT_SCALE[key]
		or Config.Admin.TITLE_SIZE_TEXT_SCALE.M
		or 1
	row.Size = UDim2.new(1, 0, heightScale, 0)

	local label = resolveLabel(row)
	if label then
		local host = ensureTitleTextHost(row, label)
		moveRuntimeScaleToHost(row, host, textScale)
	end
end

function SpecialTitleRenderer.apply(row: Frame, options: ApplyOptions)
	SpecialTitleRenderer.destroy(row)
	SpecialTitleRenderer.clearRowBackground(row)

	SpecialTitleRenderer.applyRowSize(row, options.size)

	local presetMode = options.presetMode
	if type(presetMode) ~= "string" or presetMode == "" or not AnimationModes.IsPreset(presetMode) then
		return
	end

	local label = resolveLabel(row)
	if not label then
		return
	end

	label.Text = options.text
	label.BackgroundTransparency = 1

	local speed = Config.Admin.TITLE_PRESET_SPEED or 0.42
	local size = Config.Admin.TITLE_PRESET_SIZE or 1.5

	local ok, effect = pcall(function()
		return TitleColorPreset.new(label, presetMode, speed, size, true)
	end)
	if ok and effect then
		rowEffects[row] = effect
	end

	normalizeSpecialTitleLayout(row)

	local labelAfter = resolveLabel(row)
	if labelAfter then
		TitleFontUtil.applyToTextLabel(labelAfter, options.font)
		for _, descendant in ipairs(labelAfter:GetDescendants()) do
			if descendant:IsA("UIStroke") then
				(descendant :: UIStroke).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			end
		end
		local stroke = labelAfter:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end
	end
end

return SpecialTitleRenderer
