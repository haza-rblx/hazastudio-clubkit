--!strict
-- Client/UI/EventPostPopupUI.luau
-- The event board's post popup (2026-10-09): one large Event card cloned from the Event tab's
-- ImageAnnouncement template (the owner's look: Header + Body, Banner), carrying the post's image.
--   Desktop: banner above the text.   Phone: banner left, text right (a landscape phone is short).
-- The body text scrolls, the Close button stays in view, and the whole card scales down until it
-- fits the screen with a margin. A post without an image drops the banner.

local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)
local EventCardKit = require(script.Parent.EventCardKit)

local GUI_NAME = "EventBoardPopupGui"
local DISPLAY_ORDER = 120
local DIM_TRANSPARENCY = 0.45
local PAD = 12

local DESKTOP = { width = 440, textHeight = 260, margin = 24 }
local PHONE = {
	width = 580,
	height = 290,
	bannerWidth = 250,
	gap = 14,
	margin = 40,
	-- Without an image the text column alone would leave half the card empty.
	widthNoImage = 440,
	heightNoImage = 230,
}

export type Post = {
	header: string,
	category: string,
	title: string,
	date: string,
	body: string,
	imageAssetId: string,
	closeText: string,
}

local EventPostPopupUI = {}
EventPostPopupUI.__index = EventPostPopupUI

-- nil when the template does not have the Event card shape (Header + Body with a Text line).
function EventPostPopupUI.create(playerGui: PlayerGui, template: GuiObject): any?
	local templateBody = template:FindFirstChild("Body")
	if not (template:FindFirstChild("Header") and templateBody and templateBody:FindFirstChild("Text")) then
		return nil
	end
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local self = setmetatable({}, EventPostPopupUI) :: any
	self._connections = {} :: { RBXScriptConnection }
	self._open = false
	self._onClose = nil :: (() -> ())?

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	self._gui = gui

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = DIM_TRANSPARENCY
	dim.BorderSizePixel = 0
	dim.Active = true
	dim.Parent = gui
	table.insert(self._connections, dim.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:close()
		end
	end))

	-- The fit scale lives on a centred full-screen stage, not on the card: UIMotion.popIn borrows the
	-- card's first UIScale, and only the first UIScale under an object applies.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 1)
	stage.ZIndex = 2
	stage.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = stage
	self._scale = scale

	local card = template:Clone()
	card.Name = "Popup"
	card.Visible = true
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Active = true -- a tap on the card must not reach the dim behind it
	card.Parent = stage
	self._card = card
	local header = card:FindFirstChild("Header")
	local cardList = card:FindFirstChildOfClass("UIListLayout")
	self._chromeHeight = (if header and header:IsA("GuiObject") then header.Size.Y.Offset else 0)
		+ (if cardList then cardList.Padding.Offset else 0)

	-- Body: banner + a text column (everything else, in its own order) whose Text line scrolls.
	local body = card:FindFirstChild("Body") :: GuiObject
	body.AutomaticSize = Enum.AutomaticSize.None
	self._body = body
	self._bodyList = body:FindFirstChildOfClass("UIListLayout")
	local padding = body:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingRight = padding.PaddingLeft
	end
	local banner = body:FindFirstChild("Banner")
	self._banner = if banner and banner:IsA("ImageLabel") then banner else nil
	if self._banner then
		self._banner.ScaleType = Enum.ScaleType.Crop
		self._banner.LayoutOrder = 1
	end

	local column = Instance.new("Frame")
	column.Name = "TextColumn"
	column.BackgroundTransparency = 1
	column.LayoutOrder = 2
	column.Parent = body
	local columnList = Instance.new("UIListLayout")
	columnList.SortOrder = Enum.SortOrder.LayoutOrder
	columnList.Parent = column
	self._column = column
	for _, child in ipairs(body:GetChildren()) do
		if child:IsA("GuiObject") and child ~= column and child ~= self._banner then
			child.Parent = column
		end
	end
	-- The banner's own gap sits before the category; without a banner beside or above it, it goes.
	local firstGap = column:FindFirstChild("Gap2")
	if firstGap and firstGap:IsA("GuiObject") then
		firstGap.Visible = false
	end

	local text = column:FindFirstChild("Text") :: TextLabel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TextScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.LayoutOrder = text.LayoutOrder
	scroll.Size = UDim2.fromScale(1, 0)
	scroll.ScrollBarThickness = 3
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = column
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = scroll
	text.Size = UDim2.new(1, -8, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	text.Parent = scroll
	self._text = text
	self._scroll = scroll

	local button = EventCardKit.button(card)
	if button then
		for _, c in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._connections, c)
		end
		for _, c in ipairs(UIMotion.bindHover(button)) do
			table.insert(self._connections, c)
		end
		table.insert(self._connections, button.Activated:Connect(function()
			self:close()
		end))
	end
	self._button = button

	local camera = workspace.CurrentCamera
	if camera then
		table.insert(self._connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if self._open then
				self:_layout()
			end
		end))
	end

	gui.Parent = playerGui
	return self
end

function EventPostPopupUI:onClose(callback: () -> ())
	self._onClose = callback
end

function EventPostPopupUI:isOpen(): boolean
	return self._open
end

-- Phone: banner left of a fixed-height text column. Desktop: banner (16:9) above it.
function EventPostPopupUI:_layout()
	local phone = PhoneLayout.isPhoneLayout()
	local hasImage = self._banner ~= nil and self._banner.Visible
	local list = self._bodyList
	local column = self._column :: Frame
	local banner = self._banner
	if phone then
		local width = if hasImage then PHONE.width else PHONE.widthNoImage
		local height = if hasImage then PHONE.height else PHONE.heightNoImage
		self._card.Size = UDim2.new(0, width, 0, 0)
		self._body.Size = UDim2.new(1, 0, 0, height)
		if list then
			list.FillDirection = Enum.FillDirection.Horizontal
			list.Padding = UDim.new(0, PHONE.gap)
		end
		if banner then
			banner.Size = UDim2.new(0, PHONE.bannerWidth, 1, 0)
		end
		local used = if hasImage then PHONE.bannerWidth + PHONE.gap else 0
		column.Size = UDim2.new(1, -used, 1, 0)
		self:_fit(Vector2.new(width, self._chromeHeight + height), PHONE.margin)
	else
		self._card.Size = UDim2.new(0, DESKTOP.width, 0, 0)
		local inner = DESKTOP.width - 2 * PAD
		local bannerHeight = math.floor(inner * 9 / 16)
		if list then
			list.FillDirection = Enum.FillDirection.Vertical
			list.Padding = UDim.new(0, PAD)
		end
		if banner then
			banner.Size = UDim2.new(1, 0, 0, bannerHeight)
		end
		column.Size = UDim2.new(1, 0, 0, DESKTOP.textHeight)
		local height = 2 * PAD + DESKTOP.textHeight + (if hasImage then bannerHeight + PAD else 0)
		self._body.Size = UDim2.new(1, 0, 0, height)
		self:_fit(Vector2.new(DESKTOP.width, self._chromeHeight + height), DESKTOP.margin)
	end
end

-- Shrinks the card (never grows it) until its design size fits the screen with `margin` around it.
-- The size comes from the layout, not AbsoluteSize, which the open pop animates.
function EventPostPopupUI:_fit(design: Vector2, margin: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local wanted = math.min(1, (viewport.X - 2 * margin) / design.X, (viewport.Y - 2 * margin) / design.Y)
	self._scale.Scale = math.max(wanted, 0.3)
end

function EventPostPopupUI:open(post: Post)
	local card = self._card
	EventCardKit.paintHeader(card, post.header)
	local column = self._column
	EventCardKit.setText(column, "Category", post.category)
	EventCardKit.setVisible(column, "Category", post.category ~= "")
	EventCardKit.setText(column, "Title", post.title)
	EventCardKit.setText(column, "Date", post.date)
	self._text.Text = post.body
	self._scroll.Visible = post.body ~= ""
	self._scroll.CanvasPosition = Vector2.zero
	if self._banner then
		self._banner.Image = if post.imageAssetId ~= "" then "rbxassetid://" .. post.imageAssetId else ""
		self._banner.Visible = post.imageAssetId ~= ""
	end
	if self._button then
		EventCardKit.setText(self._button, "TextLabel", post.closeText)
	end
	self._open = true
	self._gui.Enabled = true
	self:_layout()
	EventCardKit.remeasure(card)
	UIMotion.popIn(card, 0.94)
end

function EventPostPopupUI:close()
	if not self._open then
		return
	end
	self._open = false
	self._gui.Enabled = false
	if self._onClose then
		self._onClose()
	end
end

function EventPostPopupUI:destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
	self._gui:Destroy()
end

return EventPostPopupUI
