--!strict
-- Minimal overlay scrollbar: a short pill track (120px) beside a box, with a thin thumb that tracks
-- a ScrollingFrame. Shows while the list moves or the pointer is over it (or when `flash`ed, e.g.
-- as a card opens) and fades out when idle. Track = the theme's surface grey (AccentDomain
-- tintSurface), thumb = the accent fill (white on Multicolor / Graphite). The native bar stays
-- hidden (ImageTransparency 1, thickness 0).
--
-- The pill lives in its own ScreenGui so the box's clipping cannot cut it. Positions are taken
-- relative to that ScreenGui's own AbsolutePosition: with matching inset settings its origin
-- still sat one topbar (58px) off the host GUI's, so assuming 0,0 put the pill too high. Every
-- position is rounded to whole pixels so the 4px thumb stays crisp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)
local AccentService = require(script.Parent.Parent.Services.AccentService)

local OverlayScrollbar = {}

export type Options = {
	-- Which side of `edge` the pill sits on (default "right").
	side: ("left" | "right")?,
	-- What the short track is vertically centred on (default: the scroll itself).
	centerOn: GuiObject?,
}

export type Handle = {
	-- Show the bar for `seconds` (default IDLE_SECONDS) even without input.
	flash: (seconds: number?) -> (),
	destroy: () -> (),
}

local TRACK_WIDTH = 8
local THUMB_WIDTH = 4
local TRACK_HEIGHT = 120
local GAP = 6
local MIN_THUMB = 16
local IDLE_SECONDS = 1
local TRACK_DESIGN_GREY = 44 -- #2C2C2E, tinted with the accent like other surfaces
local FADE_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
local FADE_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad)

local function isOnScreen(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function pill(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	return frame
end

-- `scroll`: the list. `edge`: the box whose side the pill sits outside of.
function OverlayScrollbar.attach(scroll: ScrollingFrame, edge: GuiObject, options: Options?): Handle
	local side = if options and options.side then options.side else "right"
	local centerOn = if options and options.centerOn then options.centerOn else scroll
	local host = scroll:FindFirstAncestorWhichIsA("ScreenGui")
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not host or not playerGui then
		return {
			flash = function(_seconds: number?) end,
			destroy = function() end,
		}
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = scroll.Name .. "OverlayScrollbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = host.IgnoreGuiInset
	gui.ScreenInsets = host.ScreenInsets
	gui.DisplayOrder = host.DisplayOrder + 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Colours are painted here from the accent; the whole-GUI theme must not repaint them.
	gui:SetAttribute("AccentNoTint", true)

	local track = pill("Track")
	local thumb = pill("Thumb")
	thumb.AnchorPoint = Vector2.new(0.5, 0)
	thumb.Parent = track
	track.Parent = gui
	gui.Parent = playerGui

	local showUntil = 0
	local shown = false
	local function setShown(on: boolean)
		if on == shown then
			return
		end
		shown = on
		local info = if on then FADE_IN else FADE_OUT
		TweenService:Create(track, info, { BackgroundTransparency = if on then 0 else 1 }):Play()
		TweenService:Create(thumb, info, { BackgroundTransparency = if on then 0 else 1 }):Play()
	end
	local function flash(seconds: number?)
		showUntil = math.max(showUntil, os.clock() + (seconds or IDLE_SECONDS))
	end
	local function poke()
		flash(IDLE_SECONDS)
	end

	local function paint()
		local r, g, b = AccentDomain.tintSurface(TRACK_DESIGN_GREY, TRACK_DESIGN_GREY, TRACK_DESIGN_GREY + 2, AccentService.get().id)
		track.BackgroundColor3 = if r and g and b
			then Color3.fromRGB(r, g, b)
			else Color3.fromRGB(TRACK_DESIGN_GREY, TRACK_DESIGN_GREY, TRACK_DESIGN_GREY + 2)
		thumb.BackgroundColor3 = if AccentService.isDesign() then Color3.new(1, 1, 1) else AccentService.get().fill
	end
	paint()
	local unsubscribe = AccentService.subscribe(function()
		paint()
	end)

	local connections = {
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(poke),
		scroll.MouseEnter:Connect(poke),
		scroll.MouseMoved:Connect(poke),
		RunService.RenderStepped:Connect(function()
			local window, canvas = scroll.AbsoluteWindowSize.Y, scroll.AbsoluteCanvasSize.Y
			if canvas <= window + 1 or not isOnScreen(scroll) then
				setShown(false)
				return
			end
			local origin = gui.AbsolutePosition
			local x = if side == "left"
				then edge.AbsolutePosition.X - GAP - TRACK_WIDTH
				else edge.AbsolutePosition.X + edge.AbsoluteSize.X + GAP
			local centerY = centerOn.AbsolutePosition.Y + centerOn.AbsoluteSize.Y / 2
			track.Size = UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT)
			track.Position = UDim2.fromOffset(
				math.floor(x - origin.X + 0.5),
				math.floor(centerY - TRACK_HEIGHT / 2 - origin.Y + 0.5)
			)
			local inset = (TRACK_WIDTH - THUMB_WIDTH) / 2
			local inner = TRACK_HEIGHT - inset * 2
			local thumbHeight = math.max(MIN_THUMB, math.floor(inner * window / canvas))
			local progress = math.clamp(scroll.CanvasPosition.Y / (canvas - window), 0, 1)
			thumb.Size = UDim2.fromOffset(THUMB_WIDTH, thumbHeight)
			thumb.Position = UDim2.new(0.5, 0, 0, math.floor(inset + progress * (inner - thumbHeight) + 0.5))
			setShown(os.clock() < showUntil)
		end),
	}

	return {
		flash = flash,
		destroy = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			unsubscribe()
			gui:Destroy()
		end,
	}
end

return OverlayScrollbar
