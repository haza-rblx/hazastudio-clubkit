--!strict
-- Pointer positions in the space GuiObject.AbsolutePosition is reported in.
--
-- UserInputService:GetMouseLocation() is raw viewport space: it still includes the top-bar
-- GuiInset (58px). AbsolutePosition does not, for every ScreenGui (IgnoreGuiInset only moves the
-- ScreenGui's own origin to -inset), and neither does InputObject.Position. Testing the raw
-- mouse against an AbsolutePosition rect is therefore off by the inset. Measured 2026-10-08:
-- GetMouseLocation (125, 636) vs InputObject.Position (125, 578) for the same click.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local PointerSpace = {}

-- Where the mouse is right now, for code that has no InputObject (per-frame hover loops).
function PointerSpace.mouse(): Vector2
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

-- Where an input event happened (mouse or touch).
function PointerSpace.ofInput(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

return PointerSpace
