--!strict
-- Keeps a TextLabel on exactly one line: the label's designed TextSize is the ceiling, and it
-- steps down until the whole text fits the label's width (TextTruncate stays the last resort
-- below MIN). TextScaled cannot do this — the engine forces TextWrapped on with it.
-- The label needs a fixed width (no AutomaticSize X) and must be laid out, i.e. its ScreenGui
-- enabled and every ancestor visible; call on the frame after it is shown.

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local DEFAULT_MIN_TEXT_SIZE = 12
-- Rendering under UIScale rounds glyph sizes; measured bounds that fill the width exactly
-- still spill. Same headroom as the donation amount fit (measured in PARKLAB).
local FIT_HEADROOM = 0.97
local DESIGN_TEXT_SIZE_ATTRIBUTE = "TextFitDesignSize"

local TextFit = {}

local function cumulativeScale(label: Instance): number
	local scale = 1
	local node: Instance? = label
	while node do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return math.max(scale, 0.01)
end

function TextFit.singleLine(label: TextLabel, minTextSize: number?)
	local ceiling = label:GetAttribute(DESIGN_TEXT_SIZE_ATTRIBUTE)
	if type(ceiling) ~= "number" then
		ceiling = label.TextSize
		label:SetAttribute(DESIGN_TEXT_SIZE_ATTRIBUTE, ceiling)
	end
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd

	local floor = math.max(1, math.floor(tonumber(minTextSize) or DEFAULT_MIN_TEXT_SIZE))
	local available = label.AbsoluteSize.X / cumulativeScale(label) * FIT_HEADROOM
	local size = ceiling :: number
	if available > 0 and label.ContentText ~= "" then
		local params = Instance.new("GetTextBoundsParams")
		params.Text = label.ContentText
		params.Font = label.FontFace
		params.Width = math.huge
		while size > floor do
			params.Size = size
			local ok, bounds = pcall(function()
				return TextService:GetTextBoundsAsync(params)
			end)
			if not ok or bounds.X <= available then
				break
			end
			size -= 1
		end
	end
	label.TextSize = size
end

--- Same, one frame later — for a label that was just parented or made visible.
function TextFit.singleLineNextFrame(label: TextLabel, minTextSize: number?)
	task.spawn(function()
		RunService.Heartbeat:Wait()
		if label.Parent then
			TextFit.singleLine(label, minTextSize)
		end
	end)
end

return TextFit
