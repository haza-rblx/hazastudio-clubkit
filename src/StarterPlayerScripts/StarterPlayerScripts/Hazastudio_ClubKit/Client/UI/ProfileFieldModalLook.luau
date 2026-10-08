--!strict
-- Profile edit modal (UniversalModal) in the check-in popup look (owner, 2026-10-07; spec §3 of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md): a header bar ("Edit bio" + close) over a
-- body (field name, the Profile row hint, a centred input, a byte counter, Update).
-- Rebuilt in code from the modal's own pieces, so MenuShellUI's references and bindings keep
-- working: CancelButton becomes the header close button, Title the header label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.KitLook)

local ProfileFieldModalLook = {}

local WIDTH = 280
local C = KitLook.COLOR

-- Same copy as the Profile tab rows; limits mirror the server checks (byte length).
local FIELDS: { [string]: { name: string, hint: string, limit: (() -> number?)? } } = {
	displayNameOverride = {
		name = "Display Name",
		hint = "How others see you across this place.",
		limit = function()
			return tonumber(Config.ProfileMenu.DISPLAY_NAME_MAX_LENGTH)
		end,
	},
	specialTitle = { name = "Title", hint = "Customize your title here." },
	bio = {
		name = "Bio",
		hint = "Tell others a bit about yourself.",
		limit = function()
			return tonumber(Config.AvatarContext.BIO_MAX_LENGTH)
		end,
	},
	statusText = {
		name = "Status",
		hint = "Let people know what's up with you right now.",
		limit = function()
			return tonumber(Config.AvatarContext.STATUS_MAX_LENGTH)
		end,
	},
}

export type Refs = {
	universalModal: GuiObject?,
	modalTitle: TextLabel?,
	modalInput: TextBox?,
	modalCancelButton: TextButton?,
	modalUpdateButton: TextButton?,
}

export type Look = {
	configure: (field: string, title: string) -> (),
}

local function stripChrome(button: GuiButton)
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end
end

-- Cut to `limit` bytes without splitting a UTF-8 character.
local function clampBytes(text: string, limit: number): string
	if #text <= limit then
		return text
	end
	local cut = 0
	for position, codepoint in utf8.codes(text) do
		local width = #utf8.char(codepoint)
		if position - 1 + width > limit then
			break
		end
		cut = position - 1 + width
	end
	return string.sub(text, 1, cut)
end

function ProfileFieldModalLook.apply(refs: Refs): Look?
	local modal = refs.universalModal
	local title, input, cancel, update = refs.modalTitle, refs.modalInput, refs.modalCancelButton, refs.modalUpdateButton
	if not (modal and title and input and cancel and update) then
		return nil
	end
	local modalFrame = modal :: GuiObject
	local titleLabel = title :: TextLabel
	local inputBox = input :: TextBox
	local cancelButton = cancel :: TextButton
	local updateButton = update :: TextButton

	-- Transparent stack: header, 2px, body (the popup Card).
	modalFrame.BackgroundTransparency = 1
	modalFrame.Size = UDim2.new(0, WIDTH, modalFrame.Size.Y.Scale, modalFrame.Size.Y.Offset)
	for _, child in ipairs(modalFrame:GetChildren()) do
		if child:IsA("UIStroke") then
			child.Enabled = false
		elseif child:IsA("UIPadding") then
			child.PaddingLeft, child.PaddingRight = UDim.new(0, 0), UDim.new(0, 0)
			child.PaddingTop, child.PaddingBottom = UDim.new(0, 0), UDim.new(0, 0)
		end
	end
	local stack = modalFrame:FindFirstChildWhichIsA("UIListLayout") or KitLook.list(modalFrame, Enum.FillDirection.Vertical, 2)
	stack.Padding = UDim.new(0, 2)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- Header: "Edit <field>" + the old Cancel as a round close button.
	local header = KitLook.box(modalFrame, "Header", UDim2.new(1, 0, 0, 40), 0, C.header)
	KitLook.splitCorner(header, 18, 6)
	KitLook.padding(header, 12, 0, 6, 0)
	KitLook.shadow(header)
	KitLook.list(header, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
	titleLabel.Parent = header
	titleLabel.LayoutOrder = 1
	titleLabel.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = C.white
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Size = UDim2.new()
	titleLabel.AutomaticSize = Enum.AutomaticSize.XY
	KitLook.spacer(header, 2)

	cancelButton.Parent = header
	cancelButton.LayoutOrder = 3
	cancelButton.AnchorPoint = Vector2.zero
	cancelButton.Position = UDim2.new()
	cancelButton.Size = UDim2.fromOffset(28, 28)
	cancelButton.BackgroundColor3 = C.closeDisc
	cancelButton.BackgroundTransparency = 0
	cancelButton.TextTransparency = 1
	for _, child in ipairs(cancelButton:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") or child:IsA("UIPadding") then
			child:Destroy()
		elseif child:IsA("TextLabel") then
			child.Visible = false
		end
	end
	local cancelCorner = cancelButton:FindFirstChildWhichIsA("UICorner") or KitLook.corner(cancelButton, UDim.new(1, 0))
	cancelCorner.CornerRadius = UDim.new(1, 0)
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "CloseIcon"
	glyph.BackgroundTransparency = 1
	glyph.Image = KitLook.CLOSE_IMAGE
	glyph.ImageColor3 = C.closeGlyph
	glyph.Size = UDim2.fromOffset(16, 16)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Active = false
	glyph.Parent = cancelButton

	-- Body: field name + hint, input + counter, Update.
	local body = KitLook.box(modalFrame, "Body", UDim2.new(1, 0, 0, 0), 1, C.body)
	body.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.splitCorner(body, 6, 18)
	KitLook.padding(body, 12)
	KitLook.shadow(body)
	KitLook.list(body, Enum.FillDirection.Vertical, 12)

	local fieldHeader = KitLook.box(body, "FieldHeader", UDim2.new(1, 0, 0, 0), 0)
	fieldHeader.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.list(fieldHeader, Enum.FillDirection.Vertical, 2)
	local fieldTitle = KitLook.text(fieldHeader, "", 20, Enum.FontWeight.Bold, C.white, 0, { wrap = true })
	fieldTitle.Name = "FieldTitle"
	local hint = KitLook.text(fieldHeader, "", 14, Enum.FontWeight.SemiBold, C.bodyText, 1, { wrap = true })
	hint.Name = "Hint"

	local field = KitLook.box(body, "Field", UDim2.new(1, 0, 0, 0), 1)
	field.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.list(field, Enum.FillDirection.Vertical, 6)
	inputBox.Parent = field
	inputBox.LayoutOrder = 0
	inputBox.AnchorPoint = Vector2.zero
	inputBox.Position = UDim2.new()
	inputBox.Size = UDim2.new(1, 0, 0, 56)
	inputBox.BackgroundColor3 = C.row
	inputBox.BackgroundTransparency = 0
	inputBox.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
	inputBox.TextSize = 18
	inputBox.TextColor3 = C.white
	inputBox.TextXAlignment = Enum.TextXAlignment.Center
	inputBox.TextWrapped = true
	inputBox.ClipsDescendants = true
	inputBox.ClearTextOnFocus = false
	inputBox.PlaceholderColor3 = C.sub
	for _, child in ipairs(inputBox:GetChildren()) do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end
	local inputCorner = inputBox:FindFirstChildWhichIsA("UICorner") or KitLook.corner(inputBox, UDim.new(0, 8))
	inputCorner.CornerRadius = UDim.new(0, 8)
	local inputPadding = inputBox:FindFirstChildWhichIsA("UIPadding") or Instance.new("UIPadding")
	inputPadding.PaddingLeft, inputPadding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	inputPadding.PaddingTop, inputPadding.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	inputPadding.Parent = inputBox

	local counter = KitLook.text(field, "", 13, Enum.FontWeight.SemiBold, C.meta, 1, {
		align = Enum.TextXAlignment.Right,
	})
	counter.Name = "Counter"
	counter.Size = UDim2.new(1, 0, 0, 14)
	counter.AutomaticSize = Enum.AutomaticSize.None

	updateButton.Parent = body
	updateButton.LayoutOrder = 2
	updateButton.AnchorPoint = Vector2.zero
	updateButton.Position = UDim2.new()
	updateButton.Size = UDim2.new(1, 0, 0, 38)
	updateButton.BackgroundTransparency = 0
	-- MenuShellUI writes "Update" to both the button and its label; only the label shows.
	updateButton.TextTransparency = 1
	stripChrome(updateButton)
	for _, child in ipairs(updateButton:GetChildren()) do
		if child:IsA("UIPadding") then
			child.PaddingTop, child.PaddingBottom = UDim.new(0, 0), UDim.new(0, 0)
		elseif child:IsA("TextLabel") then
			child.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
			child.TextSize = 15
			child.TextColor3 = C.white
		end
	end

	local limit: number? = nil
	local editing = false
	local function paintCounter()
		counter.Visible = limit ~= nil
		if limit then
			counter.Text = string.format("%d / %d", #inputBox.Text, limit)
			counter.TextColor3 = if #inputBox.Text >= limit then C.danger else C.meta
		end
	end
	inputBox:GetPropertyChangedSignal("Text"):Connect(function()
		if editing then
			return
		end
		-- Typing stops at the server's limit instead of failing on Update.
		if limit and #inputBox.Text > limit then
			editing = true
			inputBox.Text = clampBytes(inputBox.Text, limit)
			editing = false
		end
		paintCounter()
	end)

	return {
		configure = function(fieldId: string, rawTitle: string)
			local spec = FIELDS[fieldId]
			local name = if spec then spec.name else rawTitle
			titleLabel.Text = "Edit " .. string.lower(name)
			fieldTitle.Text = name
			hint.Text = if spec then spec.hint else ""
			hint.Visible = hint.Text ~= ""
			inputBox.PlaceholderText = "Your " .. string.lower(name)
			limit = if spec and spec.limit then spec.limit() else nil
			paintCounter()
		end,
	}
end

return ProfileFieldModalLook
